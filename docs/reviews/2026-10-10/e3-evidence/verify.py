import pathlib,subprocess,json,plistlib,hashlib,datetime
root=pathlib.Path.cwd()
base=root/'01_Project/build/E3-Acceptance'
app=base/'export/Conjoyn.app'
def run(*args):
 p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 if p.returncode:raise RuntimeError(f'{args}: {p.returncode}\n{p.stdout}')
 return p.stdout
plist=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert plist['CFBundleShortVersionString']=='1.0.6'
assert plist['CFBundleVersion']=='106'
assert plist['CFBundleIdentifier']=='com.lucesumbrarum.conjoyn'
verification=run('codesign','--verify','--deep','--strict','--verbose=2',str(app))
spk=app/'Contents/Frameworks/Sparkle.framework/Versions/B'
paths={'app':app,'ffmpeg':app/'Contents/Resources/Helpers/ffmpeg','ffprobe':app/'Contents/Resources/Helpers/ffprobe','Sparkle':spk/'Sparkle','Autoupdate':spk/'Autoupdate','Updater':spk/'Updater.app/Contents/MacOS/Updater','Installer':spk/'XPCServices/Installer.xpc/Contents/MacOS/Installer','Downloader':spk/'XPCServices/Downloader.xpc/Contents/MacOS/Downloader'}
signatures={}
for label,path in paths.items():
 s=run('codesign','-dvvv',str(path))
 assert 'Authority=Developer ID Application:' in s and 'TeamIdentifier=FDMSRXXN73' in s
 assert 'flags=0x10000(runtime)' in s and 'Timestamp=' in s
 signatures[label]=s
helpers={n:run(str(paths[n]),'-version') for n in ['ffmpeg','ffprobe']}
exe=app/'Contents/MacOS/Conjoyn'
files={str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(app.rglob('*')) if p.is_file() and not p.is_symlink()}
symlinks={str(p.relative_to(app)):str(p.readlink()) for p in sorted(app.rglob('*')) if p.is_symlink()}
m=json.load(open('docs/reviews/2026-10-10/release-source-freeze.json'))
for key in ['source_files_sha256','build_inputs_sha256']:
 assert all(hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()==h for p,h in m[key].items())
result={'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_commit':m['source_commit'],'app_path':str(app),'version':'1.0.6','build':'106','status':'locally signed only; notarization and E3 acceptance pending','signature_verification':verification,'signatures':signatures,'entitlements':run('codesign','-d','--entitlements',':-',str(app)),'architectures':run('lipo','-archs',str(exe)),'helper_versions':helpers,'bundle_file_sha256':files,'bundle_symlinks':symlinks,'source_hashes_match':170,'build_inputs_match':7}
(base/'local-artifact.json').write_text(json.dumps(result,indent=2)+'\n')
print('Verified 1.0.6/106; 8 Developer-ID runtime signatures with team and timestamps; both helpers execute.')
print('App architectures:',result['architectures'].strip())
print('Executable SHA256:',files['Contents/MacOS/Conjoyn'])
