# OpenClaw Execution Firewall - Oracle Cloud Deployment Guide

Deploy a secure AI agent execution environment on **Oracle Cloud Free Tier** with WhatsApp integration, Sentra REPL command governance, and Python sandbox isolation.

## Architecture Overview

```
                    Internet
                        │
                        ▼
┌───────────────────────────────────────────────────────────────┐
│              Oracle Cloud VM (Free Tier)                       │
│              ARM64 Ampere A1 - 4 CPU, 24GB RAM                │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  openclaw_launcher                       │  │
│  │  • Applies seccomp profile (gateway)                     │  │
│  │  • Sets SHELL=/usr/local/bin/sentra-shell               │  │
│  │  • Launches OpenClaw gateway                             │  │
│  └────────────────────────┬────────────────────────────────┘  │
│                           │                                    │
│                           ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              OpenClaw Gateway (Node.js)                  │  │
│  │  • WhatsApp Web integration                              │  │
│  │  • LLM API calls (Gemini, OpenRouter)                   │  │
│  │  • Command execution via SHELL                           │  │
│  └────────────────────────┬────────────────────────────────┘  │
│                           │                                    │
│            ┌──────────────┴──────────────┐                    │
│            ▼                             ▼                    │
│  ┌─────────────────────┐    ┌─────────────────────────────┐  │
│  │    sentra-shell     │    │      python_runner          │  │
│  │  (Sentra REPL)      │    │   (Sandboxed Python)        │  │
│  │                     │    │                             │  │
│  │  • Policy enforce   │    │  • Namespace isolation      │  │
│  │  • Rate limiting    │    │  • Seccomp syscall filter   │  │
│  │  • Audit logging    │    │  • Cgroup resource limits   │  │
│  └─────────────────────┘    └─────────────────────────────┘  │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Oracle Cloud account (Free Tier eligible)
- SSH key pair for VM access
- WhatsApp account for bot integration (optional)
- LLM API key (Gemini, OpenRouter, etc.)

## Quick Start

### 1. Create Oracle Cloud VM

1. Log in to Oracle Cloud Console
2. Create a **Compute Instance**:
   - Shape: `VM.Standard.A1.Flex` (ARM64, Free Tier)
   - OCPUs: 4 (Free Tier allows up to 4)
   - Memory: 24 GB (Free Tier allows up to 24)
   - Image: Oracle Linux 9 or Ubuntu 22.04
   - Boot Volume: 100 GB (Free Tier)

3. Configure networking:
   - Create VCN with public subnet
   - Allow ingress on port 22 (SSH)
   - Allow ingress on port 18789 (OpenClaw gateway) if remote access needed

4. Add your SSH public key

### 2. Install Sentra Execution Firewall

SSH into your VM and run:

```bash
# One-line install
curl -sSL https://raw.githubusercontent.com/sundarsub/sentra/main/scripts/install-oracle-cloud.sh | sudo bash
```

Or step by step:

```bash
# Download install script
curl -O https://raw.githubusercontent.com/sundarsub/sentra/main/scripts/install-oracle-cloud.sh
chmod +x install-oracle-cloud.sh

# Review and run
cat install-oracle-cloud.sh
sudo ./install-oracle-cloud.sh
```

### 3. Install OpenClaw

```bash
# Install Node.js 20 LTS
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs

# Install OpenClaw globally
sudo npm install -g openclaw

# Verify
openclaw --version
```

### 4. Configure OpenClaw

```bash
# Initialize OpenClaw config
openclaw init

# Set your LLM API key (example with Gemini)
openclaw config set llm.provider gemini
openclaw config set llm.apiKey "YOUR_GEMINI_API_KEY"

# Or use OpenRouter
openclaw config set llm.provider openrouter
openclaw config set llm.apiKey "YOUR_OPENROUTER_API_KEY"
```

### 5. Configure WhatsApp (Optional)

```bash
# Enable WhatsApp channel
openclaw config set channels.whatsapp.enabled true

# Start OpenClaw to get QR code
openclaw gateway

# Scan QR code with WhatsApp mobile app
# Link as "WhatsApp Web" device
```

### 6. Launch with Execution Firewall

```bash
# Start OpenClaw with Sentra security
openclaw_launcher \
  --openclaw-bin /usr/bin/openclaw \
  --seccomp-profile gateway \
  --sentra-repl \
  -- gateway
```

Or use the systemd service:

```bash
# Enable and start
sudo systemctl enable --now openclaw-firewall

# Check status
sudo systemctl status openclaw-firewall

# View logs
journalctl -u openclaw-firewall -f
```

## What Gets Installed

| Component | Path | Description |
|-----------|------|-------------|
| `sentra` | `/usr/local/bin/sentra` | Execution governance REPL |
| `openclaw_launcher` | `/usr/local/bin/openclaw_launcher` | Seccomp-locked launcher |
| `python_runner` | `/usr/lib/sentra/python_runner` | Sandboxed Python executor |
| `sentra-shell` | `/usr/local/bin/sentra-shell` | SHELL wrapper for REPL |
| `policy.yaml` | `/etc/sentra/policy.yaml` | Execution policy rules |

## Security Profiles

### Gateway Profile (Default)

For OpenClaw gateway process - allows subprocess spawning but blocks dangerous syscalls:

```yaml
seccomp_profiles:
  gateway:
    default: allow
    deny_dangerous:
      - ptrace
      - mount
      - bpf
      - kexec_load
      - reboot
      - init_module
