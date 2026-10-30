#!/usr/bin/env python3
"""Create explicitly synthetic files for UI verification; never use a personal folder."""
import json
import os
import tempfile
from pathlib import Path

root = Path(tempfile.mkdtemp(prefix="Atlas UI Fixture - "))
files = {
    "Projects/terrain-engine/Cargo.toml": 512,
    "Projects/terrain-engine/src/main.rs": 12_000,
    "Projects/terrain-engine/target/debug/terrain-engine": 8_000_000,
    "Projects/terrain-engine/target/debug/incremental/query-cache.bin": 5_000_000,
    "Projects/notes-web/package.json": 512,
    "Projects/notes-web/src/index.tsx": 15_000,
    "Projects/notes-web/node_modules/typescript/lib/typescript.js": 7_000_000,
    "Projects/notes-web/node_modules/react/index.js": 3_000_000,
    "Projects/notes-web/.git/objects/pack/local.pack": 2_000_000,
    "Downloads/toolchain-installer.dmg": 9_000_000,
    "Downloads/old-project.zip": 4_000_000,
    "Library/Caches/Homebrew/downloads/package.tar.gz": 6_000_000,
    "Library/Developer/Xcode/DerivedData/Notes/Build/Products/Notes": 4_000_000,
    "Applications/Example Editor.app/Contents/MacOS/ExampleEditor": 5_000_000,
    "Documents/Project proposal.pdf": 1_000_000,
    "Documents/README - SYNTHETIC TEST FIXTURE.txt": 100,
    "Models/small-local-model.gguf": 10_000_000,
}
chunk = bytes((i % 251 for i in range(65536)))
for relative, size in files.items():
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        remaining = size
        while remaining:
            n = min(remaining, len(chunk))
            handle.write(chunk[:n])
            remaining -= n
os.symlink(root / "Projects", root / "Projects link")
print(root)
