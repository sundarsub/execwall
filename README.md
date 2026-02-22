# Sentra - Universal Execution Governance Gateway

Sentra is a security-focused execution gateway that provides policy-based command filtering, Python sandbox isolation, and comprehensive audit logging. It acts as a governance layer between AI systems (like OpenClaw VM) and system execution, ensuring that only authorized commands run within defined security boundaries.

## Features

### Policy-Based Command Filtering
- **Regex-based rule matching** on executable names and argument patterns
- **First-match-wins** rule evaluation for predictable behavior
- **Identity-scoped rules** for per-user/per-service policy enforcement
- **Audit mode** for testing policies without blocking commands
- **Per-identity rate limiting** to prevent abuse

### Python Sandbox with Kernel-Level Isolation (Linux)
- **Linux namespace isolation**: Mount, PID, and network namespaces
- **Seccomp-BPF syscall filtering**: Block dangerous syscalls at the kernel level
- **Cgroups v2 resource limits**: Memory, CPU, and process count restrictions
- **Filesystem isolation**: Read-only system paths, restricted write paths
- **Network blocking**: Complete network isolation by default

### JSON API Mode
- **TCP server** for programmatic access (ideal for VM integration)
- **JSON request/response protocol** for code execution
- **Profile-based configuration** for different security levels
- **Async execution** with timeout and resource tracking

### Audit Logging with Code Hashing
- **JSON Lines format** for easy parsing and ingestion
- **SHA256 code hashing** for executed Python code
- **Session tracking** with unique identifiers
- **Execution metrics**: wall time, memory usage, exit codes
- **Sandbox lifecycle events**: enter, exit, violation tracking

## Installation

