#!/usr/bin/env bash

# Setzt die TERM-Variable, um die Kompatibilität mit whiptail zu verbessern
export TERM=xterm

# --- Proxmox Helper Skript für Nextcloud ---
# Erstellt einen neuen LXC-Container und installiert Nextcloud darin.

# Farben und Helper-Funktionen (aus tteck's Skripten inspiriert)
YW='\033[33m' # Yellow
BL='\033[36m' # Blue
RD='\033[01;31m' # Red
GN='\033[1;92m' # Green
CL='\033[m' # Clear
BOLD='\033[1m'

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"

# Fehlerbehandlung
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  echo -e "\n${RD}[FEHLER]${CL} in Zeile ${RD}$line_number${CL}: Exit-Code ${RD}$exit_code${CL}: Befehl ${YW}$command${CL} fehlgeschlagen.\n"
  cleanup_lxc
  exit 1
}
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

function cleanup_lxc() {
  if pct status $VMID &>/dev/null; then
    pct stop $VMID &>/dev/null
    pct destroy $VMID &>/dev/null
  fi
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

# Überprüfen auf root-Rechte
check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    clear
    echo -e "${CROSS}${RD}Dieses Skript muss als root ausgeführt werden.${CL}\n"
    exit 1
  fi
}

# PVE-Versionsprüfung (nur für Proxmox VE 8.x oder 9.0)
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      echo -e "${CROSS}${RD}Diese Proxmox VE Version wird nicht unterstützt.${CL}"
      echo -e "${INFO}Unterstützt: Proxmox VE 8.0 – 8.9\n"
      exit 1
    fi
    return 0
  fi

  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR != 0)); then
      echo -e "${CROSS}${RD}Diese Proxmox VE Version wird noch nicht unterstützt.${CL}"
      echo -e "${INFO}Unterstützt: Proxmox VE 9.0\n"
      exit 1
    fi
    return 0
  fi

  echo -e "${CROSS}${RD}Diese Proxmox VE Version wird nicht unterstützt.${CL}"
  echo -e "${INFO}Unterstützt: Proxmox VE 8.0 – 8.x oder 9.0\n"
  exit 1
}

# SSH-Prüfung (Warnung, falls über SSH ausgeführt)
ssh_check() {
  if [ -n "${SSH_CLIENT:+x}" ]; then
    if ! whiptail --backtitle "Bastis Proxmox Help Script" --defaultno --title "SSH ERKANNT" --yesno "Es wird empfohlen, die Proxmox-Shell anstelle von SSH zu verwenden, da SSH Probleme beim Sammeln von Variablen verursachen kann. Möchten Sie trotzdem fortfahren?" 10 62; then
      clear
      echo -e "${CROSS}${RD}Benutzer hat Skript beendet.${CL}\n"
      exit 0
    fi
  fi
}

