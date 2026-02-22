#!/bin/bash
# OpenClaw Isolated Launch Script
#
# This script provides full network isolation by:
# 1. Creating a network namespace for OpenClaw
# 2. Setting up a veth pair so OpenClaw can ONLY reach Sentra
# 3. Running openclaw_launcher inside the namespace
#
# Usage: sudo ./launch_openclaw_isolated.sh [openclaw_args...]

set -e

# Configuration
SENTRA_PORT="${SENTRA_PORT:-9999}"
NAMESPACE="openclaw_ns"
VETH_HOST="veth_host"
VETH_CONTAINER="veth_oc"
HOST_IP="10.200.1.1"
CONTAINER_IP="10.200.1.2"
SENTRA_BIN="${SENTRA_BIN:-/usr/local/bin/sentra}"
OPENCLAW_BIN="${OPENCLAW_BIN:-/usr/local/bin/openclaw}"
LAUNCHER_BIN="${LAUNCHER_BIN:-/usr/local/bin/openclaw_launcher}"
PYTHON_RUNNER="${PYTHON_RUNNER:-/usr/lib/sentra/python_runner}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║    OpenClaw Isolated Launch - Full Network Isolation     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

# Cleanup function
cleanup() {
    echo ""
    echo "→ Cleaning up network namespace..."
    ip netns del "$NAMESPACE" 2>/dev/null || true
    ip link del "$VETH_HOST" 2>/dev/null || true
    echo "✓ Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Step 1: Create network namespace
echo "→ Creating network namespace: $NAMESPACE"
ip netns add "$NAMESPACE" 2>/dev/null || true

# Step 2: Create veth pair
echo "→ Creating veth pair..."
ip link add "$VETH_HOST" type veth peer name "$VETH_CONTAINER"
ip link set "$VETH_CONTAINER" netns "$NAMESPACE"

# Step 3: Configure host side
echo "→ Configuring host network..."
ip addr add "$HOST_IP/24" dev "$VETH_HOST"
ip link set "$VETH_HOST" up

# Step 4: Configure namespace side
echo "→ Configuring namespace network..."
ip netns exec "$NAMESPACE" ip addr add "$CONTAINER_IP/24" dev "$VETH_CONTAINER"
ip netns exec "$NAMESPACE" ip link set "$VETH_CONTAINER" up
ip netns exec "$NAMESPACE" ip link set lo up

# Step 5: Set up NAT for Sentra port forwarding
# OpenClaw at 10.200.1.2 connects to 10.200.1.1:$SENTRA_PORT
# which is forwarded to host's Sentra on 127.0.0.1:$SENTRA_PORT
echo "→ Setting up port forwarding to Sentra..."

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Forward traffic from veth to localhost
iptables -t nat -A PREROUTING -i "$VETH_HOST" -p tcp --dport "$SENTRA_PORT" -j DNAT --to-destination "127.0.0.1:$SENTRA_PORT"
iptables -A FORWARD -i "$VETH_HOST" -o lo -p tcp --dport "$SENTRA_PORT" -j ACCEPT
iptables -A FORWARD -o "$VETH_HOST" -i lo -m state --state ESTABLISHED,RELATED -j ACCEPT

# Step 6: Start Sentra on host (if not running)
if ! nc -z 127.0.0.1 "$SENTRA_PORT" 2>/dev/null; then
    echo "→ Starting Sentra API server on port $SENTRA_PORT..."
    "$SENTRA_BIN" --api --port "$SENTRA_PORT" --python-runner "$PYTHON_RUNNER" &
    SENTRA_PID=$!
    sleep 1
    echo "✓ Sentra started (PID: $SENTRA_PID)"
else
    echo "✓ Sentra already running on port $SENTRA_PORT"
fi

# Step 7: Run openclaw_launcher in the namespace
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Network Isolated Environment Ready"
echo "  OpenClaw can ONLY reach: $HOST_IP:$SENTRA_PORT (Sentra)"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "→ Launching OpenClaw in isolated namespace..."

# Run in namespace with seccomp
ip netns exec "$NAMESPACE" "$LAUNCHER_BIN" \
    --openclaw-bin "$OPENCLAW_BIN" \
    --sentra-bin "$SENTRA_BIN" \
    --port "$SENTRA_PORT" \
    --skip-sentra \
    --verbose \
    "$@"

# Cleanup happens via trap
