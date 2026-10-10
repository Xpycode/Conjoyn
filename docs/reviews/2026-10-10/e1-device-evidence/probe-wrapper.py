#!/usr/bin/python3
"""Acceptance-only helper gate; the app executable and compiled library are unchanged."""
import json, os, pathlib, subprocess, sys, time
import ctypes
_lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
_lib.mach_absolute_time.restype = ctypes.c_uint64
class _Timebase(ctypes.Structure):
    _fields_ = [('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
_tb = _Timebase()
assert _lib.mach_timebase_info(ctypes.byref(_tb)) == 0
def shared_clock(): return _lib.mach_absolute_time() * _tb.numer / _tb.denom / 1e9
BASE=pathlib.Path('/Users/sim/ProgrammingProjects/1-macOS/Conjoyn/01_Project/build/E1-Device-Acceptance')
def log(kind, **extra):
    line=json.dumps(dict(kind=kind,pid=os.getpid(),parent=os.getppid(),mono=shared_clock(),args=sys.argv[1:],**extra))+'\n'
    fd=os.open(str(BASE/'probe-events.jsonl'),os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
    try: os.write(fd,line.encode())
    finally: os.close(fd)
log('begin')
config=BASE/'gate.json'
if config.exists():
    c=json.loads(config.read_text())
    if any(c['match'] in arg for arg in sys.argv[1:]):
        claim=BASE/(c['name']+'.claimed')
        try: fd=os.open(str(claim),os.O_CREAT|os.O_EXCL|os.O_WRONLY)
        except FileExistsError: pass
        else:
            os.close(fd)
            log('held',gate=c['name'])
            deadline=time.monotonic()+45
            release=BASE/(c['name']+'.release')
            while not release.exists() and time.monotonic()<deadline: time.sleep(.025)
            log('released',gate=c['name'],explicit=release.exists())
result=subprocess.run([str(pathlib.Path(__file__).with_name('ffprobe.real'))]+sys.argv[1:])
log('end',returncode=result.returncode)
sys.exit(result.returncode)
