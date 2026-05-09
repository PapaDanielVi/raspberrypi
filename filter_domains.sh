#!/usr/bin/env bash

set -e

BLOCK_DIR="/etc/dnsmasq.d"
BLOCK_FILE="${BLOCK_DIR}/blocked_domains.conf"

echo "[+] DNSMASQ Domain Blocker"

# =========================
# INPUT & VALIDATION
# =========================
read -rp "Enter domain to block (e.g. example.com): " DOMAIN

# Normalize input (lowercase, remove spaces)
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [[ -z "$DOMAIN" ]]; then
    echo "[!] No domain entered. Exiting."
    exit 1
fi

# Basic validation for domain format
if ! [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
    echo "[!] Invalid domain format."
    exit 1
fi

# =========================
# PREP ENVIRONMENT
# =========================
echo "[+] Preparing blocklist file..."
sudo mkdir -p "$BLOCK_DIR"
sudo touch "$BLOCK_FILE"

# =========================
# CHECK DUPLICATE
# =========================
if grep -q "address=/${DOMAIN}/" "$BLOCK_FILE"; then
    echo "[i] Domain '${DOMAIN}' is already blocked."
    exit 0
fi

# =========================
# ADD BLOCK RULE
# =========================
echo "[+] Blocking domain: $DOMAIN"

# Block the root domain and the www variant
{
    echo "address=/${DOMAIN}/0.0.0.0"
    echo "address=/www.${DOMAIN}/0.0.0.0"
} | sudo tee -a "$BLOCK_FILE" > /dev/null

# =========================
# RESTART & TEST
# =========================
echo "[+] Restarting dnsmasq..."
sudo systemctl restart dnsmasq
sleep 1 # Give dnsmasq a moment to bind

echo "[+] Testing resolution locally..."

# Ensure dnsutils is installed for the 'dig' command
if ! command -v dig &> /dev/null; then
    sudo apt install -y dnsutils > /dev/null
fi

# Query locally. This will now work because of listen-address=127.0.0.1
RESULT=$(dig +short "$DOMAIN" @127.0.0.1 || true)

if [[ "$RESULT" == "0.0.0.0" ]]; then
    echo "[✔️] Domain '$DOMAIN' successfully blocked!"
else
    echo "[!] Warning: DNS result was '$RESULT' instead of 0.0.0.0."
    echo "    Check if dnsmasq is running properly: sudo systemctl status dnsmasq"
fi

echo ""
echo "[💡] Note: Connected hotspot clients may need to reconnect WiFi to flush their local DNS cache."
