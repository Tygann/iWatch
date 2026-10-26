"""Exercise native Apple plist tools on macOS, with portable substitutes on CI."""
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

source = (pathlib.Path(__file__).parent / 'configure-trakt.sh').read_text()
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    if sys.platform != 'darwin':
        mock = root / 'plisttool'
        mock.write_text('''#!/usr/bin/env python3
import sys, plistlib, pathlib
args = sys.argv[1:]
if args[0] == '-c':
    try: print(plistlib.loads(pathlib.Path(args[2]).read_bytes())[args[1].split(':', 1)[1]])
    except Exception: sys.exit(1)
elif args[0] == '-create':
    assert args[1] == 'xml1'
    pathlib.Path(args[2]).write_bytes(plistlib.dumps({}))
elif args[0] in ('-replace', '-remove'):
    p = pathlib.Path(args[-1]); data = plistlib.loads(p.read_bytes())
    if args[0] == '-replace': data[args[1]] = args[3]
    else: data.pop(args[1], None)
    p.write_bytes(plistlib.dumps(data))
''')
        mock.chmod(0o755)
        source = source.replace('/usr/libexec/PlistBuddy', str(mock)).replace('/usr/bin/plutil', str(mock))
    script = root / 'configure.sh'
    script.write_text(source)
    bundle = root / 'App.app'
    bundle.mkdir()
    local = root / 'iWatch'
    local.mkdir()
    info = bundle / 'Info.plist'
    secrets = bundle / 'Secrets.plist'
    local_secrets = local / 'Secrets.plist'
    # Do not inherit any live configuration from the calling environment.
    base = dict(PATH=os.environ['PATH'], SRCROOT=str(root), TARGET_BUILD_DIR=str(root),
                UNLOCALIZED_RESOURCES_FOLDER_PATH='App.app', INFOPLIST_PATH='App.app/Info.plist',
                PRODUCT_BUNDLE_IDENTIFIER='com.tyler.iWatch', CONFIGURATION='Release')
    valid = {'TMDB_API_KEY': 'fixture-tmdb-key', 'TRAKT_CLIENT_ID': 'fixture-id', 'TRAKT_CLIENT_SECRET': 'fixture-secret'}
    cases = [
        ('missing', {}, {}, False),
        ('debug missing', {}, {'CONFIGURATION': 'Debug'}, True),
        ('archive missing', {}, {'CONFIGURATION': 'Debug', 'ACTION': 'install'}, False),
        ('local credentials', valid, {}, True),
        ('missing TMDb key', {k: v for k, v in valid.items() if k != 'TMDB_API_KEY'}, {}, False),
        ('placeholder TMDb key', dict(valid, TMDB_API_KEY='replace-with-key'), {}, False),
        ('whitespace TMDb key', dict(valid, TMDB_API_KEY='  '), {}, False),
        ('PKCE without secret', {k: v for k, v in valid.items() if k != 'TRAKT_CLIENT_SECRET'}, {}, True),
        ('placeholder', dict(valid, TRAKT_CLIENT_ID='replace-with-id'), {}, False),
        ('whitespace', dict(valid, TRAKT_CLIENT_ID='  '), {}, False),
        ('unresolved', dict(valid, TRAKT_CLIENT_ID='$(TRAKT_CLIENT_ID)'), {}, False),
        ('migrate legacy redirect', dict(valid, TRAKT_REDIRECT_URI='com.tyler.iWatch://oauth/callback'), {}, True),
        ('HTTPS redirect', dict(valid, TRAKT_REDIRECT_URI='https://tylerkeegan.com/iwatch/oauth/trakt'), {}, True),
        ('bad redirect', dict(valid, TRAKT_REDIRECT_URI='other://oauth/callback'), {}, False),
        ('CI without local file', {}, valid, True),
        ('CI overrides local', dict(valid, TRAKT_CLIENT_ID='old-id'), valid, True),
    ]
    def run(extra, expected):
        result = subprocess.run(['/bin/sh', str(script)], env=base | extra, capture_output=True, text=True)
        assert (result.returncode == 0) == expected, 'Unexpected configuration result'
        assert 'fixture-secret' not in result.stdout + result.stderr
        assert 'fixture-tmdb-key' not in result.stdout + result.stderr
    for name, values, extra, expected in cases:
        info.write_bytes(plistlib.dumps({}))
        secrets.unlink(missing_ok=True)
        local_secrets.unlink(missing_ok=True)
        if values:
            local_secrets.write_bytes(plistlib.dumps(values))
        before = local_secrets.read_bytes() if local_secrets.exists() else None
        run(extra, expected)
        assert (local_secrets.read_bytes() if local_secrets.exists() else None) == before
        if name.startswith('CI'):
            assert plistlib.loads(info.read_bytes())['TRAKT_CLIENT_ID'] == 'fixture-id'
            assert plistlib.loads(info.read_bytes())['TMDB_API_KEY'] == 'fixture-tmdb-key'
        assert 'TRAKT_CLIENT_SECRET' not in plistlib.loads(info.read_bytes())
        if secrets.exists():
            assert 'TRAKT_CLIENT_SECRET' not in plistlib.loads(secrets.read_bytes())
        print('PASS:', name)
    local_secrets.unlink(missing_ok=True)
    run(valid, True)
    run({}, False)
    assert not secrets.exists()
    assert 'TRAKT_CLIENT_ID' not in plistlib.loads(info.read_bytes())
    assert 'TMDB_API_KEY' not in plistlib.loads(info.read_bytes())
    print('PASS: removed CI inputs cannot reuse stale credentials')
    local_secrets.write_bytes(plistlib.dumps(valid))
    run({}, True)
    local_secrets.unlink()
    run({}, False)
    print('PASS: removed local file cannot reuse stale credentials')

    checks = root / 'scripts'
    checks.mkdir()
    (checks / 'check-cloudkit-schema.py').write_text("import os, sys\nassert sys.argv[1:] == ['--live']\nsys.exit(int(os.environ.get('FIXTURE_SCHEMA_EXIT', '0')))\n")
    run(valid | {'CI_XCODE_CLOUD': 'TRUE'}, True)
    print('PASS: cloud Release requires successful schema check')
    run(valid | {'CI_XCODE_CLOUD': 'TRUE', 'FIXTURE_SCHEMA_EXIT': '1'}, False)
    print('PASS: cloud Release rejects failed schema check')
    run(valid | {'CI_XCODE_CLOUD': 'TRUE', 'CONFIGURATION': 'Debug', 'FIXTURE_SCHEMA_EXIT': '1'}, True)
    print('PASS: cloud Debug skips release schema gate')
