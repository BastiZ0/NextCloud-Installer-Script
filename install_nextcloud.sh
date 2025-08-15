#!/bin/bash

# Farben für die Ausgabe definieren (via tput für bessere Kompatibilität)
# Stellen Sie sicher, dass 'ncurses-bin' installiert ist (enthält tput)
# tput setaf 2 setzt Vordergrundfarbe auf Grün
# tput sgr0 setzt alle Attribute zurück (Farbe und Formatierung)
GREEN=$(tput setaf 2)
NC=$(tput sgr0) # No Color

echo ""
echo "${GREEN}--- Willkommen zur interaktiven Nextcloud-Installation ---${NC}"
echo ""
read -p "Domain / Hostname (z.B. nextcloud.local oder IP-Adresse): " NEXTCLOUD_DOMAIN
read -p "Datenbank-Name (Standard: nextcloud): " DB_NAME
DB_NAME=${DB_NAME:-nextcloud}
read -p "Datenbank-Benutzer (Standard: nextcloud_user): " DB_USER
DB_USER=${DB_USER:-nextcloud_user}
read -p "Nextcloud Admin-Benutzer (Standard: admin): " NC_ADMIN_USER
NC_ADMIN_USER=${NC_ADMIN_USER:-admin}
read -p "Standard-Telefonregion (z.B. DE für Deutschland): " DEFAULT_PHONE_REGION
DEFAULT_PHONE_REGION=${DEFAULT_PHONE_REGION:-DE}

echo ""
echo "--- Passwörter festlegen ---"
read -p "Datenbank-Passwort: " DB_PASSWORD
read -p "Nextcloud Admin-Passwort: " NC_ADMIN_PASSWORD
echo ""

# --- Skript nur als root ausführen ---
if [ "$(id -u)" != "0" ]; then
   echo "Dieses Skript muss als root ausgeführt werden." 1>&2
   exit 1
fi

# --- System aktualisieren und notwendige Pakete installieren ---
echo ""
echo "${GREEN}=== SCHRITT 1: SYSTEM AKTUALISIEREN & PAKETE INSTALLIEREN ===${NC}"
echo ""
echo "Dies kann einige Minuten dauern. Es werden Apache, MariaDB, PHP und deren Module installiert."
echo ""
read -p "Drücke Enter, um fortzufahren..."
apt-get update
apt-get upgrade -y
# ncurses-bin für tput und lsb-release für die Distribution-Erkennung hinzufügen
apt-get install -y ncurses-bin lsb-release
echo "" # Zusätzlicher Absatz nach dem Befehl


# --- MariaDB Repository hinzufügen und neueste Version installieren ---
echo ""
echo "${GREEN}=== SCHRITT 2: MARIADB-REPOSITORY HINZUFÜGEN & SERVER INSTALLIEREN ===${NC}"
echo ""
echo "Dadurch wird die neueste Version von MariaDB bezogen, und die Repository-URL wird automatisch an Ihre Distribution angepasst."
echo ""
read -p "Drücke Enter, um fortzufahren..."
# Dynamische Erkennung des Distribution-Codenames und des ID-Namens (ubuntu oder debian)
DISTRO_CODENAME=$(lsb_release -cs)
DISTRO_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]') # z.B. "Ubuntu" -> "ubuntu", "Debian" -> "debian"

apt-get install -y curl software-properties-common apt-transport-https

# Das offizielle MariaDB Repository Setup-Skript verwenden
# Es kümmert sich um den GPG-Key und die sources.list.d-Datei
# Wir erzwingen Version 11.4, aber es kann auch eine aktuellere stabile Version wählen
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | \
sudo bash -s -- --mariadb-server-version="mariadb-11.4" --os-type="${DISTRO_ID}" --os-version="${DISTRO_CODENAME}"

# Nach dem Hinzufügen des Repositories apt-update ausführen
apt-get update
apt-get install -y mariadb-server
echo ""


# --- Restliche Nextcloud-Pakete und PHP-Module installieren ---
echo ""
echo "${GREEN}=== SCHRITT 3: NEXTCLOUD-PAKETE & PHP-MODULE INSTALLIEREN ===${NC}"
echo ""
echo "Dazu gehören die PHP-Module, die Nextcloud benötigt."
echo ""
read -p "Drücke Enter, um fortzufahren..."
apt-get install -y apache2 libapache2-mod-php php-gd php-curl php-zip php-xml php-mbstring php-imagick php-gmp php-bcmath php-intl php-ldap php-apcu php-mysql php-cli php-fpm unzip librsvg2-bin libmagickwand-dev
echo ""


