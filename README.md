# Nextcloud Installationsskript für Ubuntu/Debian

Dieses Skript automatisiert die Installation und Erstkonfiguration von Nextcloud auf einem Ubuntu- oder Debian-System.

### Voraussetzungen

* Ein frisches Ubuntu- oder Debian-System.
* Zugriff auf die Konsole (SSH).
* `sudo`-Rechte.

---

### Interaktive Anleitung 

[**▶️ Zur Interaktiven Nextcloud Installationsanleitung**](https://BastiZ0.github.io/NextCloud_Installer/index.html)

---

### Erste Schritte 

Hier ist, wie du das Skript auf deinem System startest:

1.  **Wechsle ins Verzeichnis `/opt`:**
    ```bash
    cd /opt
    ```

2.  **Lade das Skript herunter:**
    ```bash
    sudo wget [https://github.com/BastiZ0/NextCloud_Installer/raw/main/install_nextcloud.sh](https://github.com/BastiZ0/NextCloud_Installer/raw/main/install_nextcloud.sh)
    ```

3.  **Mache das Skript ausführbar:**
    ```bash
    sudo chmod +x install_nextcloud.sh
    ```

4.  **Führe das Skript aus:**
    ```bash
    sudo ./install_nextcloud.sh
    ```
    Das Skript ist interaktiv und wird dich durch die Konfiguration führen.

---

### Was das Skript macht (Übersicht)

Das Skript installiert und konfiguriert:
* Apache, MariaDB und PHP
* Die neueste Nextcloud-Version
* Wichtige PHP- und Nextcloud-Einstellungen

---

### Nächste Schritte nach der Installation

* **HTTPS einrichten:** Für sichere Verbindungen. Bei lokalem Betrieb/VPN ist dies auch mit selbstsignierten Zertifikaten möglich (Let's Encrypt erfordert eine öffentliche Domain).
* **E-Mail-Server:** In Nextcloud für Benachrichtigungen konfigurieren.
* **Caching:** Für verbesserte Performance (optional).

Weitere Details findest du in der [Interaktiven Anleitung](https://BastiZ0.github.io/NextCloud_Installer/index.html).

---

# Nextcloud Installation Script for Ubuntu/Debian

This script automates the installation and initial configuration of Nextcloud on an Ubuntu or Debian system.

### Prerequisites

* A fresh Ubuntu or Debian system.
* Console access (SSH).
* `sudo` privileges.

---

### Interactive Guide 🚀

For a **detailed, step-by-step, and interactive guide** on how to use this script, please visit our GitHub Pages site:

[**▶️ Go to Interactive Nextcloud Installation Guide**](https://BastiZ0.github.io/NextCloud_Installer/index.html)

---

### Getting Started 🏃‍♂️

Here's how to start the script on your system:

1.  **Navigate to `/opt` directory:**
    ```bash
    cd /opt
    ```

2.  **Download the script:**
    ```bash
    sudo wget [https://github.com/BastiZ0/NextCloud_Installer/raw/main/install_nextcloud.sh](https://github.com/BastiZ0/NextCloud_Installer/raw/main/install_nextcloud.sh)
    ```

3.  **Make the script executable:**
    ```bash
    sudo chmod +x install_nextcloud.sh
    ```

4.  **Run the script:**
    ```bash
    sudo ./install_nextcloud.sh
    ```
    The script is interactive and will guide you through the configuration.

---

### What the Script Does (Overview)

The script installs and configures:
* Apache, MariaDB, and PHP
* The latest Nextcloud version
* Key PHP and Nextcloud settings

---

### Next Steps After Installation

* **Set up HTTPS:** For secure connections. For local/VPN access, this can be done with self-signed certificates (Let's Encrypt requires a public domain).
* **Email Server:** Configure in Nextcloud for notifications.
* **Caching:** For improved performance (optional).

Find more details in the [Interactive Guide](https://BastiZ0.github.io/NextCloud_Installer/index.html).
