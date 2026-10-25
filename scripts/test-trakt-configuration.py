import os, pathlib, plistlib, subprocess, tempfile
# Portable control-flow tests; Apple plist tools are substituted on Linux.
source=(pathlib.Path(__file__).resolve().parent / 'configure-trakt.sh').read_text()
with tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d)
    mock=root/'plisttool'
    mock.write_text('''#!/usr/bin/env python3
import sys,plistlib,pathlib
args=sys.argv[1:]
if args[0]=='-c':
    try: print(plistlib.loads(pathlib.Path(args[2]).read_bytes())[args[1].split(':',1)[1]])
    except Exception: sys.exit(1)
elif args[0]=='-create': pathlib.Path(args[2]).write_bytes(plistlib.dumps({}))
elif args[0]=='-replace':
    p=pathlib.Path(args[4]); data=plistlib.loads(p.read_bytes()); data[args[1]]=args[3]; p.write_bytes(plistlib.dumps(data))
''')
    mock.chmod(0o755)
    script=root/'configure.sh'
    script.write_text(source.replace('/usr/libexec/PlistBuddy',str(mock)).replace('/usr/bin/plutil',str(mock)))
    bundle=root/'App.app'; bundle.mkdir()
    info=bundle/'Info.plist'; secrets=bundle/'Secrets.plist'
    base=dict(os.environ,TARGET_BUILD_DIR=str(root),UNLOCALIZED_RESOURCES_FOLDER_PATH='App.app',INFOPLIST_PATH='App.app/Info.plist',PRODUCT_BUNDLE_IDENTIFIER='com.tyler.iWatch',CONFIGURATION='Release')
    valid={'TRAKT_CLIENT_ID':'fixture-id','TRAKT_CLIENT_SECRET':'fixture-secret'}
    cases=[('missing',{}, {}, {},False),('debug missing',{}, {},{'CONFIGURATION':'Debug'},True),('archive missing',{}, {},{'CONFIGURATION':'Debug','ACTION':'install'},False),('local credentials',{},valid,{},True),('missing secret',{}, {'TRAKT_CLIENT_ID':'fixture-id'},{},False),('placeholder',{},dict(valid,TRAKT_CLIENT_ID='replace-with-your-trakt-client-id'),{},False),('whitespace',{},dict(valid,TRAKT_CLIENT_ID='  '),{},False),('unresolved',{},dict(valid,TRAKT_CLIENT_ID='$(TRAKT_CLIENT_ID)'),{},False),('bad redirect',{},dict(valid,TRAKT_REDIRECT_URI='other://oauth/callback'),{},False),('Info precedence',{'TRAKT_CLIENT_ID':'replace-with-id'},valid,{},False),('CI overrides stale Info',{'TRAKT_CLIENT_ID':'replace-with-id'}, {},valid,True)]
    for name,i,s,e,success in cases:
        info.write_bytes(plistlib.dumps(i)); secrets.write_bytes(plistlib.dumps(s))
        result=subprocess.run(['/bin/sh',str(script)],env=base|e,capture_output=True,text=True)
        assert (result.returncode==0)==success,(name,result.stdout,result.stderr)
        assert 'fixture-secret' not in result.stdout+result.stderr
        if name=='CI overrides stale Info':
            assert plistlib.loads(secrets.read_bytes())['TRAKT_CLIENT_ID']=='fixture-id'
        print('PASS:',name)
