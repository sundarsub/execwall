#!/bin/bash
# Sentra Easy Installer
# Universal Execution Governance Gateway
#
# This script installs:
#   - sentra binary (main REPL/API server)
#   - python_runner binary (sandbox executor)
#   - Default policy and sandbox profiles
#   - Optional systemd service for API mode

set -e

SENTRA_VERSION="${SENTRA_VERSION:-latest}"
GITHUB_REPO="sundarsub/sentra"
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Sentra - Execution Governance               ║"
    echo "║         Universal Shell with Policy Enforcement          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_banner
echo "Installing Sentra..."
echo ""

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

if [ "$OS" = "darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        ASSET="sentra-macos-aarch64.tar.gz"
    else
        ASSET="sentra-macos-x86_64.tar.gz"
    fi
    PLATFORM_INFO="macOS"
elif [ "$OS" = "linux" ]; then
    if [ "$ARCH" = "aarch64" ]; then
        ASSET="sentra-linux-aarch64.tar.gz"
    else
        ASSET="sentra-linux-x86_64.tar.gz"
    fi
    PLATFORM_INFO="Linux (full sandbox support)"
else
    log_error "Unsupported OS: $OS"
    exit 1
fi

echo "Platform: $PLATFORM_INFO ($ARCH)"
echo "Downloading $ASSET..."
echo ""

# Download and extract binaries
cd /tmp
rm -rf /tmp/sentra-install-tmp
mkdir -p /tmp/sentra-install-tmp
cd /tmp/sentra-install-tmp

if [ "$SENTRA_VERSION" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/$ASSET"
else
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${SENTRA_VERSION}/$ASSET"
fi

curl -sL "$DOWNLOAD_URL" | tar xz

# Install main sentra binary
sudo mv /tmp/sentra-install-tmp/sentra /usr/local/bin/
log_info "Installed sentra to /usr/local/bin/sentra"

# Install python_runner binary (for sandbox execution)
if [ -f /tmp/sentra-install-tmp/python_runner ]; then
    sudo mkdir -p /usr/lib/sentra
    sudo mv /tmp/sentra-install-tmp/python_runner /usr/lib/sentra/
    sudo chmod 755 /usr/lib/sentra/python_runner
    log_info "Installed python_runner to /usr/lib/sentra/python_runner"
else
    log_warn "python_runner not found in release (sandbox features limited)"
fi

rm -rf /tmp/sentra-install-tmp

# Create configuration directories
echo ""
echo "Setting up configuration directories..."
sudo mkdir -p /etc/sentra
sudo mkdir -p /etc/sentra/profiles
sudo mkdir -p /var/log/sentra

# Download default policy
sudo curl -sL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/policy.yaml" \
    -o /etc/sentra/policy.yaml 2>/dev/null || {
    log_warn "Could not download default policy, creating minimal policy"
    sudo tee /etc/sentra/policy.yaml > /dev/null << 'POLICY_EOF'
# Sentra Default Policy
version: "2.0"
mode: enforce
default: deny

rate_limit:
  max_commands: 60
  window_seconds: 60

rules:
  - id: safe_read_commands
    match:
      executable: "^(ls|cat|head|tail|less|pwd|whoami|echo|date)$"
    effect: allow

  - id: block_sudo
    match:
      executable: "^sudo$"
    effect: deny
    reason: "Privilege escalation blocked"
POLICY_EOF
}
log_info "Installed default policy to /etc/sentra/policy.yaml"

# Download sandbox profiles
echo ""
echo "Downloading sandbox profiles..."

# Python sandbox profile v1
sudo curl -sL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/profiles/python_sandbox_v1.yaml" \
    -o /etc/sentra/profiles/python_sandbox_v1.yaml 2>/dev/null || {
    sudo tee /etc/sentra/profiles/python_sandbox_v1.yaml > /dev/null << 'PROFILE_EOF'
# Python Sandbox Profile v1 - Secure by Default
runner: "/usr/lib/sentra/python_runner"
python_bin: "/usr/bin/python3"
deny_spawn_processes: true
default_network: deny

fs_defaults:
  cwd: "/work"
  read_allow:
    - "/work"
  write_allow:
    - "/work/tmp"
    - "/work/out"
  protected_deny:
    - "/"
    - "/etc"
    - "/proc"
    - "/sys"

limits_defaults:
  timeout_sec: 30
  cpu_max_percent: 50
  mem_max_mb: 512
  pids_max: 64
  max_stdout_bytes: 200000
  max_stderr_bytes: 200000

syscall_profile: restricted
PROFILE_EOF
}
log_info "Installed python_sandbox_v1.yaml profile"

# Python sandbox profile v2 (more permissive for data science)
sudo tee /etc/sentra/profiles/python_data_science_v1.yaml > /dev/null << 'DS_PROFILE_EOF'
# Python Data Science Profile - For numpy/pandas workloads
runner: "/usr/lib/sentra/python_runner"
python_bin: "/usr/bin/python3"
deny_spawn_processes: true
default_network: deny