# Hauptfunktionalität des Skripts
main() {
  check_root
  pve_check
  ssh_check

  clear
  echo -e "${BOLD}${GN}--- Nextcloud LXC-Container Erstellung ---${CL}\n"
  echo "Dieses Skript erstellt einen neuen LXC-Container und installiert Nextcloud darin."
  if ! whiptail --backtitle "Bastis Proxmox Help Script" --title "Nextcloud LXC" --yesno "Möchten Sie fortfahren?" 10 58; then
    echo -e "${CROSS}${RD}Benutzer hat Skript beendet.${CL}\n"
    exit 0
  fi

  # Standardwerte setzen
  VMID=$(get_valid_nextid)
  HOSTNAME="nextcloud-lxc"
  CPU_CORES="2"
  RAM_SIZE="2048" # MiB
  DISK_SIZE="32" # GiB
  BRIDGE="vmbr0"
  OS_TEMPLATE="ubuntu-24.04-standard" # Standard-Template

  # --- LXC Konfigurationsabfragen ---
  if ! VMID=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Container ID festlegen:" 8 58 "$VMID" --title "LXC ID" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
      echo -e "${CROSS}${RD} ID $VMID ist bereits in Verwendung. Bitte wähle eine andere ID.${CL}"
      exit 1
  fi
  echo -e "${CONTAINERID}${BOLD}${GN}Container ID: ${BL}${VMID}${CL}"

  if ! HOSTNAME=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Hostname festlegen:" 8 58 "$HOSTNAME" --title "HOSTNAME" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${HOSTNAME}${BOLD}${GN}Hostname: ${BL}${HOSTNAME}${CL}"

  if ! CPU_CORES=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Anzahl der CPU-Kerne zuweisen:" 8 58 "$CPU_CORES" --title "CPU-KERNE" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${CPUCORE}${BOLD}${GN}CPU-Kerne: ${BL}${CPU_CORES}${CL}"

  if ! RAM_SIZE=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "RAM in MiB zuweisen:" 8 58 "$RAM_SIZE" --title "RAM" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${RAMSIZE}${BOLD}${GN}RAM (MiB): ${BL}${RAM_SIZE}${CL}"

  if ! DISK_SIZE=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Festplattengröße in GiB zuweisen:" 8 58 "$DISK_SIZE" --title "DISK-GRÖSSE" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DISKSIZE}${BOLD}${GN}Festplattengröße (GiB): ${BL}${DISK_SIZE}${CL}"

  # Bridge-Auswahl
  msg_info "Gültige Bridge-Standorte werden gesucht..."
  BRIDGE_MENU=()
  while read -r line; do
    TAG=$(echo $line | awk '{print $1}')
    ITEM="Bridge: $(echo $line | awk '{print $1}')"
    BRIDGE_MENU+=("$TAG" "$ITEM" "OFF")
  done < <(brctl show | grep -E "^(vmbr|br)-[0-9]+" | awk '{print $1}')
  
  VALID_BRIDGES=$(brctl show | grep -E "^(vmbr|br)-[0-9]+")
  if [ -z "$VALID_BRIDGES" ]; then
    echo -e "${CROSS}${RD}Keine gültige Bridge gefunden. Bitte stelle sicher, dass eine Bridge (z.B. vmbr0) existiert.${CL}\n"
    exit 1
  elif [ $((${#BRIDGE_MENU[@]} / 3)) -eq 1 ]; then
    BRIDGE=${BRIDGE_MENU[0]}
    echo -e "${BRIDGE}${BOLD}${GN}Bridge: ${BL}$BRIDGE${CL}"
  else
    if ! BRIDGE=$(whiptail --backtitle "Bastis Proxmox Help Script" --title "BRIDGE AUSWÄHLEN" --radiolist "Welche Bridge soll für den LXC verwendet werden?" 10 58 3 "${BRIDGE_MENU[@]}" 3>&1 1>&2 2>&3); then
      echo -e "${CROSS}${RD}Benutzer hat Skript beendet.${CL}\n"
      exit 0
    fi
    echo -e "${BRIDGE}${BOLD}${GN}Bridge: ${BL}$BRIDGE${CL}"
  fi


  # OS-Template-Auswahl (Ubuntu/Debian)
  OS_MENU=(
    "ubuntu-24.04-standard" "Ubuntu 24.04 (Noble Numbat)" ON
    "ubuntu-22.04-standard" "Ubuntu 22.04 (Jammy Jellyfish)" OFF
    "debian-12-standard" "Debian 12 (Bookworm)" OFF
    "debian-11-standard" "Debian 11 (Bullseye)" OFF
  )
  if ! OS_TEMPLATE=$(whiptail --backtitle "Bastis Proxmox Help Script" --title "BETRIEBSSYSTEM-TEMPLATE" --radiolist "Wähle ein OS-Template für den Container:" 14 58 5 "${OS_MENU[@]}" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${OS}${BOLD}${GN}OS-Template: ${BL}${OS_TEMPLATE}${CL}"


  # --- Nextcloud Konfigurationsabfragen ---
  echo -e "\n${BOLD}${GN}--- Nextcloud-Anwendungs-Einstellungen ---${CL}\n"

  if ! NEXTCLOUD_DOMAIN=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Domain / Hostname (z.B. nextcloud.local oder IP-Adresse):" 8 58 "nextcloud.local" --title "NEXTCLOUD DOMAIN/IP" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Nextcloud Domain/IP: ${BL}${NEXTCLOUD_DOMAIN}${CL}"

  if ! DB_NAME=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Datenbank-Name (Standard: nextcloud):" 8 58 "nextcloud" --title "DATENBANK-NAME" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Datenbank-Name: ${BL}${DB_NAME}${CL}"

  if ! DB_USER=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Datenbank-Benutzer (Standard: nextcloud_user):" 8 58 "nextcloud_user" --title "DATENBANK-BENUTZER" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; CURR_DB_USER="nextcloud_user"; fi
  echo -e "${DEFAULT}${BOLD}${GN}Datenbank-Benutzer: ${BL}${DB_USER}${CL}"

  if ! DB_PASSWORD=$(whiptail --backtitle "Bastis Proxmox Help Script" --passwordbox "Datenbank-Passwort eingeben:" 8 58 --title "DATENBANK-PASSWORT" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Datenbank-Passwort: ${BL}********${CL}"

  if ! NC_ADMIN_USER=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Nextcloud Admin-Benutzer (Standard: admin):" 8 58 "admin" --title "NEXTCLOUD ADMIN-BENUTZER" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Nextcloud Admin-Benutzer: ${BL}${NC_ADMIN_USER}${CL}"

  if ! NC_ADMIN_PASSWORD=$(whiptail --backtitle "Bastis Proxmox Help Script" --passwordbox "Nextcloud Admin-Passwort eingeben:" 8 58 --title "NEXTCLOUD ADMIN-PASSWORT" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Nextcloud Admin-Passwort: ${BL}********${CL}"

  if ! DEFAULT_PHONE_REGION=$(whiptail --backtitle "Bastis Proxmox Help Script" --inputbox "Standard-Telefonregion (z.B. DE für Deutschland):" 8 58 "DE" --title "TELEFONREGION" --cancel-button "Abbrechen" 3>&1 1>&2 2>&3); then exit 1; fi
  echo -e "${DEFAULT}${BOLD}${GN}Standard-Telefonregion: ${BL}${DEFAULT_PHONE_REGION}${CL}"

  # Bestätigung vor der Erstellung
  echo -e "\n${CREATING}${BOLD}${GN}Erstelle Nextcloud LXC-Container mit den oben genannten Einstellungen...${CL}\n"
  if ! whiptail --backtitle "Bastis Proxmox Help Script" --title "Einstellungen überprüfen" --yesno "Sind die Einstellungen korrekt und möchten Sie fortfahren?" 10 58; then
    echo -e "${CROSS}${RD}Benutzer hat Skript beendet.${CL}\n"
    exit 0
  fi

  # --- LXC-Container erstellen ---
  echo -e "${INFO}Container ${VMID} wird erstellt mit Template ${OS_TEMPLATE}...${CL}"
  pct create $VMID --hostname $HOSTNAME --ostype $(echo $OS_TEMPLATE | cut -d'-' -f1) --template $(pveam path ${OS_TEMPLATE}) --cores $CPU_CORES --memory $RAM_SIZE --rootfs ${DISK_SIZE}G --net0 name=eth0,bridge=$BRIDGE,ip=dhcp
  
  echo -e "${CM}LXC-Container ${VMID} '${HOSTNAME}' erfolgreich erstellt.${CL}"
  
  echo -e "${INFO}Warte, bis der Container gestartet ist...${CL}"
  pct start $VMID
  sleep 10 # Wartezeit, damit der Container booten kann

  echo -e "${INFO}IP-Adresse des Containers wird abgerufen...${CL}"
  # Warte auf IP-Adresse
  COUNTER=0
  while [ -z "$CONTAINER_IP" ] && [ $COUNTER -lt 30 ]; do
    CONTAINER_IP=$(pct exec $VMID ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    sleep 2
    COUNTER=$((COUNTER + 1))
  done

  if [ -z "$CONTAINER_IP" ]; then
    echo -e "${CROSS}${RD}Konnte IP-Adresse des Containers nicht abrufen. Bitte manuell überprüfen.${CL}\n"
    exit 1
  fi
  echo -e "${CM}Container IP-Adresse: ${BL}${CONTAINER_IP}${CL}"

  # --- Nextcloud Installationsskript in den Container kopieren und ausführen ---
  echo -e "${INFO}Nextcloud Installationsskript wird in den Container kopiert und ausgeführt...${CL}"

  # Das Nextcloud Installationsskript (Teil 2) als String definieren
  # Alle Variablen aus den whiptail-Abfragen werden hier direkt eingefügt
  NEXTCLOUD_INSTALL_SCRIPT=$(cat <<'EOF'
#!/bin/bash

# Farben für die Ausgabe definieren (via tput für bessere Kompatibilität)
GREEN=\$(tput setaf 2)
NC=\$(tput sgr0) # No Color

echo ""
echo "\${GREEN}--- Beginne Nextcloud-Installation im LXC-Container --- \${NC}"
echo ""

# Übergebene Variablen (keine erneute Abfrage)
NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
NC_ADMIN_USER="${NC_ADMIN_USER}"
NC_ADMIN_PASSWORD="${NC_ADMIN_PASSWORD}"
DEFAULT_PHONE_REGION="${DEFAULT_PHONE_REGION}"

# --- Skript nur als root ausführen (innerhalb des Containers) ---
if [ "\$(id -u)" != "0" ]; then
   echo "Dieses Skript muss als root ausgeführt werden." 1>&2
   exit 1
fi

# --- System aktualisieren und notwendige Pakete installieren ---
echo ""
echo "\${GREEN}=== SCHRITT 1: SYSTEM AKTUALISIEREN & PAKETE INSTALLIEREN ===\${NC}"
echo ""
echo "Dies kann einige Minuten dauern. Es werden Apache, MariaDB, PHP und deren Module installiert."
echo ""
apt-get update -y
apt-get upgrade -y
apt-get install -y ncurses-bin lsb-release # Sicherstellen, dass diese da sind
echo ""

# --- MariaDB Repository hinzufügen und neueste Version installieren ---
echo ""
echo "\${GREEN}=== SCHRITT 2: MARIADB-REPOSITORY HINZUFÜGEN & SERVER INSTALLIEREN ===\${NC}"
echo ""
echo "Dadurch wird die neueste Version von MariaDB bezogen, und die Repository-URL wird automatisch an Ihre Distribution angepasst."
echo ""
DISTRO_CODENAME=\$(lsb_release -cs)
DISTRO_ID=\$(lsb_release -is | tr '[:upper:]' '[:lower:]')

apt-get install -y curl software-properties-common apt-transport-https

curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | \\
sudo bash -s -- --mariadb-server-version="mariadb-11.4" --os-type="\${DISTRO_ID}" --os-version="\${DISTRO_CODENAME}"

apt-get update -y
apt-get install -y mariadb-server
echo ""

# --- Restliche Nextcloud-Pakete und PHP-Module installieren ---
echo ""
echo "\${GREEN}=== SCHRITT 3: NEXTCLOUD-PAKETE & PHP-MODULE INSTALLIEREN ===\${NC}"
echo ""
echo "Dazu gehören die PHP-Module, die Nextcloud benötigt."
echo ""
apt-get install -y apache2 libapache2-mod-php php-gd php-curl php-zip php-xml php-mbstring php-imagick php-gmp php-bcmath php-intl php-ldap php-apcu php-mysql php-cli php-fpm unzip librsvg2-bin libmagickwand-dev
echo ""

# --- PHP-Konfiguration anpassen ---
echo ""
echo "\${GREEN}=== SCHRITT 4: PHP-KONFIGURATION ANPASSEN ===\${NC}"
echo ""
echo "Hier wird das Speicherlimit erhöht und der OPcache für eine bessere Performance optimiert."
echo ""
PHP_VERSION=\$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_INI_PATH="/etc/php/\${PHP_VERSION}/apache2/php.ini"

if [ -f "\$PHP_INI_PATH" ]; then
    sed -i "s/memory_limit = .*/memory_limit = 512M/" "\$PHP_INI_PATH"
    sed -i "s/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=32/" "\$PHP_INI_PATH"
else
    echo "Warnung: Die PHP-Konfigurationsdatei \$PHP_INI_PATH wurde nicht gefunden. Bitte manuell überprüfen."
fi
echo ""

# --- Apache Konfiguration ---
echo ""
echo "\${GREEN}=== SCHRITT 5: APACHE KONFIGURIEREN ===\${NC}"
echo ""
echo "Hier werden die benötigten Module aktiviert und der Webserver neu gestartet."
echo ""
a2enmod rewrite dir headers env mime
systemctl restart apache2
echo ""

# --- Datenbank konfigurieren ---
echo ""
echo "\${GREEN}=== SCHRITT 6: DATENBANK KONFIGURIEREN ===\${NC}"
echo ""
echo "Eine neue Datenbank und ein Benutzer werden mit den von dir eingegebenen Daten erstellt."
echo ""
mariadb -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`\${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '\${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`\${DB_NAME}\`.* TO '\${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo ""

# --- Nextcloud herunterladen und entpacken ---
echo ""
echo "\${GREEN}=== SCHRITT 7: NEXTCLOUD HERUNTERLADEN & ENTPACKEN ===\${NC}"
echo ""
echo "Die neueste Nextcloud-Version wird aus dem Internet heruntergeladen und im Webverzeichnis entpackt."
echo ""
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
mv nextcloud /var/www/html/
chown -R www-data:www-data /var/www/html/nextcloud
chmod -R 755 /var/www/html/nextcloud
rm latest.zip
echo ""

# --- Apache Virtual Host für Nextcloud erstellen ---
echo ""
echo "\${GREEN}=== SCHRITT 8: APACHE VIRTUAL HOST ERSTELLEN & KONFIGURIEREN ===\${NC}"
echo ""
echo "Hier wird eine neue Apache-Konfiguration erstellt und aktiviert."
echo ""
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
   ServerName \${NEXTCLOUD_DOMAIN}
   DocumentRoot /var/www/html/nextcloud
   
   <Directory /var/www/html/nextcloud>
       Require all granted
       AllowOverride All
       Options FollowSymlinks Multiviews
       <IfModule mod_dav.c>
           Dav off
       </IfModule>
   </Directory>
   
   <IfModule mod_headers.c>
       Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
   </IfModule>
   
   ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
   CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# --- Nextcloud Virtual Host aktivieren ---
a2ensite nextcloud.conf
a2dissite 000-default.conf
systemctl restart apache2
echo ""

# --- Nextcloud Konfiguration und CLI-Installation ---
echo ""
echo "\${GREEN}=== SCHRITT 9: NEXTCLOUD ÜBER DIE KOMMANDOZEILE INSTALLIEREN & KONFIGURIEREN ===\${NC}"
echo ""
echo "Dieser letzte Schritt verbindet die Anwendung mit der Datenbank und schließt die Installation ab."
echo ""
sudo -u www-data php /var/www/html/nextcloud/occ maintenance:install \\
--database "mysql" \\
--database-name="\${DB_NAME}" \\
--database-user="\${DB_USER}" \\
--database-pass="\${DB_PASSWORD}" \\
--data-dir="/var/www/html/nextcloud/data" \\
--admin-user="\${NC_ADMIN_USER}" \\
--admin-pass="\${NC_ADMIN_PASSWORD}"
echo ""

# --- Zusätzliche Konfigurationen und Reparaturen ---
echo ""
echo "\${GREEN}=== SCHRITT 10: ZUSÄTZLICHE KONFIGURATIONEN & REPARATUREN DURCHFÜHREN ===\${NC}"
echo ""
echo "Es werden letzte Optimierungen und Reparaturen vorgenommen, um die verbleibenden Warnungen zu beheben."
echo ""
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set trusted_domains 1 --value="\${NEXTCLOUD_DOMAIN}"
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set default_phone_region --value="\${DEFAULT_PHONE_REGION}"
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set maintenance_window_start --value="1" # Startet Wartung um 1 Uhr morgens
sudo -u www-data php /var/www/html/nextcloud/occ maintenance:repair --include-expensive
echo ""

echo ""
echo "--- Installation abgeschlossen! ---"
echo "Du kannst jetzt die Weboberfläche unter \${GREEN}http://\${NEXTCLOUD_DOMAIN}\${NC} aufrufen."
echo "Admin-Benutzer: \${NC_ADMIN_USER}"
echo "Admin-Passwort: \${NC_ADMIN_PASSWORD}"
echo ""
EOF
)

  # Das Skript in den Container kopieren und ausführbar machen
  pct exec $VMID bash -c "echo '$NEXTCLOUD_INSTALL_SCRIPT' > /opt/install_nextcloud_in_lxc.sh"
  pct exec $VMID chmod +x /opt/install_nextcloud_in_lxc.sh

  # Das Skript im Container ausführen
  echo -e "${INFO}Starte Nextcloud-Installation im LXC-Container...${CL}"
  pct exec $VMID /opt/install_nextcloud_in_lxc.sh

  echo -e "${CM}Nextcloud-Installation im Container abgeschlossen!${CL}"
  echo -e "Du kannst jetzt die Weboberfläche unter ${BL}http://${NEXTCLOUD_DOMAIN}${CL} erreichen."
  echo -e "Admin-Benutzer: ${BL}${NC_ADMIN_USER}${CL}"
  echo -e "Admin-Passwort: ${BL}${NC_ADMIN_PASSWORD}${CL}"
  echo -e "\n${BOLD}${GN}Viel Erfolg mit deiner Nextcloud!${CL}\n"
}

# Skript starten
main
