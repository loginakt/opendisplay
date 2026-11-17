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
# Keep stdin's writer alive after the parent crashes; EOF cannot explain this exit.
import os, time
read_fd, write_fd = os.pipe()
status_read, status_write = os.pipe()
proxy_code = 'import subprocess,sys,time; p=subprocess.Popen([sys.argv[1],"--control-stdio"],stdin=int(sys.argv[2]),stdout=int(sys.argv[3]),stderr=subprocess.DEVNULL); print(p.pid,flush=True); time.sleep(30)'
proxy = subprocess.Popen([sys.executable, '-c', proxy_code, engine, str(read_fd), str(status_write)], pass_fds=(read_fd,status_write), stdout=subprocess.PIPE, text=True)
helper_pid = int(proxy.stdout.readline())
os.close(read_fd); os.close(status_write)
try:
    selector = selectors.DefaultSelector(); selector.register(status_read, selectors.EVENT_READ)
    assert selector.select(10), 'orphan test helper did not start'
    assert json.loads(os.read(status_read, 65_536).splitlines()[0])['transport'] == 'usb'
    proxy.kill(); proxy.wait(timeout=5)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        state = subprocess.run(['/bin/ps','-p',str(helper_pid),'-o','stat='], capture_output=True,text=True).stdout.strip()
        if not state or state.startswith('Z'): break
        time.sleep(0.05)
    else: raise AssertionError('orphan helper survived parent death with stdin held open')
finally:
    if proxy.poll() is None: proxy.kill(); proxy.wait()
    os.close(write_fd); os.close(status_read)
    try: os.kill(helper_pid, 9)
    except ProcessLookupError: pass
print('PASS: parent-process watchdog exits even when another process keeps stdin open')
