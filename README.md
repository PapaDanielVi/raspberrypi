# Raspberry PI5 Bash Scripts

A collection of bash scripts to configure your Raspberry Pi 5 with various services including workflow automation, AI models, WiFi hotspot, VPN routing, and domain filtering.

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `configure_n8n.sh` | n8n + Ollama with Phi-3 AI model |
| `configure_hotspot.sh` | 5GHz WiFi hotspot with VPN routing |
| `configure_vpn_routing.sh` | VPN routing gateway for hotspot clients |
| `configure_openclaw.sh` | OpenClaw AI agent with Ollama |
| `filter_domains.sh` | Block domains via dnsmasq |

---

## configure_n8n.sh

Installs and configures **n8n** (workflow automation platform) with **Ollama** for local AI capabilities.

### Features
- Installs Docker if not present
- Installs and configures Ollama as a systemd service
- Pulls Microsoft Phi-3 AI model
- Runs n8n container with persistent storage
- Optional proxy support for restricted networks

### Usage
```bash
./configure_n8n.sh
```

### Output
- **n8n URL**: `http://<PI_IP>:5678`
- **Ollama Base URL**: `http://host.docker.internal:11434`

---

## configure_hotspot.sh

Creates a **5GHz WiFi hotspot** with VPN-based routing and a kill switch to prevent traffic leaks.

### Features
- 5GHz access point (Channel 36, SSID: `RouterAX`)
- DHCP server with dnsmasq (192.168.4.10-100)
- Policy-based routing via `vpntable` (tun0)
- Kill switch to block non-VPN traffic
- DNS redirection enforcement
- IPTables NAT with persistent rules

### Usage
```bash
./configure_hotspot.sh
```

### Configuration
Edit these variables at the top of the script:
```bash
SSID="RouterAX"           # WiFi network name
PASSPHRASE="test_pass"    # WiFi password
COUNTRY="IR"              # Regulatory domain
CHANNEL="36"              # WiFi channel
```

### Output
- **WiFi Network**: 5GHz, WPA2-PSK
- **Hotspot IP**: 192.168.4.1

---

## configure_vpn_routing.sh

Configures the Raspberry Pi as a **VPN gateway** for connected hotspot clients. Traffic from the hotspot network (192.168.4.0/24) is routed exclusively through the VPN (tun0).

### Features
- IP forwarding configuration
- Custom routing table (`vpn`) for policy routing
- DNSSEC-compatible dnsmasq configuration
- NAT rules for VPN (tun0) with fallback to ethernet (eth0)
- Kill switch to prevent leaks to eth0
- FORWARD chain rules for VPN traffic

### Usage
```bash
./configure_vpn_routing.sh
```

### Requirements
- OpenVPN must be running with `tun0` interface active
- Run after `configure_hotspot.sh`

### Output
- Routes hotspot traffic through `tun0` (VPN)
- Falls back to `eth0` only if VPN is down (optional safety)

---

## configure_openclaw.sh

Installs **OpenClaw** (AI agent platform) with **Ollama** Phi-3 model integration.

### Features
- Installs Docker if not present
- Creates `.openclaw` directory with proper permissions
- Pulls OpenClaw Docker image
- Configures Ollama as model provider
- Runs OpenClaw container on host network

### Usage
```bash
./configure_openclaw.sh
```

### Configuration
Edit these variables at the top of the script:
```bash
PROXY_URL="http://192.168.1.94:8118"
OPENCLAW_GATEWAY_TOKEN="test_token_secret"
```

### Output
- **OpenClaw URL**: `http://<PI_IP>:18789`
- **Gateway Token**: `test_token_secret` (change in production!)

---

## filter_domains.sh

Interactive script to **block domains** using dnsmasq.

### Features
- Interactive domain input with validation
- Blocks both root domain and `www.` variant
- Automatic dnsmasq restart
- Local DNS resolution test
- Duplicate detection

### Usage
```bash
./filter_domains.sh
```

### Example Session
```
Enter domain to block (e.g. example.com): ads.example.com
[+] Blocking domain: ads.example.com
[+] Restarting dnsmasq...
[+] Testing resolution locally...
[✔] Domain 'ads.example.com' successfully blocked!
```

### Blocked Domains Location
Blocked domains are stored in: `/etc/dnsmasq.d/blocked_domains.conf`

---

## Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │         Raspberry Pi 5              │
                    │                                     │
┌──────────────┐    │  ┌─────────────┐  ┌─────────────┐  │
│   Ethernet   │────│──│  Hotspot    │──│   n8n       │  │
│  (Internet) │    │  │  (wlan0)    │  │   Ollama    │  │
└──────────────┘    │  └──────┬──────┘  │   OpenClaw  │  │
                   │         │         └─────────────┘  │
                   │         │                           │
                   │    Policy Route                     
                   │    (vpntable)                       
                   │         │                           
                   │         ▼                           
                   │  ┌─────────────┐                    
                   │  │  VPN (tun0) │                    
                   │  └─────────────┘                    
                   └─────────────────────────────────────┘
                           ▲
                           │
                    ┌──────┴──────┐
                    │   Clients   │
                    │  (WiFi)     │
                    └─────────────┘
```

## Requirements

- Raspberry Pi 5
- Raspberry Pi OS (64-bit)
- WiFi adapter supporting 5GHz (for hotspot)
- Root/sudo access

## Quick Start

1. Clone or copy scripts to your Pi
2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```
3. Run the desired configuration script
4. Follow the on-screen instructions

## Notes

- Some scripts require a restart or manual service start after completion
- VPN scripts require an active VPN connection (`tun0`) for full functionality
- Change default passwords and tokens before deploying
- Firewall rules persist via `iptables-persistent`