### Quick Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/sundarsub/sentra/main/install.sh | bash
```

### Install with Systemd Service (Linux)

```bash
curl -sSL https://raw.githubusercontent.com/sundarsub/sentra/main/install.sh | INSTALL_SYSTEMD=true bash
```

### Install Specific Version

```bash
curl -sSL https://raw.githubusercontent.com/sundarsub/sentra/main/install.sh | SENTRA_VERSION=2.0.0 bash
```

### Manual Installation

1. Download the appropriate binary from [Releases](https://github.com/sundarsub/sentra/releases)
2. Extract and install:
   ```bash
   tar xzf sentra-linux-x86_64.tar.gz
   sudo mv sentra /usr/local/bin/
   sudo mv python_runner /usr/lib/sentra/
   ```
3. Create configuration:
   ```bash
   sudo mkdir -p /etc/sentra/profiles
   sudo cp policy.yaml /etc/sentra/
   sudo cp profiles/*.yaml /etc/sentra/profiles/
   ```

### What Gets Installed

| Path | Description |
|------|-------------|
| `/usr/local/bin/sentra` | Main binary (REPL and API server) |
| `/usr/lib/sentra/python_runner` | Python sandbox executor |
| `/etc/sentra/policy.yaml` | Default execution policy |
| `/etc/sentra/profiles/` | Sandbox profile configurations |
| `/var/log/sentra/` | Audit log directory |

## Usage Examples

### Interactive REPL Mode

Start the interactive shell with policy enforcement:

```bash
# Use default policy
sentra

# Use custom policy
sentra --policy /path/to/policy.yaml

# Audit mode (log but don't block)
sentra --mode audit

# Verbose output
sentra -v
```

Example session:
```
+----------------------------------------------------------+
|              Sentra - Execution Governance               |
|         Universal Shell with Policy Enforcement          |
+----------------------------------------------------------+

[ok] Loaded policy from: /etc/sentra/policy.yaml
[ok] Policy: Policy v2.0 | Mode: Enforce | Default: Deny | Rules: 45
[ok] Rate limit: 60 commands per 60 seconds
[ok] Identity: developer

[sentra:enforce]$ ls -la
total 48
drwxr-xr-x  5 user user 4096 Feb 20 10:00 .
...

[sentra:enforce]$ sudo rm -rf /
[X] DENIED: sudo rm -rf /
  Rule:   block_sudo
  Reason: Privilege escalation via sudo is blocked

[sentra:enforce]$ status
Session Status:
  Session ID:        a1b2c3d4-5678-90ab-cdef-1234567890ab
  Identity:          developer
  Commands executed: 1
  Commands denied:   1
  Rate limit usage:  2/60 (per 60 sec)
```

### API Mode for OpenClaw VM Integration

Start the API server:

```bash
# Start API server on port 9800
sentra --api --port 9800

# With custom policy and logging
sentra --api --port 9800 --policy /etc/sentra/policy.yaml --log /var/log/sentra/api.jsonl
```

Send execution requests:

```bash
# Execute Python code
echo '{"code": "print(2 + 2)", "profile": "python_sandbox_v1"}' | nc localhost 9800
```

Response:
```json
{
  "exit_code": 0,
  "stdout": "4\n",
  "stderr": "",
  "wall_time_ms": 45,
  "peak_mem_mb": 12,
  "code_sha256": "8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92",
  "timed_out": false,
  "truncated_stdout": false,
  "truncated_stderr": false
}
```

API Request Format:
```json
{
  "code": "import math; print(math.pi)",
  "profile": "python_sandbox_v1",
  "cwd": "/work",
  "timeout_sec": 30,
  "mem_max_mb": 512,
  "pids_max": 64,
  "env": {
    "MY_VAR": "value"
  }
}
```

### Using with systemd (Linux)

```bash
# Enable and start the API service
sudo systemctl enable --now sentra-api

# Check status
sudo systemctl status sentra-api

# View logs
journalctl -u sentra-api -f
```

### Policy Configuration

Create a custom policy:

```yaml
# my-policy.yaml
version: "2.0"
mode: enforce
default: deny

rate_limit:
  max_commands: 100
  window_seconds: 60

rules:
  # Allow read-only git commands
  - id: git_read_only
    match:
      executable: "^git$"
      args_pattern: "^(status|log|diff|show|branch)"
    effect: allow

  # Block git push
  - id: git_block_push
    match:
      executable: "^git$"
      args_pattern: "^push"
    effect: deny
    reason: "Git push requires approval"

  # Allow npm for specific users
  - id: npm_for_developers
    match:
      executable: "^npm$"
      identity: "^developer-.*"
    effect: allow

  # Block access to .env files
  - id: block_env_files
    match:
      args_pattern: "\\.env"
    effect: deny
    reason: "Access to .env files is blocked"
```

## Sandbox Features

### Linux Namespace Isolation

Sentra uses Linux namespaces to isolate Python execution:

| Namespace | Purpose |
|-----------|---------|
| **Mount** | Isolate filesystem view, restrict accessible paths |
| **PID** | Isolate process tree, hide host processes |
| **Network** | Block all network access by default |

### Seccomp-BPF Syscall Filtering

The `restricted` syscall profile blocks dangerous syscalls:

```yaml
# Blocked syscall categories:
# - Process spawning: execve, execveat
# - Network: socket, connect, bind, listen, accept
# - Destructive FS: unlink, rmdir, rename
# - Permissions: chmod, chown
# - Privilege escalation: setuid, setgid, capset
# - Kernel: ptrace, mount, bpf, init_module
```

### Cgroups Resource Limits

Resource limits are enforced via cgroups v2:

| Limit | Default | Description |
|-------|---------|-------------|
| `mem_max_mb` | 512 | Maximum memory in MB |
| `cpu_max_percent` | 50 | CPU quota percentage |
| `pids_max` | 64 | Maximum process count |
| `timeout_sec` | 30 | Wall clock timeout |
| `max_stdout_bytes` | 200000 | Output truncation limit |

### Filesystem Isolation

Sandbox profiles define filesystem access:

```yaml
fs_defaults:
  cwd: "/work"
  read_allow:
    - "/work"
    - "/usr/lib/python3"
  write_allow:
    - "/work/tmp"
    - "/work/out"
  protected_deny:
    - "/"
    - "/etc"
    - "/proc"
    - "/sys"
```

## Policy v2.0 YAML Schema

### Root Level

```yaml
version: "2.0"           # Schema version
mode: enforce|audit      # enforce blocks, audit only logs
default: deny|allow      # Default when no rule matches

rate_limit:
  max_commands: 60       # Max commands per identity per window
  window_seconds: 60     # Sliding window duration

rules: []                # List of policy rules
profiles: {}             # Named sandbox profiles
capabilities: {}         # Named capability definitions
syscall_profiles: {}     # Named syscall filter profiles
```

### Rule Schema

```yaml
rules:
  - id: "unique_rule_id"           # Required: unique identifier
    match:
      executable: "^pattern$"       # Regex for executable name
      args_pattern: "pattern"       # Regex for argument string
      identity: "^user-.*"          # Regex for identity/username
    effect: allow|deny              # Required: rule action
    reason: "Human-readable reason" # Optional: shown on deny
```

### Sandbox Profile Schema

```yaml
profiles:
  python_sandbox_v1:
    runner: "/usr/lib/sentra/python_runner"
    python_bin: "/usr/bin/python3"
    deny_spawn_processes: true
    default_network: deny

    fs_defaults:
      cwd: "/work"
      read_allow: ["/work", "/usr/lib/python3"]
      write_allow: ["/work/tmp", "/work/out"]
      protected_deny: ["/", "/etc", "/proc", "/sys"]

    limits_defaults:
      timeout_sec: 30
      cpu_max_percent: 50
      mem_max_mb: 512
      pids_max: 64
      max_stdout_bytes: 200000
      max_stderr_bytes: 200000

    syscall_profile: restricted
```

### Capability Schema

```yaml
capabilities:
  exec_python:
    type: python
    profile: python_sandbox_v1
    allowed_python_argv: ["-u", "-B"]
```

### Syscall Profile Schema

```yaml
syscall_profiles:
  restricted:
    default: allow
    deny:
      - execve
      - socket
      - connect
      - unlink
      - chmod
      - ptrace
    allow: []
```

## Building from Source

### Prerequisites

- Rust 1.75+ (with cargo)
- Linux: libseccomp-dev (for seccomp support)

### Build Steps

```bash
# Clone repository
git clone https://github.com/sundarsub/sentra.git
cd sentra

# Build release binaries
cargo build --release

# Binaries are in target/release/
ls -la target/release/sentra target/release/python_runner
```

### Linux-specific Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install libseccomp-dev

# Fedora/RHEL
sudo dnf install libseccomp-devel

# Arch
sudo pacman -S libseccomp
```

### Running Tests

```bash
# Run all tests
cargo test

# Run with verbose output
cargo test -- --nocapture

# Run specific test module
cargo test policy::tests
```

### Development Build

```bash
# Debug build with faster compilation
cargo build

# Run directly
cargo run -- --policy policy.yaml

# Run API mode
cargo run -- --api --port 9800
```

## Architecture

```
+-------------------------------------------------------------+
|                    OpenClaw VM / Client                     |
+-----------------------------+-------------------------------+
                              | JSON API (TCP :9800)
                              v
+-------------------------------------------------------------+
|                         Sentra                              |
|  +-------------+  +--------------+  +------------------+    |
|  | API Server  |  |Policy Engine |  |  Audit Logger    |    |
|  |  (Tokio)    |  |  (Regex)     |  |  (JSON Lines)    |    |
|  +------+------+  +------+-------+  +--------+---------+    |
|         |                |                   |              |
|         v                v                   v              |
|  +-----------------------------------------------------+    |
|  |               Sandbox Executor                      |    |
|  |  +-----------+ +----------+ +---------------------+ |    |
|  |  | Namespace | | Seccomp  | | Cgroup Controller   | |    |
|  |  | Isolation | | BPF      | | (mem/cpu/pids)      | |    |
|  |  +-----------+ +----------+ +---------------------+ |    |
|  +------------------------+----------------------------+    |
+--------------------------+----------------------------------+
                           |
                           v
                   +---------------+
                   |python_runner  |
                   |  (isolated)   |
                   +---------------+
```

## Audit Log Format

Audit logs are JSON Lines format, one entry per line:

```json
{"timestamp":"2026-02-21T10:30:00Z","session_id":"abc-123","host":"server1","user":"developer","action":"exec","command":"git status","executable":"git","args":"status","cwd":"/home/dev/project","decision":"allowed","rule_id":"git_read_only","eval_duration_ms":0,"exec_duration_ms":45,"exit_code":0}
```

### Sandbox Execution Log Entry

```json
{
  "timestamp": "2026-02-21T10:30:00Z",
  "session_id": "abc-123",
  "host": "server1",
  "user": "api-client",
  "action": "sandbox_exec",
  "command": "print('hello')",
  "executable": "python3",
  "cwd": "/work",
  "decision": "allowed",
  "code_sha256": "8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92",
  "profile": "python_sandbox_v1",
  "sandbox_metrics": {
    "wall_time_ms": 45,
    "peak_mem_mb": 12,
    "timed_out": false
  },
  "exit_code": 0
}
```

### Event Types

| Event | Description |
|-------|-------------|
| `session_start` | Session began with policy info |
| `exec` | Command evaluation and execution |
| `sandbox_exec` | Sandboxed Python execution |
| `sandbox_enter` | Sandbox environment setup |
| `sandbox_exit` | Sandbox execution completed |
| `sandbox_violation` | Security policy violation |
| `session_end` | Session ended with statistics |

## Security Considerations

1. **Run as non-root**: Sentra should run as an unprivileged user in production
2. **Policy review**: Audit your policy.yaml before deployment
3. **Log monitoring**: Monitor audit logs for security events
4. **Network isolation**: The sandbox blocks all network by default
5. **Cgroup limits**: Set appropriate resource limits to prevent DoS

### Deployment as Forced Shell

When deployed as a ForceCommand or login shell:

1. Users cannot bypass the governance gateway
2. All commands are evaluated against policy
3. Rate limiting prevents automated attacks
4. Audit trail provides forensic visibility

```bash
# SSH forced command configuration
# /etc/ssh/sshd_config
Match User developer
    ForceCommand /usr/local/bin/sentra --policy /etc/sentra/policy.yaml
```

### Rate Limiting for Breach Containment

Rate limiting disrupts attack patterns:
- Automated reconnaissance is throttled
- Brute-force attempts are slowed
- Data exfiltration is rate-constrained

## License

Apache-2.0

## Author

Sundar Subramaniam

## Support

- Issues: [GitHub Issues](https://github.com/sundarsub/sentra/issues)
- Email: sentrahelp@gmail.com
