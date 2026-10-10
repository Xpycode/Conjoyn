import pathlib, subprocess, json, plistlib, time, shutil, ctypes
B=pathlib.Path(__file__).resolve().parent
E=B/'mount-evidence'
V=pathlib.Path('/Volumes/4.x - MORE')
UUID='A7FC471B-9BBD-4190-98B6-0A5D3FA30278'
UI=str(B.parent/'E1-Acceptance/ui')
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib');lib.mach_absolute_time.restype=ctypes.c_uint64
class TB(ctypes.Structure):_fields_=[('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
tb=TB();assert lib.mach_timebase_info(ctypes.byref(tb))==0
def now():return lib.mach_absolute_time()*tb.numer/tb.denom/1e9
def record(kind,**kw):
    with (E/'mount-actions.jsonl').open('a') as f:f.write(json.dumps(dict(kind=kind,mono=now(),**kw))+'\n')
def run(*args,timeout=25):return subprocess.check_output(args,text=True,timeout=timeout)
def info():
    value=plistlib.loads(subprocess.check_output(['diskutil','info','-plist',UUID],timeout=10))
    assert value['VolumeUUID']==UUID
    value['Mounted']=bool(value.get('MountPoint'))
    return value
def unmount(allow_owned_read=False):
    d=info();assert d['Mounted']
    opened=subprocess.run(['lsof','+f','--',d['MountPoint']],capture_output=True,text=True,timeout=10)
    if opened.stdout.strip():
        assert allow_owned_read,opened.stdout+opened.stderr
        rows=[line.split(None,8) for line in opened.stdout.splitlines()[1:]]
        assert rows and all(len(r)==9 and r[0]=='Conjoyn' and r[3].endswith('r') and '/Conjoyn-Acceptance-20261010/' in r[8] for r in rows),rows
        for r in rows:
            executable=run('ps','-p',r[1],'-o','comm=').strip()
            assert executable==str(B/'Conjoyn.app/Contents/MacOS/Conjoyn'),executable
        record('owned-read-open-at-unmount',rows=rows)
    else:assert opened.returncode==1,opened.stderr
    record('unmount-request',device=d['DeviceIdentifier'],mount=d['MountPoint'])
    result=run('diskutil','unmount',d['DeviceIdentifier'])
    assert not info()['Mounted'];record('unmounted',result=result)
def mount():
    d=info()
    if not d['Mounted']:
        record('mount-request',device=d['DeviceIdentifier'])
        result=run('diskutil','mount',d['DeviceIdentifier']);record('mounted',result=result)
    d=info();assert d['Mounted'] and d['MountPoint']==str(V),d
def wait(fn,seconds=30):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        value=fn()
        if value:return value
        time.sleep(.15)
    raise RuntimeError('Observation deadline exceeded')
def snapshot(name):
    text=run(UI,'dump');(E/(name+'-ax.txt')).write_text(text);record('snapshot',name=name);return text
def outputs(name):return sorted(p.name for p in (B/name).glob('*.mp4'))
if __name__=='__main__':
    try:
        (E/'device-before.plist').write_bytes(plistlib.dumps(info()))
        unmount()
        record('launch-absent',result=run('swift',str(B/'launch.swift')))
        run(UI,'press','Watch Folders…')
        tree=snapshot('absent-at-launch')
        assert not info()['Mounted'] and not outputs('mount-device-output')
        shutil.copy2(B/'strong-fixture.MP4',B/'mount-healthy/DJI_0051.MP4');record('healthy-added-while-absent')
        wait(lambda:len(outputs('mount-healthy-output'))==1)
        assert not info()['Mounted'];record('healthy-exported-while-absent')
        snapshot('healthy-while-absent')
        mount()
        wait(lambda:len(outputs('mount-device-output'))==1)
        record('external-exported-after-mount',outputs=outputs('mount-device-output'))
        snapshot('mounted-recovered')
    finally:
        mount()
