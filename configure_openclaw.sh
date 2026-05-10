#!/bin/bash

# Configuration
PROXY_URL="http://192.168.1.94:8118"
OPENCLAW_GATEWAY_TOKEN=test_token_secret

echo "--- Starting OpenClaw Setup for Raspberry Pi 5 ---"

PI_IP=$(hostname -I | awk '{print $1}')

# 1. Update System
sudo apt update && sudo apt upgrade -y

# 2. Install Docker if not present
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

# 4. Create Directory for Game Files
mkdir -p ~/.openclaw
chown -R 1000:1000 ~/.openclaw
chmod -R u+rwX ~/.openclaw
echo "Created directory at ~/.openclaw"

# 5. Pull OpenClaw Docker Image
echo "Pulling OpenClaw image using proxy..."
docker pull ghcr.io/openclaw/openclaw:latest

sudo tee ~/.openclaw/openclaw.json <<EOF > /dev/null
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": [
        "*"
      ],
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://host.docker.internal:11434",
        "apiKey": "dummy",
        "timeoutSeconds": 172800,
        "models": [
          {
            "id": "phi3:latest",
            "name": "Phi-3 (Local)",
            "contextWindow": 8192,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "timeoutSeconds": 172800,
      "model": {
        "primary": "ollama/phi3:latest"
      }
    }
  }
}
EOF

docker run -d \
  --name openclaw \
  --network="host" \
  --user 1000:1000 \
  -e HTTP_PROXY="http://192.168.1.94:8118" \
  -e HTTPS_PROXY="http://192.168.1.94:8118" \
  -e OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN \
  -e OLLAMA_API_KEY=dummy \
  -e NO_PROXY="localhost,127.0.0.1,192.168.1.*" \
  --add-host=host.docker.internal:host-gateway \
  -v ~/.openclaw:/home/node/.openclaw \
  --restart unless-stopped \
  ghcr.io/openclaw/openclaw:latest


echo "======================================================="
echo " Setup Complete!"
echo " openclaw URL: http://$PI_IP:18789"
echo " openclaw auth token: $OPENCLAW_GATEWAY_TOKEN"
echo " Proxy Used: $PROXY_URL"
echo "======================================================="
