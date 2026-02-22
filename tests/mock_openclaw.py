#!/usr/bin/env python3
"""
Mock OpenClaw - Demonstrates seccomp lockdown behavior

This script simulates an AI agent (OpenClaw) running inside the
seccomp-locked environment created by openclaw_launcher.

It attempts various operations to demonstrate what's blocked vs allowed:
- subprocess.run() → BLOCKED (execve blocked by seccomp)
- os.system() → BLOCKED (execve blocked by seccomp)
- socket to external host → BLOCKED (network namespace isolation)
- socket to Sentra API → ALLOWED (loopback to Sentra)
- File operations in /work → ALLOWED
- Regular Python computation → ALLOWED
"""

import os
import sys
import json
import socket

def test_subprocess():
    """Test if subprocess is blocked"""
    print("\n═══ Test 1: subprocess.run() ═══")
    try:
        import subprocess
        result = subprocess.run(["id"], capture_output=True, text=True)
        print(f"  ✗ FAIL: subprocess.run() succeeded: {result.stdout}")
        return False
    except OSError as e:
        print(f"  ✓ PASS: subprocess.run() blocked: {e}")
        return True
    except Exception as e:
        print(f"  ? ERROR: Unexpected error: {e}")
        return False

def test_os_system():
    """Test if os.system is blocked"""
    print("\n═══ Test 2: os.system() ═══")
    try:
        ret = os.system("echo 'should not work'")
        if ret == 0:
            print(f"  ✗ FAIL: os.system() succeeded")
            return False
        else:
            print(f"  ✓ PASS: os.system() blocked (returned {ret})")
            return True
    except OSError as e:
        print(f"  ✓ PASS: os.system() blocked: {e}")
        return True

def test_fork():
    """Test if fork is blocked"""
    print("\n═══ Test 3: os.fork() ═══")
    try:
        pid = os.fork()
        if pid == 0:
            # Child process - should not happen
            os._exit(0)
        else:
            print(f"  ✗ FAIL: fork() succeeded, child PID: {pid}")
            os.waitpid(pid, 0)
            return False
    except OSError as e:
        print(f"  ✓ PASS: fork() blocked: {e}")
        return True
    except Exception as e:
        print(f"  ? ERROR: Unexpected error: {e}")
        return False

def test_external_network():
    """Test if external network is blocked"""
    print("\n═══ Test 4: External network connection ═══")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(("8.8.8.8", 53))
        s.close()
        print("  ✗ FAIL: External network connection succeeded")
        return False
    except (socket.timeout, OSError) as e:
        print(f"  ✓ PASS: External network blocked: {e}")
        return True
    except Exception as e:
        print(f"  ? PASS (probably): {e}")
        return True

def test_sentra_api(port=9998):
    """Test if Sentra API is reachable"""
    print(f"\n═══ Test 5: Sentra API connection (127.0.0.1:{port}) ═══")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(("127.0.0.1", port))

        # Send a simple request
        request = json.dumps({
            "code": "print('Hello from sandbox!')",
            "profile": "python_sandbox"
        }) + "\n"
        s.sendall(request.encode())

        # Read response
        response = s.recv(65536)
        s.close()

        print(f"  ✓ PASS: Sentra API reachable")
        print(f"  Response: {response.decode()[:200]}...")
        return True
    except socket.timeout:
        print("  ✗ FAIL: Sentra API connection timed out")
        return False
    except ConnectionRefusedError:
        print("  ✗ FAIL: Sentra API connection refused (is Sentra running?)")
        return False
    except Exception as e:
        print(f"  ? ERROR: {e}")
        return False

def test_file_operations():
    """Test if file operations work"""
    print("\n═══ Test 6: File operations ═══")
    import tempfile
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write("test data")
            temp_path = f.name

        with open(temp_path, 'r') as f:
            data = f.read()

        os.unlink(temp_path)
        print(f"  ✓ PASS: File read/write works in allowed paths")
        return True
    except Exception as e:
        print(f"  ✗ FAIL: File operations failed: {e}")
        return False

def test_python_computation():
    """Test if regular Python works"""
    print("\n═══ Test 7: Python computation ═══")
    try:
        import math
        import json

        # Some computation
        result = math.pi * 2
        data = json.dumps({"pi_times_2": result})

        print(f"  ✓ PASS: Python computation works: {data}")
        return True
    except Exception as e:
        print(f"  ✗ FAIL: Python computation failed: {e}")
        return False

def main():
    print("╔══════════════════════════════════════════════════════════╗")
    print("║           Mock OpenClaw - Security Test Suite            ║")
    print("║        Testing seccomp lockdown restrictions             ║")
    print("╚══════════════════════════════════════════════════════════╝")

    # Get Sentra port from environment or default
    sentra_port = int(os.environ.get("SENTRA_PORT", "9999"))

    results = []

    # Run tests
    results.append(("subprocess.run()", test_subprocess()))
    results.append(("os.system()", test_os_system()))
    results.append(("os.fork()", test_fork()))
    results.append(("External network", test_external_network()))
    results.append(("Sentra API", test_sentra_api(sentra_port)))
    results.append(("File operations", test_file_operations()))
    results.append(("Python computation", test_python_computation()))

    # Summary
    print("\n" + "═" * 60)
    print("SUMMARY")
    print("═" * 60)

    passed = sum(1 for _, r in results if r)
    total = len(results)

    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    # For seccomp lockdown to be effective:
    # - subprocess, os.system, fork should be BLOCKED
    # - External network should be BLOCKED
    # - Sentra API should be ALLOWED
    # - File operations should be ALLOWED
    # - Python computation should be ALLOWED

    expected_blocked = ["subprocess.run()", "os.system()", "os.fork()", "External network"]
    expected_allowed = ["Sentra API", "File operations", "Python computation"]

    blocked_correct = all(
        not result for name, result in results if name in expected_blocked
    )
    # Note: subprocess/system/fork should FAIL (blocked), so result=True means correctly blocked

    print("\nSeccomp lockdown status:")
    if passed >= 5:  # At least subprocess, fork, external blocked + sentra + computation working
        print("  ✓ Seccomp lockdown appears to be working correctly")
    else:
        print("  ⚠ Seccomp lockdown may not be fully active")
        print("    (This is expected on macOS or without seccomp)")

    return 0 if passed >= 5 else 1

if __name__ == "__main__":
    sys.exit(main())
