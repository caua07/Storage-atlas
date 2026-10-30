#!/usr/bin/env python3
"""Certificate-backed signing with a locally pinned designated requirement."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / '.signing'
BUNDLE_ID = 'local.storageatlas.mac'


def run(args, check=True):
    result = subprocess.run(args, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Command failed')
    return result


def identities(include_untrusted=False):
    result = run(['security', 'find-identity'] + ([] if include_untrusted else ['-v']) + ['-p', 'codesigning'])
    return dict(re.findall(r'\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"', result.stdout))


def load_profile(mode):
    if mode == 'ci':
        if os.environ.get('CI') != 'true':
            raise RuntimeError('Ad-hoc signing is restricted to explicit CI=true builds, not local installed apps.')
        return None
    path = CONFIG / (mode + '.json')
    if not path.exists():
        raise RuntimeError('Configure a certificate first: python3 scripts/app-signing.py configure ' + mode + ' CERTIFICATE_SHA1. No ad-hoc fallback is allowed.')
    profile = json.loads(path.read_text())
    fingerprint = profile['identity']
    name = identities(include_untrusted=mode == 'community').get(fingerprint)
    if mode == 'community':
        if name != 'Storage Atlas Community Releases':
            raise RuntimeError('The persistent community signing identity is unavailable. No fallback is allowed.')
        return profile
    prefix = 'Apple Development:' if mode == 'development' else 'Developer ID Application:'
    if not name or not name.startswith(prefix):
        raise RuntimeError('The pinned ' + mode + ' signing identity is unavailable or has the wrong certificate type. No fallback is allowed.')
    return profile


def requirement(bundle):
    result = run(['codesign', '-d', '-r-', str(bundle)])
    text = result.stdout + result.stderr
    match = re.search(r'^(?:# )?designated => (.+)$', text, re.M)
    if not match:
        raise RuntimeError('Missing designated requirement.')
    return match.group(1)


def verify_requirement(bundle, expression):
    run(['codesign', '--verify', '-R=' + expression, str(bundle)])


def sign(bundle, mode):
    profile = load_profile(mode)
    # Sign nested code from the inside out; never use --deep to create signatures.
    nested = bundle / 'Contents/Frameworks'
    signer = '-' if mode == 'ci' else profile['identity']
    if nested.exists():
        magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
        for item in sorted(nested.rglob('*'), key=lambda p: len(p.parts), reverse=True):
            if item.is_symlink(): continue
            if item.is_file():
                with item.open('rb') as file: is_code = file.read(4) in magic
            else: is_code = item.suffix in ['.framework', '.app', '.xpc']
            if is_code:
                flags = ['--options', 'runtime', '--timestamp'] if mode == 'distribution' else ['--timestamp=none']
                run(['codesign', '--force', '--sign', signer] + flags + [str(item)])
    if mode == 'ci':
        run(['codesign', '--force', '--sign', '-', '--identifier', BUNDLE_ID, str(bundle)])
        return
    args = ['codesign', '--force', '--sign', profile['identity'], '--identifier', BUNDLE_ID]
    if mode == 'distribution':
        args += ['--options', 'runtime', '--timestamp']
    else:
        args += ['--timestamp=none']
    if mode == 'community':
        args += ['--requirements', '=designated => identifier \"' + BUNDLE_ID + '\" and anchor H\"' + profile['identity'] + '\"']
    args += [str(bundle)]
    run(args)
    run(['codesign', '--verify', '--deep', '--strict', str(bundle)])
    details = run(['codesign', '-dv', '--verbose=4', str(bundle)]).stderr
    expression = requirement(bundle)
    if mode == 'community':
        expected = 'identifier "' + BUNDLE_ID + '" and anchor H"' + profile['identity'] + '"'
        verify_requirement(bundle, expected)
        team_id = 'community:' + profile['identity']
    else:
        authority = 'Apple Development:' if mode == 'development' else 'Developer ID Application:'
        if 'Authority=' + authority not in details or 'Signature=adhoc' in details:
            raise RuntimeError('Unexpected signing authority.')
        team = re.search(r'^TeamIdentifier=(.+)$', details, re.M)
        if not team or team.group(1) == 'not set':
            raise RuntimeError('A certificate-backed team identity is required.')
        team_id = team.group(1)
        if 'cdhash' in expression or 'anchor apple generic' not in expression or 'certificate' not in expression:
            raise RuntimeError('Refusing an unstable or insufficiently constrained designated requirement.')
        verify_requirement(bundle, 'anchor apple generic and identifier "' + BUNDLE_ID + '"')
    previous = profile.get('requirement')
    if previous:
        verify_requirement(bundle, previous)
        if profile.get('team') != team_id:
            raise RuntimeError('Signing team changed.')
    else:
        profile.update(requirement=expression, team=team_id)
        write_profile(mode, profile)
    print(mode.capitalize() + ' signing verified; stable certificate-backed identity.')


def write_profile(mode, profile):
    CONFIG.mkdir(mode=0o700, exist_ok=True)
    target = CONFIG / (mode + '.json')
    temp = target.with_suffix('.tmp')
    temp.write_text(json.dumps(profile, indent=2) + '\n')
    temp.chmod(0o600)
    temp.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    setup = sub.add_parser('configure')
    setup.add_argument('mode', choices=['development', 'distribution'])
    setup.add_argument('identity')
    for command in ['preflight', 'sign', 'compatible']:
        child = sub.add_parser(command)
        child.add_argument('mode', choices=['development', 'community', 'distribution', 'ci'])
        if command != 'preflight': child.add_argument('bundle', type=Path)
        if command == 'compatible': child.add_argument('installed', type=Path)
    args = parser.parse_args()
    if args.command == 'configure':
        fingerprint = args.identity.upper()
        name = identities().get(fingerprint, '')
        prefix = 'Apple Development:' if args.mode == 'development' else 'Developer ID Application:'
        if not name.startswith(prefix):
            raise RuntimeError('No valid certificate of the required type matches that fingerprint.')
        existing = CONFIG / (args.mode + '.json')
        profile = json.loads(existing.read_text()) if existing.exists() else {}
        # Keep the original requirement when rotating a certificate. A replacement
        # must satisfy the established identity instead of silently resetting it.
        profile['identity'] = fingerprint
        write_profile(args.mode, profile)
        print('Pinned ' + args.mode + ' certificate. Private keys stay in Keychain.')
    elif args.command == 'preflight':
        load_profile(args.mode)
    elif args.command == 'sign':
        sign(args.bundle, args.mode)
    elif args.command == 'compatible':
        if not args.installed.exists(): return
        run(['codesign', '--verify', '--deep', '--strict', str(args.installed)])
        old = requirement(args.installed)
        check = run(['codesign', '--verify', '-R=' + old, str(args.bundle)], check=False)
        if check.returncode:
            if (args.mode != 'development' or 'cdhash' not in old
                    or os.environ.get('ATLAS_ALLOW_SIGNING_MIGRATION') != '1'):
                raise RuntimeError('Replacement does not satisfy the installed app identity. Refusing installation. A deliberate first migration requires ATLAS_ALLOW_SIGNING_MIGRATION=1 and one new Full Disk Access authorization.')
            print('Explicit one-time signing migration: macOS permission must be authorized for the new identity.')
        if args.mode == 'ci':
            raise RuntimeError('CI builds cannot replace an installed app bundle.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, KeyError, ValueError) as error:
        print('Signing error: ' + str(error), file=sys.stderr)
        sys.exit(1)
