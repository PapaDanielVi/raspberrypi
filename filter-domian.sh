#!/usr/bin/env bash

set -e

BLOCK_FILE="/etc/dnsmasq.d/blocked_domains.conf"

echo "[+] DNSMASQ Domain Blocker"

# =========================
# INPUT
# =========================
read -rp "Enter domain to block (e.g. example.com): " DOMAIN

# Normalize input
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [[ -z "$DOMAIN" ]]; then
    echo "[!] No domain entered. Exiting."
    exit 1
fi

# Basic validation
if ! [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
    echo "[!] Invalid domain format."
    exit 1
fi

# =========================
# PREP FILE
# =========================
echo "[+] Preparing blocklist file..."

sudo mkdir -p /etc/dnsmasq.d
sudo touch "$BLOCK_FILE"

# =========================
# CHECK DUPLICATE
# =========================
if grep -q "address=/${DOMAIN}/0.0.0.0" "$BLOCK_FILE"; then
    echo "[i] Domain already blocked."
    exit 0
fi

# =========================
# ADD BLOCK RULE
# =========================
echo "[+] Blocking domain: $DOMAIN"

echo "address=/${DOMAIN}/0.0.0.0" | sudo tee -a "$BLOCK_FILE" > /dev/null

# Also block www variant explicitly (optional but safer)
echo "address=/www.${DOMAIN}/0.0.0.0" | sudo tee -a "$BLOCK_FILE" > /dev/null

# =========================
# VERIFY DNSMASQ INCLUDES DIR
# =========================
if ! grep -q "conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
    echo "[+] Enabling dnsmasq conf-dir..."
    echo "conf-dir=/etc/dnsmasq.d" | sudo tee -a /etc/dnsmasq.conf > /dev/null
fi

# =========================
# RESTART SERVICE
# =========================
echo "[+] Restarting dnsmasq..."
sudo systemctl restart dnsmasq

# =========================
# TEST
# =========================
echo "[+] Testing resolution..."
sleep 1

RESULT=$(dig +short "$DOMAIN" @127.0.0.1 || true)

echo "[i] Result: $RESULT"

if [[ "$RESULT" == "0.0.0.0" ]]; then
    echo "[✔️] Domain successfully blocked!"
else
    echo "[!] Warning: DNS result not 0.0.0.0 (may be cached on client)"
fi

echo ""
echo "[💡] Clients may need to reconnect WiFi or flush DNS cache."
