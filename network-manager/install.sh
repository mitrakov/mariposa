#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Rocky Linux 9 Wi-Fi packages"
echo "$SCRIPT_DIR/iw-6.9-1.el9.x86_64.rpm"
rpm --install "$SCRIPT_DIR/iw-6.9-1.el9.x86_64.rpm"
rpm --install "$SCRIPT_DIR/wpa_supplicant-2.11-2.el9.x86_64.rpm"
rpm --install "$SCRIPT_DIR/wireless-regdb-2024.01.23-1.el9.noarch.rpm"
rpm --install "$SCRIPT_DIR/NetworkManager-wifi-1.52.0-3.el9_6.x86_64.rpm"

sudo systemctl restart NetworkManager
echo "Installation done, checking ping..."
sleep 3
ping 8.8.8.8