```

### WhatsApp Agent Profile

For sandboxed code execution with WhatsApp network access:

```yaml
seccomp_profiles:
  whatsapp_agent:
    extends: base_restricted
    allow:
      - socket
      - connect
      - sendto
      - recvfrom
    network_policy:
      allow_outbound:
        - "*.whatsapp.net:443"
        - "*.whatsapp.com:443"
```

### Isolated Agent Profile

For maximum isolation - no network, no spawn:

```yaml
seccomp_profiles:
  isolated_agent:
    extends: base_restricted
    deny:
      - socket
      - connect
```

## Command Governance

Sentra REPL enforces policy on all commands:

```
[sentra:enforce]$ ls -la
total 48
drwxr-xr-x  5 opc opc 4096 Feb 24 10:00 .
...

[sentra:enforce]$ rm -rf /
[X] DENIED: rm -rf /
  Rule:   block_rm_rf_root
  Reason: Recursive deletion of root filesystem is blocked

[sentra:enforce]$ sudo su
[X] DENIED: sudo su
  Rule:   block_sudo
  Reason: Privilege escalation via sudo is blocked
```

## Python Sandbox

Python code executes in an isolated sandbox:

```python
# This runs in python_runner with:
# - Namespace isolation (mount, PID, network)
# - Seccomp syscall filtering
# - Cgroup resource limits (512MB RAM, 30s timeout)

import math
print(f"Pi = {math.pi}")  # Works

import subprocess
subprocess.run(["ls"])  # BLOCKED by seccomp
```

## Monitoring

### View Audit Logs

```bash
# Real-time audit log
tail -f /var/log/sentra/audit.jsonl | jq .

# Filter denied commands
grep '"decision":"denied"' /var/log/sentra/audit.jsonl | jq .
```

### Check Process Status

```bash
# OpenClaw processes
ps aux | grep openclaw

# Sentra status
systemctl status openclaw-firewall
```

### Resource Usage

```bash
# Memory and CPU
htop

# Disk usage
df -h
```

## Troubleshooting

### OpenClaw won't start

```bash
# Check if ports are in use
ss -tlnp | grep 18789

# Kill existing processes
pkill -9 openclaw

# Check logs
journalctl -u openclaw-firewall -n 50
```

### WhatsApp not connecting

```bash
# Check WhatsApp logs
tail -f /tmp/openclaw/openclaw-*.log | grep whatsapp

# Re-authenticate
rm -rf ~/.openclaw/whatsapp/
openclaw gateway  # Scan new QR code
```

### Seccomp blocking needed operations

```bash
# List available profiles
openclaw_launcher --list-profiles

# Use development profile (less restrictive)
openclaw_launcher --seccomp-profile development ...

# Or disable seccomp (NOT recommended for production)
openclaw_launcher --no-seccomp ...
```

### Policy denying valid commands

```bash
# Check which rule is blocking
sentra --verbose

# Test command evaluation
echo "your-command" | sentra --policy /etc/sentra/policy.yaml

# Edit policy
sudo vim /etc/sentra/policy.yaml
```

## Updating

```bash
# Update Sentra components
curl -sSL https://raw.githubusercontent.com/sundarsub/sentra/main/scripts/install-oracle-cloud.sh | sudo bash

# Update OpenClaw
sudo npm update -g openclaw
```

## Uninstalling

```bash
# Stop services
sudo systemctl stop openclaw-firewall
sudo systemctl disable openclaw-firewall

# Remove binaries
sudo rm -f /usr/local/bin/sentra
sudo rm -f /usr/local/bin/openclaw_launcher
sudo rm -f /usr/local/bin/sentra-shell
sudo rm -rf /usr/lib/sentra/

# Remove config
sudo rm -rf /etc/sentra/

# Remove OpenClaw
sudo npm uninstall -g openclaw
rm -rf ~/.openclaw/
```

## Security Considerations

1. **API Keys**: Store API keys in environment variables, not in config files
2. **Firewall**: Only expose necessary ports (22 for SSH, optionally 18789)
3. **Updates**: Regularly update Sentra and OpenClaw for security patches
4. **Audit Logs**: Monitor `/var/log/sentra/audit.jsonl` for suspicious activity
5. **WhatsApp**: Use a dedicated phone number for the bot

## Cost (Oracle Cloud Free Tier)

| Resource | Free Tier Allowance | Usage |
|----------|---------------------|-------|
| Compute | 4 ARM OCPUs, 24GB RAM | Full allocation |
| Storage | 200GB boot volume | 100GB used |
| Network | 10TB/month outbound | Minimal for WhatsApp |
| **Total** | **$0/month** | Within free tier |

## Support

- GitHub Issues: https://github.com/sundarsub/sentra/issues
- Email: sentrahelp@gmail.com
