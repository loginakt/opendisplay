#!/usr/bin/env python3
"""Smoke-test the actual helper: rejects network CLI, no IP sockets, parent EOF stops it."""
import json, selectors, subprocess, sys
from pathlib import Path
engine = str(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/USBDisplayEngine').resolve())
for args in [['-host', '127.0.0.1'], ['--port', '9000'], ['--wifi']]:
    result = subprocess.run([engine, *args], capture_output=True, timeout=5)
    assert result.returncode == 64, (args, result.returncode)
p = subprocess.Popen([engine, '--control-stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
try:
    selector = selectors.DefaultSelector(); selector.register(p.stdout, selectors.EVENT_READ)
    assert selector.select(10), 'helper did not publish initial state'
    state = json.loads(p.stdout.readline())
    assert state['transport'] == 'usb' and state['activeDevice'] == ''
    sockets = subprocess.run(['/usr/sbin/lsof', '-nP', '-a', '-p', str(p.pid), '-i'], capture_output=True, text=True)
    assert sockets.returncode == 1 and not sockets.stdout, sockets.stdout
    p.stdin.write(b'{"action":"connect","device":"nonexistent","mode":"extend","host":"192.168.1.2"}\n'); p.stdin.flush()
    p.stdin.close()
    assert p.wait(timeout=10) == 0
finally:
    if p.poll() is None: p.kill(); p.wait()
print('PASS: rejected network CLI, USB-only initial state, no IPv4/IPv6 sockets, parent EOF terminates engine')
