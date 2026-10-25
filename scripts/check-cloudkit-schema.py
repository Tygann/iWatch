#!/usr/bin/env python3
"""Read-only preflight: compare required SwiftData fields with Production schema."""
import argparse
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TYPES = {'String': 'STRING', 'UUID': 'STRING', 'Int': 'INT64', 'Int64': 'INT64',
         'Bool': 'INT64', 'Double': 'DOUBLE', 'Date': 'TIMESTAMP', 'Data': 'BYTES', '[String]': 'BYTES'}


def required_schema(root=ROOT):
    persistence = (root / 'iWatch/Data/Local/Persistence.swift').read_text()
    schema = re.search(r'let schema = Schema\(\[(.*?)\]\)', persistence, re.S)
    if not schema:
        raise ValueError('Could not identify the SwiftData schema')
    names = re.findall(r'(\w+)\.self', schema[1])
    models = {}
    for source in (root / 'iWatch/Data/Local').rglob('*.swift'):
        text = source.read_text()
        for model in re.finditer(r'@Model\s+(?:final\s+)?class\s+(\w+)\s*\{', text):
            name = model[1]
            if name not in names:
                continue
            fields = {'CD_entityName': 'STRING'}
            declarations = text[model.end():].split('    init(', 1)[0]
            for line in declarations.splitlines():
                field = re.match(r'\s*var (\w+):\s*([^=]+?)(?:\s*=.*)?$', line)
                if not field or '{' in line:
                    continue
                field_type = field[2].strip().rstrip('?')
                if field_type not in TYPES:
                    raise ValueError(f'Unsupported stored type: {name}.{field[1]} ({field_type})')
                fields['CD_' + field[1]] = TYPES[field_type]
            models['CD_' + name] = fields
    if set(models) != {'CD_' + name for name in names}:
        raise ValueError('Some SwiftData models could not be inspected')
    return models


def check_schema(text, required):
    actual = {}
    for record in re.finditer(r'RECORD\s+TYPE\s+(\w+)\s*\((.*?)\);', text, re.S):
        actual[record[1]] = dict(re.findall(r'^\s*(CD_\w+)\s+(\w+)', record[2], re.M))
    errors = []
    for name, fields in sorted(required.items()):
        if name not in actual:
            errors.append(f'Missing record type {name}')
            continue
        for field, kind in sorted(fields.items()):
            found = actual[name].get(field)
            if found != kind:
                errors.append(f'{name}.{field}: expected {kind}, found {found or "missing"}')
    return errors


def self_test(required):
    def fixture(models):
        return '\n'.join('RECORD TYPE ' + name + ' (\n' + '\n'.join('  ' + key + ' ' + kind + ',' for key, kind in fields.items()) + '\n);' for name, fields in models.items())
    valid = fixture(required)
    assert not check_schema(valid, required)
    name = next(iter(required))
    assert check_schema(fixture({k: v for k, v in required.items() if k != name}), required)
    broken = {k: dict(v) for k, v in required.items()}
    broken[name].pop('CD_entityName')
    assert check_schema(fixture(broken), required)
    broken[name]['CD_entityName'] = 'INT64'
    assert check_schema(fixture(broken), required)
    assert not check_schema(valid + '\nRECORD TYPE Extra (\n CD_extra STRING\n);', required)
    print(f'PASS: schema parser and validation ({len(required)} models)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--schema', type=pathlib.Path, help='Production schema exported from CloudKit Console')
    modes.add_argument('--live', action='store_true', help='Export Production with cktool using its private environment/keychain token')
    modes.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    try:
        required = required_schema()
        if args.self_test:
            self_test(required)
            return 0
        with tempfile.TemporaryDirectory(prefix='iwatch-schema-') as temporary:
            schema = args.schema
            if args.live:
                schema = pathlib.Path(temporary) / 'production.ckdb'
                result = subprocess.run(['xcrun', 'cktool', 'export-schema', '--team-id', 'XKQ424HQ33',
                    '--container-id', 'iCloud.com.tyler.iWatch', '--environment', 'production', '--output-file', str(schema)],
                    capture_output=True, text=True, timeout=120)
                if result.returncode:
                    print('error: Could not export CloudKit Production schema. Configure a private CLOUDKIT_MANAGEMENT_TOKEN or use --schema with a Console export.')
                    return 1
            errors = check_schema(schema.read_text(), required)
            for error in errors:
                print('error: CloudKit schema: ' + error)
            if not errors:
                print(f'CloudKit Production schema covers {len(required)} SwiftData models.')
            return int(bool(errors))
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print('error: CloudKit schema preflight could not complete: ' + type(error).__name__)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
