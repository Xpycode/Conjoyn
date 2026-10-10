import runpy,pathlib,subprocess,json,time,shutil
m=runpy.run_path(str(pathlib.Path(__file__).with_name('mount-test.py')))
globals().update({k:v for k,v in m.items() if not k.startswith('__')})
ALT=pathlib.Path('/private/tmp/Conjoyn-E1-Physical-Mount-20261010')
def probes():
    p=E/'probe-events.jsonl'
    return [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
def has43():
    p=B/'Home/Library/Application Support/Conjoyn/queue.json'
    return p.exists() and any('DJI_0045' in c['videoFilePath'] for j in json.loads(p.read_text()) for c in j['clips'])
def waiting():
    tree=run(UI,'dump');i=tree.find('AXValue=mount-device')
    return i>=0 and 'AXValue=WAITING' in tree[i:i+180]
try:
    run(UI,'press','Watch Folders…')
    wait(lambda:any(any('/mount-healthy/DJI_0051.MP4' in a for a in p['args']) and p['kind']=='end' for p in probes()))
    shutil.copy2(B/'strong-fixture.MP4',V/'Conjoyn-Acceptance-20261010/mount-device/DJI_0045.MP4')
    record('loss-new-file-added')
    wait(lambda:(B/'mount-loss2.claimed').exists())
    held=next(p for p in probes() if p['kind']=='held' and p.get('gate')=='mount-loss2')
    record('loss-reader-held',pid=held['pid'])
    unmount(allow_owned_read=True)
    wait(waiting);snapshot('unmounted-during-reader')
    (B/'mount-loss2.release').touch();record('release-offline-reader')
    wait(lambda:any(p['kind']=='end' and p['pid']==held['pid'] for p in probes()))
    assert not has43() and len(outputs('mount-device-output'))==2
    record('old-reader-no-admission')
    shutil.copy2(B/'strong-fixture.MP4',B/'mount-healthy/DJI_0053.MP4');record('healthy-added-during-loss')
    wait(lambda:len(outputs('mount-healthy-output'))==2)
    assert not info()['Mounted'];snapshot('healthy-during-loss')
    record('healthy-completed-during-loss')
    assert not ALT.exists();ALT.mkdir()
    d=info();record('alternate-mount-request',path=str(ALT))
    result=run('diskutil','mount','-mountPoint',str(ALT),d['DeviceIdentifier'])
    assert info()['MountPoint']==str(ALT);record('alternate-mounted',result=result)
    wait(lambda:len(outputs('mount-device-output'))==3)
    tree=snapshot('alternate-path-recovered')
    assert str(ALT)+'/Conjoyn-Acceptance-20261010/mount-device' in tree
    p=B/'Home/Library/Application Support/Conjoyn/queue.json'
    shutil.copy2(p,E/'alternate-path-queue.json')
    jobs=json.loads(p.read_text())
    job=next(j for j in jobs if any('DJI_0045' in c['videoFilePath'] for c in j['clips']))
    assert all(c['videoFilePath'].startswith(str(ALT)) for c in job['clips'])
    record('recovered-at-alternate-path',outputs=outputs('mount-device-output'))
    time.sleep(3)
    unmount();mount()
    wait(lambda:not waiting());snapshot('original-path-restored')
    time.sleep(5)
    assert len(outputs('mount-device-output'))==3 and len(outputs('mount-healthy-output'))==2
    record('normal-path-no-duplicates')
finally:
    (B/'mount-loss2.release').touch()
    d=info()
    if d['Mounted'] and d['MountPoint']!=str(V):unmount()
    mount()
    if ALT.exists() and not any(ALT.iterdir()):ALT.rmdir()
