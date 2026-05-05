#!/usr/bin/env bash

set -e

SSID="RouterAX"
PASSPHRASE="MK20122013mk"
WLAN_IFACE="wlan0"
ETH_IFACE="eth0"

echo "[+] Installing required packages..."
sudo apt update
sudo apt install -y hostapd dnsmasq iptables iptables-persistent

echo "[+] Stopping services..."
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq

echo "[+] Configuring static IP for wlan0..."
sudo tee /etc/dhcpcd.conf > /dev/null <<EOF
interface ${WLAN_IFACE}
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

echo "[+] Restarting dhcpcd..."
sudo systemctl restart dhcpcd

echo "[+] Configuring dnsmasq..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak || true

sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=${WLAN_IFACE}
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
EOF

echo "[+] Configuring hostapd..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=${WLAN_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

echo "[+] Linking hostapd config..."
sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

echo "[+] Enabling IP forwarding..."
sudo tee /etc/sysctl.d/routed-ap.conf > /dev/null <<EOF
net.ipv4.ip_forward=1
EOF

sudo sysctl -p /etc/sysctl.d/routed-ap.conf

echo "[+] Setting up NAT (iptables-nft)..."
sudo iptables -t nat -A POSTROUTING -o ${ETH_IFACE} -j MASQUERADE
sudo iptables -A FORWARD -i ${ETH_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j ACCEPT

echo "[+] Saving iptables rules..."
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

echo "[+] Enabling services..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

echo "[+] Starting services..."
sudo systemctl start hostapd
sudo systemctl start dnsmasq

echo "[✔️] Hotspot setup complete!"
echo "SSID: ${SSID}"
echo "Password: ${PASSPHRASE}"