# --- PHP-Konfiguration anpassen ---
echo ""
echo "${GREEN}=== SCHRITT 4: PHP-KONFIGURATION ANPASSEN ===${NC}"
echo ""
echo "Hier wird das Speicherlimit erhöht und der OPcache für eine bessere Performance optimiert."
echo ""
read -p "Drücke Enter, um fortzufahren..."
# Dynamische Erkennung des PHP-INI-Pfades für Apache
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_INI_PATH="/etc/php/${PHP_VERSION}/apache2/php.ini"

if [ -f "$PHP_INI_PATH" ]; then
    sed -i "s/memory_limit = .*/memory_limit = 512M/" "$PHP_INI_PATH"
    sed -i "s/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=32/" "$PHP_INI_PATH"
else
    echo "Warnung: Die PHP-Konfigurationsdatei $PHP_INI_PATH wurde nicht gefunden. Bitte manuell überprüfen."
fi
echo ""


# --- Apache Konfiguration ---
echo ""
echo "${GREEN}=== SCHRITT 5: APACHE KONFIGURIEREN ===${NC}"
echo ""
echo "Hier werden die benötigten Module aktiviert und der Webserver neu gestartet."
echo ""
read -p "Drücke Enter, um fortzufahren..."
a2enmod rewrite dir headers env mime
systemctl restart apache2
echo ""


# --- Datenbank konfigurieren ---
echo ""
echo "${GREEN}=== SCHRITT 6: DATENBANK KONFIGURIEREN ===${NC}"
echo ""
echo "Eine neue Datenbank und ein Benutzer werden mit den von dir eingegebenen Daten erstellt."
echo ""
read -p "Drücke Enter, um fortzufahren..."
# Geänderter Befehl: 'mysql' durch 'mariadb' ersetzt
mariadb -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo ""


# --- Nextcloud herunterladen und entpacken ---
echo ""
echo "${GREEN}=== SCHRITT 7: NEXTCLOUD HERUNTERLADEN & ENTPACKEN ===${NC}"
echo ""
echo "Die neueste Nextcloud-Version wird aus dem Internet heruntergeladen und im Webverzeichnis entpackt."
echo ""
read -p "Drücke Enter, um fortzufahren..."
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
mv nextcloud /var/www/html/
chown -R www-data:www-data /var/www/html/nextcloud
chmod -R 755 /var/www/html/nextcloud
rm latest.zip
echo ""


# --- Apache Virtual Host für Nextcloud erstellen ---
echo ""
echo "${GREEN}=== SCHRITT 8: APACHE VIRTUAL HOST ERSTELLEN & KONFIGURIEREN ===${NC}"
echo ""
echo "Hier wird eine neue Apache-Konfiguration erstellt und aktiviert."
echo ""
read -p "Drücke Enter, um fortzufahren..."
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
   ServerName ${NEXTCLOUD_DOMAIN}
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
echo "${GREEN}=== SCHRITT 9: NEXTCLOUD ÜBER DIE KOMMANDOZEILE INSTALLIEREN & KONFIGURIEREN ===${NC}"
echo ""
echo "Dieser letzte Schritt verbindet die Anwendung mit der Datenbank und schließt die Installation ab."
echo ""
read -p "Drücke Enter, um fortzufahren..."
sudo -u www-data php /var/www/html/nextcloud/occ maintenance:install \
--database "mysql" \
--database-name "$DB_NAME" \
--database-user "$DB_USER" \
--database-pass "$DB_PASSWORD" \
--data-dir "/var/www/html/nextcloud/data" \
--admin-user "$NC_ADMIN_USER" \
--admin-pass "$NC_ADMIN_PASSWORD"
echo ""


# --- Zusätzliche Konfigurationen und Reparaturen ---
echo ""
echo "${GREEN}=== SCHRITT 10: ZUSÄTZLICHE KONFIGURATIONEN & REPARATUREN DURCHFÜHREN ===${NC}"
echo ""
echo "Es werden letzte Optimierungen und Reparaturen vorgenommen, um die verbleibenden Warnungen zu beheben."
echo ""
read -p "Drücke Enter, um fortzufahren..."
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set trusted_domains 1 --value="$NEXTCLOUD_DOMAIN"
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set default_phone_region --value="$DEFAULT_PHONE_REGION"
sudo -u www-data php /var/www/html/nextcloud/occ config:system:set maintenance_window_start --value="1" # Startet Wartung um 1 Uhr morgens
sudo -u www-data php /var/www/html/nextcloud/occ maintenance:repair --include-expensive
echo ""

echo ""
echo "--- Installation abgeschlossen! ---"
echo "Du kannst jetzt die Weboberfläche unter ${GREEN}http://${NEXTCLOUD_DOMAIN}${NC} aufrufen."
echo "Admin-Benutzer: ${NC_ADMIN_USER}"
echo "Admin-Passwort: ${NC_ADMIN_PASSWORD}"
echo ""
