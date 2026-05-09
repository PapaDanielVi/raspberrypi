#!/usr/bin/env bash

set -e

WLAN_IFACE="wlan0"
ETH_IFACE="eth0"
VPN_IFACE="tun0"
VPN_TABLE="vpn"
HOTSPOT_NET="192.168.4.0/24"
HOTSPOT_IP="192.168.4.1"

echo "[+] Setting up VPN Hotspot Gateway..."

# =========================
# ENABLE IP FORWARDING
# =========================
echo "[+] Enabling IP forwarding..."
sudo tee /etc/sysctl.d/99-vpn-hotspot.conf > /dev/null <<EOF
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

# =========================
# CREATE ROUTING TABLE
# =========================
echo "[+] Setting up policy routing table..."
if ! grep -q "$VPN_TABLE" /etc/iproute2/rt_tables; then
    echo "200 $VPN_TABLE" | sudo tee -a /etc/iproute2/rt_tables
fi

# =========================
# HOTSPOT → VPN ROUTE RULE
# =========================
echo "[+] Adding policy routing rule..."
sudo ip rule add from ${HOTSPOT_NET} table ${VPN_TABLE} 2>/dev/null || true

# NOTE: VPN route will only exist AFTER OpenVPN is started
echo "[i] VPN route will be added automatically after tun0 is up"

# =========================
# DNSMASQ HARDENING (clients only)
# =========================
echo "[+] Ensuring dnsmasq is locked to wlan0..."
sudo sed -i '/interface=/d' /etc/dnsmasq.conf
sudo sed -i '/bind-interfaces/d' /etc/dnsmasq.conf

cat <<EOF | sudo tee -a /etc/dnsmasq.conf > /dev/null

interface=${WLAN_IFACE}
bind-interfaces
listen-address=${HOTSPOT_IP}

dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
dhcp-option=6,${HOTSPOT_IP}
dhcp-option=3,${HOTSPOT_IP}

domain-needed
bogus-priv
EOF

# =========================
# NAT RULES (VPN + fallback safe)
# =========================
echo "[+] Setting NAT rules..."

# VPN NAT (preferred path)
sudo iptables -t nat -C POSTROUTING -s ${HOTSPOT_NET} -o ${VPN_IFACE} -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -s ${HOTSPOT_NET} -o ${VPN_IFACE} -j MASQUERADE

# Fallback NAT (only if VPN is down - optional safety)
sudo iptables -t nat -C POSTROUTING -s ${HOTSPOT_NET} -o ${ETH_IFACE} -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -s ${HOTSPOT_NET} -o ${ETH_IFACE} -j MASQUERADE

# FORWARD rules
sudo iptables -C FORWARD -i ${WLAN_IFACE} -o ${VPN_IFACE} -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${WLAN_IFACE} -o ${VPN_IFACE} -j ACCEPT

sudo iptables -C FORWARD -i ${VPN_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i ${VPN_IFACE} -o ${WLAN_IFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

# Block leaks to eth0 (important)
sudo iptables -C FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j REJECT 2>/dev/null || \
sudo iptables -A FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j REJECT

# =========================
# KILL SWITCH (optional safety)
# =========================
echo "[+] Adding VPN kill-switch (prevents leaks if VPN is down)..."
sudo iptables -C FORWARD -i ${WLAN_IFACE} -o ${ETH_IFACE} -j REJECT 2>/dev/null || true

# =========================
# APPLY CHANGES
# =========================
echo "[+] Restarting services..."
sudo systemctl restart dnsmasq

echo ""
echo "[✔] VPN Hotspot configured"
echo "[i] NEXT STEP:"
echo "   1. Start OpenVPN manually"
echo "   2. Ensure tun0 appears: ip a"
echo "   3. Test: curl ifconfig.me from client"
echo ""
echo "[✔] Routing rule active for: ${HOTSPOT_NET} → ${VPN_IFACE}"
