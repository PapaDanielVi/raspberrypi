#!/bin/bash

# Configuration
USE_PROXY=false
PROXY_URL="http://192.168.1.94:8118"

# Exit immediately if any command fails
set -e

echo "======================================================="
echo " Starting n8n + Ollama Installation (Full Proxy Support)"
echo "======================================================="

# 1. Dynamically find the Raspberry Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')
echo "[Info] Your Raspberry Pi IP address: $PI_IP"

# 2. Configure Proxy for Docker Daemon (Pulling n8n image)
if [ "$USE_PROXY" = true ]; then
    echo "[Info] Setting up Docker Proxy configuration..."
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF > /dev/null
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,host.docker.internal"
EOF
    # Export for current shell session
    export http_proxy=$PROXY_URL
    export https_proxy=$PROXY_URL
fi

# 3. Install Docker & Curl
echo "[Info] Ensuring Docker and Curl are installed..."
sudo apt-get update -y
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

# Reload Docker to pick up proxy settings
if [ "$USE_PROXY" = true ]; then
    sudo systemctl daemon-reload
    sudo systemctl restart docker
fi

# 4. Install Ollama
echo "[Info] Installing Ollama..."
if ! command -v ollama &> /dev/null; then
    # We use env to pass proxy to the installer script itself
    curl -fsSL https://ollama.com/install.sh | sh
fi

# 5. Configure Ollama Service and Proxy
echo "[Info] Configuring Ollama systemd service..."
sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service <<EOF > /dev/null
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=$USER
Group=$USER
Restart=always
RestartSec=3
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=0"
Environment="OLLAMA_NUM_THREAD=2"
Environment="OLLAMA_DEBUG=1"
Environment="OLLAMA_LOAD_TIMEOUT=3600"
Environment="OLLAMA_DEBUG_LOG_REQUESTS=true"
Environment="OLLAMA_MAX_QUEUE=0"
Environment="OLLAMA_HOST=0.0.0.0"
EOF

if [ "$USE_PROXY" = true ]; then
    echo "[Info] Injecting proxy configuration for Ollama..."
    sudo tee /etc/systemd/system/ollama.service.d/proxy.conf <<EOF > /dev/null
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,host.docker.internal"
EOF
fi

echo "[Info] Restarting Ollama service..."
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

# Give Ollama a moment to initialize
sleep 5

# 6. Pull the Microsoft Phi model
echo "[Info] Pulling Microsoft Phi-3 model..."
ollama pull phi3

# 7. Run n8n
echo "[Info] Setting up n8n..."
sudo docker volume create n8n_data > /dev/null 2>&1 || true
sudo docker stop n8n > /dev/null 2>&1 || true
sudo docker rm n8n > /dev/null 2>&1 || true

sudo docker run -d \
  --name n8n \
  --restart always \
  -p 5678:5678 \
  -e N8N_SECURE_COOKIE=false \
  --add-host=host.docker.internal:host-gateway \
  -v n8n_data:/home/node/.n8n \
  docker.n8n.io/n8nio/n8n

echo "======================================================="
echo " Setup Complete!"
echo " n8n URL: http://$PI_IP:5678"
echo " Ollama Base URL for n8n: http://host.docker.internal:11434"
echo " Proxy Used: $PROXY_URL"
echo "======================================================="
