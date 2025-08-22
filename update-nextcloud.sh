#!/bin/bash

# Farben für die Ausgabe definieren
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
NC=$(tput sgr0) # No Color

# --- Skript nur als root ausführen ---
if [ "$(id -u)" != "0" ]; then
    echo "${RED}Fehler: Dieses Skript muss als root ausgeführt werden.${NC}"
    exit 1
fi

# --- Konfiguration ---
NEXTCLOUD_PATH="/var/www/html/nextcloud"
BACKUP_BASE_DIR="/var/www/html"
# API-URL, um die neueste Hauptversion zu finden
RELEASES_URL="https://updates.nextcloud.com/updater_server/releases/"

echo ""
echo "${GREEN}--- Intelligentes Nextcloud-Update-Skript ---${NC}"
echo ""
echo "Dieses Skript wird deine Nextcloud-Instanz automatisch schrittweise aktualisieren."
echo "Bitte stelle unbedingt sicher, dass du ein aktuelles Backup deiner Dateien und Datenbank hast!"
read -p "Drücke Enter, um fortzufahren..."

# --- Abhängigkeiten installieren (jq für JSON-Parsing) ---
echo "${YELLOW}=== Prüfe und installiere Abhängigkeiten (jq)...${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y jq >/dev/null 2>&1
echo "${GREEN}Abhängigkeiten installiert.${NC}"

# --- Haupt-Update-Schleife ---
while true; do
    # Aktuelle Version der installierten Nextcloud-Instanz abrufen
    CURRENT_VERSION_STRING=$(su -s /bin/bash -c "php ${NEXTCLOUD_PATH}/occ status --no-ansi | grep 'versionstring' | cut -d':' -f2 | xargs" www-data)
    CURRENT_MAJOR_VERSION=$(echo "$CURRENT_VERSION_STRING" | cut -d'.' -f1)

    # Prüfen, ob die Ausgabe gültig ist
    if [ -z "$CURRENT_VERSION_STRING" ]; then
        echo "${RED}Fehler: Konnte die aktuelle Nextcloud-Version nicht ermitteln. Bitte die manuelle Installation überprüfen.${NC}"
        exit 1
    fi
    echo "${YELLOW}Aktuell installierte Version: ${CURRENT_VERSION_STRING}${NC}"

    # Informationen zur neuesten Version abrufen
    LATEST_VERSION_STRING=$(curl -s $RELEASES_URL | jq -r '.[-1].version_string')
    LATEST_MAJOR_VERSION=$(echo "$LATEST_VERSION_STRING" | cut -d'.' -f1)

    # Prüfen, ob die aktuelle Version die neueste ist
    if [ "$CURRENT_VERSION_STRING" == "$LATEST_VERSION_STRING" ]; then
        echo "${GREEN}Deine Nextcloud-Instanz ist bereits auf der neuesten Version (${LATEST_VERSION_STRING}).${NC}"
        break
    fi

    # Die nächste zu aktualisierende Version finden
    NEXT_MAJOR_VERSION=$((CURRENT_MAJOR_VERSION + 1))
    
    if [ "$NEXT_MAJOR_VERSION" -ge "$LATEST_MAJOR_VERSION" ]; then
        # Wenn die nächste Version die neueste ist, verwende latest.zip
        NEXT_DOWNLOAD_URL="https://download.nextcloud.com/server/releases/latest.zip"
        VERSION_TO_UPGRADE_TO="Latest"
    else
        # Andernfalls verwende den latest-Versions-Link
        NEXT_DOWNLOAD_URL="https://download.nextcloud.com/server/releases/latest-${NEXT_MAJOR_VERSION}.zip"
        VERSION_TO_UPGRADE_TO="${NEXT_MAJOR_VERSION}"
    fi

    echo "${YELLOW}--- Bereite Upgrade auf Nextcloud ${VERSION_TO_UPGRADE_TO} vor ---${NC}"

    # --- SCHRITT 1: Wartungsmodus aktivieren ---
    echo "${YELLOW}=== 1/4: Nextcloud in den Wartungsmodus versetzen...${NC}"
    su -s /bin/bash -c "php ${NEXTCLOUD_PATH}/occ maintenance:mode --on" www-data
    echo "${GREEN}Wartungsmodus aktiviert.${NC}"

    # --- SCHRITT 2: Dateien herunterladen & ersetzen ---
    echo "${YELLOW}=== 2/4: Version ${VERSION_TO_UPGRADE_TO} herunterladen und ersetzen...${NC}"
    rm -rf /tmp/nextcloud-update
    mkdir -p /tmp/nextcloud-update
    wget -O /tmp/nextcloud-update/nextcloud.zip $NEXT_DOWNLOAD_URL >/dev/null 2>&1
    unzip -q /tmp/nextcloud-update/nextcloud.zip -d /tmp/nextcloud-update/

    BACKUP_DIR="${BACKUP_BASE_DIR}/nextcloud_backup_$(date +%Y%m%d%H%M%S)"
    cp -a ${NEXTCLOUD_PATH} ${BACKUP_DIR}

    # Neuen Ordner leeren, außer 'config' und 'data'
    find ${NEXTCLOUD_PATH}/ -mindepth 1 -maxdepth 1 -not -name "config" -not -name "data" -exec rm -rf {} +

    # Neue Dateien kopieren
    cp -a /tmp/nextcloud-update/nextcloud/. ${NEXTCLOUD_PATH}/
    rm -rf /tmp/nextcloud-update
    echo "${GREEN}Dateien erfolgreich ersetzt. Sicherung unter ${BACKUP_DIR}${NC}"

    # --- SCHRITT 3: Berechtigungen setzen ---
    echo "${YELLOW}=== 3/4: Berechtigungen korrigieren...${NC}"
    chown -R www-data:www-data ${NEXTCLOUD_PATH}
    echo "${GREEN}Berechtigungen wurden korrigiert.${NC}"

    # --- SCHRITT 4: Upgrade-Prozess starten ---
    echo "${YELLOW}=== 4/4: Upgrade auf Version ${VERSION_TO_UPGRADE_TO} ausführen...${NC}"
    su -s /bin/bash -c "php ${NEXTCLOUD_PATH}/occ upgrade" www-data
    if [ $? -ne 0 ]; then
        echo "${RED}Fehler: Upgrade auf ${VERSION_TO_UPGRADE_TO} fehlgeschlagen. Überprüfe die Logs.${NC}"
        # Wartungsmodus anlassen, damit die Fehler behoben werden können
        su -s /bin/bash -c "php ${NEXTCLOUD_PATH}/occ maintenance:mode --on" www-data
        exit 1
    fi
    echo "${GREEN}Upgrade auf ${VERSION_TO_UPGRADE_TO} erfolgreich abgeschlossen!${NC}"
done

# --- Finalisierung ---
su -s /bin/bash -c "php ${NEXTCLOUD_PATH}/occ maintenance:mode --off" www-data
echo "${GREEN}Nextcloud ist wieder online!${NC}"
echo ""
echo "${GREEN}--- Update-Vorgang abgeschlossen! ---${NC}"
echo "Deine Nextcloud-Instanz ist jetzt auf der neuesten Version (${LATEST_VERSION_STRING})."
echo ""
