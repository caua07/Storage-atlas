#!/usr/bin/env python3
"""Build, sign and publish a community release; publish the signed feed last."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
REPO = 'caua07/Storage-atlas'
TOOLS = ROOT / '.build/sparkle-tools/bin'


def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='Publish release assets, then commit/push the signed update feed')
    args = parser.parse_args()
    info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not build.isdecimal() or any(c not in '0123456789.' for c in version):
        raise SystemExit('Use numeric release versions and an increasing numeric build.')
    tag = 'v' + version
    if args.publish:
        dirty = subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT,text=True)
        if dirty: raise SystemExit('Commit source changes before publishing a release.')
        run(['gh','repo','view',REPO,'--json','nameWithOwner'],stdout=subprocess.DEVNULL)
    run(['./scripts/fetch-sparkle-tools.sh'])
    out = ROOT/'dist/releases'/tag
    if out.exists(): raise SystemExit('Release output already exists; do not overwrite signed release bytes.')
    out.mkdir(parents=True)
    app = out/'Storage Atlas.app'
    run(['./scripts/build-app.sh','release',str(app)],env=dict(os.environ,ATLAS_SIGNING_MODE='community'))
    run(['codesign','--verify','--deep','--strict',str(app)])
    if subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/StorageAtlas')],text=True).strip()!='arm64':
        raise SystemExit('This release channel is Apple Silicon only.')
    archive = out/'StorageAtlas-macOS-arm64.zip'
    run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)])
    stage = out/'dmg-contents';stage.mkdir()
    shutil.copytree(app,stage/'Storage Atlas.app',symlinks=True)
    (stage/'Applications').symlink_to('/Applications',target_is_directory=True)
    (stage/'Read me first.txt').write_text('Storage Atlas — macOS 14+, Apple Silicon\n\nDrag Storage Atlas into Applications, then open it there.\nCommunity builds are not Apple-notarized. macOS may require first-launch approval in System Settings > Privacy & Security > Open Anyway. Only approve an app from a source you trust.\nAtlas guides you through Full Disk Access for protected folders.\nNo account or subscription is required.\n\nSource, license and releases: https://github.com/caua07/Storage-atlas\n')
    dmg = out/'StorageAtlas-macOS-arm64.dmg'
    run(['hdiutil','create','-volname','Storage Atlas','-srcfolder',str(stage),'-format','UDZO',str(dmg)])
    checksums = out/'SHA256SUMS.txt'
    checksums.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [dmg,archive]))
    feed_stage = out/'feed-source';feed_stage.mkdir();shutil.copy2(archive,feed_stage/archive.name)
    run([str(TOOLS/'generate_appcast'),'--account','storage-atlas','--download-url-prefix',f'https://github.com/{REPO}/releases/download/{tag}/','--maximum-deltas','0',str(feed_stage)])
    feed = feed_stage/'appcast.xml'
    run([str(TOOLS/'sign_update'),'--account','storage-atlas','--verify',str(feed)])
    assets = [dmg,archive,checksums]
    notes = out/'release-notes.md'
    notes.write_text(f'Storage Atlas {version} (build {build})\n\n- macOS 14+, Apple Silicon. Drag the app into Applications.\n- MIT open source. No account, telemetry or subscription.\n- In-app signed updates preserve your local index and preferences and wait for active scans.\n- Community signed; not Apple-notarized. macOS may require first-launch approval.\n\nSource and verification: https://github.com/{REPO}\n')
    print('Signed release packaged:',out)
    if not args.publish: return
    commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    run(['gh','release','create',tag,'--repo',REPO,'--target',commit,'--draft','--title','Storage Atlas '+version,'--notes-file',str(notes)]+[str(p) for p in assets])
    run(['gh','release','edit',tag,'--repo',REPO,'--draft=false'])
    for asset in assets:
        run(['curl','--fail','--location','--silent','--show-error','--head',f'https://github.com/{REPO}/releases/download/{tag}/{asset.name}'],stdout=subprocess.DEVNULL)
    # Only announce bytes which have already become publicly downloadable.
    shutil.copy2(feed,ROOT/'updates/appcast.xml')
    run(['git','add','updates/appcast.xml'])
    run(['git','commit','-m','Publish signed update feed for '+tag])
    run(['git','push','origin','main'])
    print('Release and signed update feed published:',tag)


if __name__=='__main__':
    try: main()
    except subprocess.CalledProcessError as error:
        print('Release stopped. Existing signed feed remains authoritative; inspect the failed step before retrying.',file=sys.stderr)
        sys.exit(error.returncode)
