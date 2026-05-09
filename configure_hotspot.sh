#!/usr/bin/env bash

set -e

SSID="RouterAX"
PASSPHRASE="test_pass"
WLAN_IFACE="wlan0"
ETH_IFACE="eth0"
TUN_IFACE="tun0" # Added VPN interface variable
COUNTRY="IR"
CHANNEL="36"

# =========================
# PRECHECKS
# =========================
echo "[+] Checking WiFi capabilities..."
if ! iw list | grep -q "5180 MHz"; then
    echo "[!] WARNING: 5GHz may not be supported on this device!"
fi

echo "[+] Installing required packages..."
sudo apt update
sudo apt install -y hostapd dnsmasq iptables iptables-persistent iproute2

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

interface ${ETH_IFACE}
static domain_name_servers=192.168.1.1
noipv6rs
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
listen-address=127.0.0.1,192.168.4.1
bind-interfaces

# DHCP range
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h

# Force clients to use Pi as DNS
dhcp-option=6,192.168.4.1
dhcp-option=3,192.168.4.1

domain-needed
bogus-priv
no-resolv

# Standard Upstream DNS (Routing handled by IP routes below)
server=8.8.8.8
server=1.1.1.1

# Logging (optional, useful for debugging)
log-queries
log-dhcp

# Include directory for your blocker script
conf-dir=/etc/dnsmasq.d/,*.conf
EOF

# =========================
# HOSTAPD CONFIG (5 GHz)
# =========================
echo "[+] Configuring hostapd (5 GHz)..."

sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=${WLAN_IFACE}
driver=nl80211
ssid=${SSID}
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

sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

echo "[+] Enabling IP forwarding..."
sudo tee /etc/sysctl.d/routed-ap.conf > /dev/null <<EOF
net.ipv4.ip_forward=1
EOF
sudo sysctl -p /etc/sysctl.d/routed-ap.conf

# =========================
# FIREWALL & NAT (iptables-nft)
# =========================
echo "[+] Configuring NAT for ${TUN_IFACE}..."

# Route traffic out through the VPN instead of eth0
sudo iptables -t nat -C POSTROUTING -o ${TUN_IFACE} -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o ${TUN_IFACE} -j MASQUERADE

sudo iptables -C FORWARD -i ${TUN_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${TUN_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -C FORWARD -i ${WLAN_IFACE} -o ${TUN_IFACE} -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${WLAN_IFACE} -o ${TUN_IFACE} -j ACCEPT

# Bypass custom domain server via Pi's local dnsmasq
echo "[+] Enforcing DNS redirection..."
sudo iptables -t nat -C PREROUTING -i ${WLAN_IFACE} -p udp --dport 53 -j REDIRECT --to-port 53 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -i ${WLAN_IFACE} -p udp --dport 53 -j REDIRECT --to-port 53
sudo iptables -t nat -C PREROUTING -i ${WLAN_IFACE} -p tcp --dport 53 -j REDIRECT --to-port 53 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -i ${WLAN_IFACE} -p tcp --dport 53 -j REDIRECT --to-port 53

sudo netfilter-persistent save

# =========================
# POLICY-BASED ROUTING
# =========================
echo "[+] Setting up routing for route-nopull..."

# Create a custom routing table for VPN traffic if it doesn't exist
if ! grep -q "200 vpntable" /etc/iproute2/rt_tables; then
    echo "200 vpntable" | sudo tee -a /etc/iproute2/rt_tables
fi

# Clean up any old routing rules
sudo ip rule del from 192.168.4.0/24 table vpntable 2>/dev/null || true
sudo ip route flush table vpntable 2>/dev/null || true

# Any traffic originating from the hotspot must use the 'vpntable' routing table
sudo ip rule add from 192.168.4.0/24 table vpntable

# Add the default route to the VPN table (only works if tun0 is active)
if ip link show ${TUN_IFACE} > /dev/null 2>&1; then
    sudo ip route add default dev ${TUN_IFACE} table vpntable
    echo "[✔️] VPN routing configured successfully."
else
    echo "[!] WARNING: ${TUN_IFACE} is not currently running!"
    echo "    Start your OpenVPN connection, then run this command manually:"
    echo "    sudo ip route add default dev ${TUN_IFACE} table vpntable"
fi

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
echo "VPN Interface: ${TUN_IFACE}"
echo ""
