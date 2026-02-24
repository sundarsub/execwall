# Sentra Oracle Cloud Setup

## Server Details

| Setting | Value |
|---------|-------|
| **Public IP** | 150.136.64.135 |
| **Instance** | instance-20260223-1746 |
| **User** | opc |
| **Platform** | Oracle Linux (ARM64 Ampere A1) |
| **SSH Key** | `/Users/sundarsubramaniam/Downloads/ssh-key-2026-02-23 (1).key` |

## SSH Connection

```bash
ssh -i "/Users/sundarsubramaniam/Downloads/ssh-key-2026-02-23 (1).key" opc@150.136.64.135
```

## Installed Components

| Component | Path | Status |
|-----------|------|--------|
| sentra | /usr/local/bin/sentra | Installed |
| openclaw_launcher | /usr/local/bin/openclaw_launcher | Installed |
| python_runner | /usr/lib/sentra/python_runner | Installed |
| sentra-shell | /usr/local/bin/sentra-shell | Installed |
| policy.yaml | /etc/sentra/policy.yaml | Configured |
| himalaya | /home/opc/.local/bin/himalaya | Installed |
| openclaw | /usr/bin/openclaw | Installed |

## Email Configuration

| Setting | Value |
|---------|-------|
| Email | sentra@lma.llc |
| Provider | Gmail (Google Workspace) |
| IMAP | imap.gmail.com:993 (TLS) |
| SMTP | smtp.gmail.com:465 (TLS) |
| Auth | App Password |
| Config | ~/.config/himalaya/config.toml |
| OpenClaw Skill | himalaya (ready) |

## OpenClaw Configuration

- **Config file**: `~/.openclaw/openclaw.json`
- **Model**: openrouter/auto
- **Channels**: WhatsApp enabled
- **Gateway token**: 9a054e581680c04cad5aaf7f101713ab39a05f63c93cfc1a

### Path Configuration
```json
"tools": {
  "exec": {
    "pathPrepend": [
      "/home/opc/.local/bin",
      "/home/opc/sentra/bin"
    ]
  }
}
```

## Environment Variables

Located in `~/.openclaw/.env`:
- OPENROUTER_API_KEY

Located in `/etc/sentra/env`:
- OPENROUTER_API_KEY

## Seccomp Profile

Default profile: `gateway` (allows subprocess spawning, blocks dangerous syscalls)

## Services

```bash
# Start OpenClaw with execution firewall
openclaw_launcher \
  --openclaw-bin /usr/bin/openclaw \
  --seccomp-profile gateway \
  --sentra-repl \
  -- gateway

# Or via systemd
sudo systemctl enable --now openclaw-firewall
sudo systemctl status openclaw-firewall
journalctl -u openclaw-firewall -f
```

## Quick Commands

```bash
# Check email inbox
~/.local/bin/himalaya envelope list

# Send test email
echo "To: test@example.com
Subject: Test

Message body" | ~/.local/bin/himalaya message send

# List OpenClaw skills
openclaw skills list

# Check Sentra policy
sentra --policy /etc/sentra/policy.yaml
```

## Networking

- SSH: Port 22
- OpenClaw Gateway: Port 18789
- VCN Security List: Ingress rules for 22, 18789

## Notes

- VM IP changed from 129.153.116.73 to 150.136.64.135 (Feb 24, 2026)
- Gmail App Password required for himalaya (regular password won't work)
- WhatsApp connected and operational
