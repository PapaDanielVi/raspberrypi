#!/usr/bin/env bash

set -e

SSID="RouterAX"
PASSPHRASE="MK20122013mk"
WLAN_IFACE="wlan0"
ETH_IFACE="eth0"
COUNTRY="IR"
CHANNEL="36"

# =========================
# PRECHECKS
# =========================
echo "[+] Checking WiFi capabilities..."
if ! iw list | grep -q "5180 MHz"; then
    echo "[!] WARNING: 5GHz may not be supported on this device!"
fi

# echo "[+] Setting regulatory domain to ${COUNTRY}..."
# sudo raspi-config nonint do_wifi_country ${COUNTRY} || true

echo "[+] Installing required packages..."
sudo apt update
sudo apt install -y hostapd dnsmasq iptables iptables-persistent

# =========================
# STOP SERVICES
# =========================
echo "[+] Stopping services..."
sudo systemctl stop hostapd || true
sudo systemctl stop dnsmasq || true

# =========================
# NETWORK CONFIG (dhcpcd)
# =========================
echo "[+] Configuring static IP for ${WLAN_IFACE}..."

if ! grep -q "interface ${WLAN_IFACE}" /etc/dhcpcd.conf; then
sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

interface ${WLAN_IFACE}
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF
fi

sudo systemctl restart dhcpcd || true

# =========================
# DNSMASQ CONFIG
# =========================
echo "[+] Configuring dnsmasq..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null || true

sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=${WLAN_IFACE}
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
domain-needed
bogus-priv
EOF

# =========================
# HOSTAPD CONFIG (5 GHz)
# =========================
echo "[+] Configuring hostapd (5 GHz)..."

sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=${WLAN_IFACE}
driver=nl80211
ssid=${SSID}

# 5GHz setup
hw_mode=a
channel=${CHANNEL}
ieee80211n=1
ieee80211ac=1

country_code=${COUNTRY}
ieee80211d=1
ieee80211h=1

wmm_enabled=1

auth_algs=1
ignore_broadcast_ssid=0

wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Link config
sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd


echo "[+] Enabling IP forwarding..."
sudo tee /etc/sysctl.d/routed-ap.conf > /dev/null <<EOF
net.ipv4.ip_forward=1
EOF

sudo sysctl -p /etc/sysctl.d/routed-ap.conf

# =========================
# FIREWALL (iptables-nft)
# =========================
echo "[+] Configuring NAT..."

sudo iptables -t nat -C POSTROUTING -o ${ETH_IFACE} -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o ${ETH_IFACE} -j MASQUERADE

sudo iptables -C FORWARD -i ${ETH_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${ETH_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -C FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j ACCEPT

sudo netfilter-persistent save

# =========================
# ENABLE SERVICES
# =========================
echo "[+] Enabling services..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

echo "[+] Starting services..."
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

# =========================
# STATUS
# =========================
echo ""
echo "[✔️] 5GHz Hotspot is ready!"
echo "SSID: ${SSID}"
echo "Password: ${PASSPHRASE}"
echo "Channel: ${CHANNEL}"
echo ""

echo "[i] If hotspot is not visible:"
echo " - Ensure country code is set"
echo " - Try another channel (36, 40, 44, 48)"
echo " - Check logs: journalctl -u hostapd -f"