fs_defaults:
  cwd: "/work"
  read_allow:
    - "/work"
    - "/usr/lib/python3"
    - "/usr/local/lib/python3"
  write_allow:
    - "/work/tmp"
    - "/work/out"
    - "/work/data"
  protected_deny:
    - "/etc"
    - "/proc"
    - "/sys"

limits_defaults:
  timeout_sec: 300
  cpu_max_percent: 100
  mem_max_mb: 4096
  pids_max: 128
  max_stdout_bytes: 1000000
  max_stderr_bytes: 500000

syscall_profile: data_science
DS_PROFILE_EOF
log_info "Installed python_data_science_v1.yaml profile"

# Set permissions
sudo chmod 644 /etc/sentra/policy.yaml
sudo chmod 644 /etc/sentra/profiles/*.yaml
sudo chmod 755 /var/log/sentra

# Linux-specific: Create sentra cgroup for resource limits
if [ "$OS" = "linux" ]; then
    echo ""
    echo "Setting up Linux-specific features..."

    # Create cgroup directory if cgroups v2 is available
    if [ -d "/sys/fs/cgroup" ] && [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        sudo mkdir -p /sys/fs/cgroup/sentra 2>/dev/null || true
        if [ -d "/sys/fs/cgroup/sentra" ]; then
            # Enable controllers for sentra cgroup
            echo "+cpu +memory +pids" | sudo tee /sys/fs/cgroup/sentra/cgroup.subtree_control > /dev/null 2>&1 || true
            log_info "Created sentra cgroup for resource limits"
        fi
    else
        log_warn "Cgroups v2 not available, resource limits will be limited"
    fi
fi

# Optional: Install systemd service for API mode
if [ "$INSTALL_SYSTEMD" = "true" ] && [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
    echo ""
    echo "Installing systemd service for API mode..."

    sudo tee /etc/systemd/system/sentra-api.service > /dev/null << 'SYSTEMD_EOF'
[Unit]
Description=Sentra Execution Governance API Server
Documentation=https://github.com/sundarsub/sentra
After=network.target

[Service]
Type=simple
User=sentra
Group=sentra
ExecStart=/usr/local/bin/sentra --api --port 9800 --policy /etc/sentra/policy.yaml --log /var/log/sentra/api_audit.jsonl
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/sentra
ReadOnlyPaths=/etc/sentra

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    # Create sentra system user if it doesn't exist
    if ! id "sentra" &>/dev/null; then
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin sentra 2>/dev/null || true
    fi

    sudo chown -R sentra:sentra /var/log/sentra 2>/dev/null || true
    sudo systemctl daemon-reload
    log_info "Installed sentra-api.service"
    log_info "Enable with: sudo systemctl enable --now sentra-api"
fi

# Verification step
echo ""
echo "Verifying installation..."
VERIFY_PASSED=true

# Check sentra binary
if command -v sentra &> /dev/null; then
    SENTRA_VERSION_OUT=$(sentra --version 2>&1 || echo "unknown")
    log_info "sentra binary: OK ($SENTRA_VERSION_OUT)"
else
    log_error "sentra binary: NOT FOUND"
    VERIFY_PASSED=false
fi

# Check python_runner
if [ -x "/usr/lib/sentra/python_runner" ]; then
    log_info "python_runner: OK"
else
    log_warn "python_runner: NOT FOUND (sandbox features limited)"
fi

# Check policy file
if [ -f "/etc/sentra/policy.yaml" ]; then
    log_info "policy.yaml: OK"
else
    log_error "policy.yaml: NOT FOUND"
    VERIFY_PASSED=false
fi

# Check profiles directory
PROFILE_COUNT=$(ls -1 /etc/sentra/profiles/*.yaml 2>/dev/null | wc -l)
if [ "$PROFILE_COUNT" -gt 0 ]; then
    log_info "sandbox profiles: OK ($PROFILE_COUNT profiles)"
else
    log_warn "sandbox profiles: NONE FOUND"
fi

# Check Python (needed for sandbox execution)
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    log_info "python3: OK ($PYTHON_VERSION)"
else
    log_warn "python3: NOT FOUND (required for Python sandbox)"
fi

echo ""
if [ "$VERIFY_PASSED" = "true" ]; then
    echo -e "${GREEN}Installation complete!${NC}"
else
    echo -e "${YELLOW}Installation completed with warnings.${NC}"
fi

echo ""
echo -e "${CYAN}Quick Start:${NC}"
echo ""
echo "  Interactive REPL mode:"
echo "    sentra"
echo ""
echo "  With custom policy:"
echo "    sentra --policy /path/to/policy.yaml"
echo ""
if [ "$OS" = "linux" ]; then
echo "  API mode (for OpenClaw VM integration):"
echo "    sentra --api --port 9800"
echo ""
fi
echo "  View help:"
echo "    sentra --help"
echo ""
echo -e "${CYAN}Configuration Files:${NC}"
echo "  Policy:   /etc/sentra/policy.yaml"
echo "  Profiles: /etc/sentra/profiles/"
echo "  Logs:     /var/log/sentra/"
echo ""
echo "Run 'sentra' to start!"
