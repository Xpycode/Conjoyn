import pathlib,subprocess,time,json,shutil,os
import ctypes
_lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
_lib.mach_absolute_time.restype = ctypes.c_uint64
class _Timebase(ctypes.Structure):
    _fields_ = [('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
_tb = _Timebase()
assert _lib.mach_timebase_info(ctypes.byref(_tb)) == 0
def shared_clock(): return _lib.mach_absolute_time() * _tb.numer / _tb.denom / 1e9
B=pathlib.Path(__file__).resolve().parent
V=pathlib.Path('/Volumes/4.x - MORE/Conjoyn-Acceptance-20261010')
UI=str(B.parent/'E1-Acceptance/ui')
events=[]
def record(kind,**kw):
    events.append(dict(kind=kind,mono=shared_clock(),**kw))
    (B/'timing-actions.json').write_text(json.dumps(events,indent=2))
def run(*args): return subprocess.check_output(args,text=True,timeout=20)
def wait(fn,seconds=25):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        result=fn()
        if result:return result
        time.sleep(.05)
    raise RuntimeError('Observation deadline exceeded')
def probes():
    return [json.loads(line) for line in (B/'probe-events.jsonl').read_text().splitlines()]
def snapshot(name): (B/(name+'-ax.txt')).write_text(run(UI,'dump'))
try:
    record('launch',result=run('swift',str(B/'launch.swift')))
    wait(lambda:(B/'trailing.claimed').exists())
    record('reader-held')
    shutil.copy2(B/'strong-fixture.MP4',V/'timing-repeat/DJI_0023.MP4')
    record('new-file-written',path=str(V/'timing-repeat/DJI_0023.MP4'))
    time.sleep(3)
    assert not list((B/'timing-repeat-output').glob('*.mp4'))
    assert any(p['kind']=='held' and p.get('gate')=='trailing' for p in probes())
    assert not any(p['kind']=='released' and p.get('gate')=='trailing' for p in probes())
    record('no-early-output')
    (B/'trailing.release').touch();record('release-trailing')
    wait(lambda:len(list((B/'timing-repeat-output').glob('*.mp4')))==2)
    record('trailing-two-outputs',files=[p.name for p in (B/'timing-repeat-output').glob('*.mp4')])
    run(UI,'press','Watch Folders…');snapshot('trailing')
    (B/'gate.json').write_text(json.dumps({'name':'disable','match':'/timing-repeat/DJI_0025.MP4'}))
    shutil.copy2(B/'strong-fixture.MP4',V/'timing-repeat/DJI_0025.MP4');record('disable-new-file')
    wait(lambda:(B/'disable.claimed').exists());record('disable-reader-held')
    record('disable-ui-action',result=run(UI,'press','role:AXCheckBox','2'))
    snapshot('disable-held')
    (B/'disable.release').touch();record('release-disabled-reader')
    wait(lambda:any(p['kind']=='end' and any('/timing-repeat/DJI_0025.MP4' in a for a in p['args']) for p in probes()))
    time.sleep(5)
    queue=json.loads((B/'Home/Library/Application Support/Conjoyn/queue.json').read_text())
    assert not any(any('DJI_0025' in c['videoFilePath'] for c in j['clips']) for j in queue)
    assert len(list((B/'timing-repeat-output').glob('*.mp4')))==2
    snapshot('disable-after')
    record('disable-pass',queue_jobs=len(queue),timing_outputs=2)
finally:
    for name in ['trailing','disable']:(B/(name+'.release')).touch()
