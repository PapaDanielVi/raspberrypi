#!/bin/bash

# Exit immediately if any command fails
set -e

echo "======================================================="
echo " Starting n8n + Ollama Installation on Raspberry Pi 5  "
echo "======================================================="

# 1. Dynamically find the Raspberry Pi's IP address
# hostname -I gets all IPs, awk '{print $1}' grabs the primary local IP
PI_IP=$(hostname -I | awk '{print $1}')
echo "[Info] Your Raspberry Pi IP address is dynamically detected as: $PI_IP"

# 2. Update system and ensure curl is installed
echo "[Info] Updating system packages..."
sudo apt-get update -y
sudo apt-get install -y curl

# 3. Install Docker (if not already installed)
echo "[Info] Checking for Docker..."
if ! command -v docker &> /dev/null; then
    echo "[Info] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "[Info] Docker installed successfully."
else
    echo "[Info] Docker is already installed. Skipping."
fi

# 4. Install Ollama (if not already installed)
echo "[Info] Checking for Ollama..."
if ! command -v ollama &> /dev/null; then
    echo "[Info] Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    echo "[Info] Ollama installed successfully."
else
    echo "[Info] Ollama is already installed. Skipping."
fi

# 5. Configure Ollama network access for Docker
echo "[Info] Configuring Ollama to accept connections from Docker..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
echo -e '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"' | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null

echo "[Info] Restarting Ollama service to apply changes..."
sudo systemctl daemon-reload
sudo systemctl restart ollama

# Give Ollama a few seconds to fully boot up
sleep 5

# 6. Download the Microsoft Phi-3 model
# Using 'pull' instead of 'run' so the script doesn't pause for interactive chat
echo "[Info] Downloading Microsoft Phi-3 model (this may take a few minutes)..."
ollama pull phi

# 7. Setup n8n in Docker
echo "[Info] Setting up n8n..."
# Create volume if it doesn't exist
sudo docker volume create n8n_data > /dev/null 2>&1 || true

# Check if n8n container already exists
if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^n8n\$"; then
    echo "[Info] n8n container already exists. Starting it..."
    sudo docker start n8n
else
    echo "[Info] Creating and starting n8n container..."
    sudo docker run -d \
      --name n8n \
      --restart always \
      -p 5678:5678 \
      --add-host=host.docker.internal:host-gateway \
      -v n8n_data:/home/node/.n8n \
      docker.n8n.io/n8nio/n8n
fi

echo "======================================================="
echo " Installation Complete! "
echo "======================================================="
echo ""
echo "You can now access n8n from any browser on your network at:"
echo "http://$PI_IP:5678"
echo ""
echo "When connecting n8n to Ollama, use this exact Base URL in your n8n credentials:"
echo "http://host.docker.internal:11434"
echo ""
echo "Note: The script used 'sudo' for docker commands to ensure it runs smoothly right now. If you want to run docker commands manually later without typing sudo, you will need to log out of your Pi and log back in."
