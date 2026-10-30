#!/usr/bin/env python3
"""Verify that distinct app versions share a certificate-backed signing identity."""
import argparse
import importlib.util
import plistlib
import re

from pathlib import Path

spec = importlib.util.spec_from_file_location('atlas_signing', Path(__file__).with_name('app-signing.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('first', type=Path)
parser.add_argument('second', type=Path)
args = parser.parse_args()
metadata = []
for bundle in [args.first, args.second]:
    signing.run(['codesign', '--verify', '--deep', '--strict', str(bundle)])
    details = signing.run(['codesign', '-dv', '--verbose=4', str(bundle)]).stderr
    if 'Signature=adhoc' in details:
        raise SystemExit('Ad-hoc identity cannot establish continuity.')
    with (bundle / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    metadata.append((info['CFBundleIdentifier'], info['CFBundleVersion'],
                     re.search(r'^CDHash=(.+)$', details, re.M).group(1),
                     re.search(r'^TeamIdentifier=(.+)$', details, re.M).group(1)))
if metadata[0][0] != metadata[1][0] or metadata[0][3] != metadata[1][3]:
    raise SystemExit('Bundle identifier or signing team differs.')
if metadata[0][1] == metadata[1][1] or metadata[0][2] == metadata[1][2]:
    raise SystemExit('Use distinct builds with different build numbers and code hashes.')
for first, second in [(args.first, args.second), (args.second, args.first)]:
    requirement = signing.requirement(first)
    if 'cdhash' in requirement or 'anchor apple generic' not in requirement:
        raise SystemExit('Unstable or insufficiently constrained identity.')
    signing.verify_requirement(second, requirement)
print('PASS: different app builds satisfy each other’s certificate-backed designated requirements.')
print('This proves signing continuity; actual macOS permission continuity also requires an authorized runtime test.')
