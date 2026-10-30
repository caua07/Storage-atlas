#!/usr/bin/env python3
"""Create small, explicitly synthetic filesystem data for native UX checks."""
from pathlib import Path
import os
import tempfile

root = Path(tempfile.mkdtemp(prefix="StorageAtlas-UX-Fixture-")).resolve()

def write(name, size, byte=b"x"):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        chunk = byte * min(size, 1024 * 1024)
        remaining = size
        while remaining:
            stream.write(chunk[:remaining])
            remaining -= min(remaining, len(chunk))
    return path

write("project/level-two/level-three/level-four/deep.bin", 24 * 1024 * 1024)
write("project/package.json", 128)
write("project/src/main.swift", 4096)
write("project/build/output.o", 2 * 1024 * 1024)
write("project/node_modules/example/index.js", 16384)
write("project/.git/objects/example.pack", 1024 * 1024)
model = write("project/models/example.gguf", 4 * 1024 * 1024)
os.link(model, root / "project/models/weights-hardlink.gguf")
write("project/assets/video.mp4", 2 * 1024 * 1024)
write("project/literal_%_.txt", 4096)
write("outside/archive.zip", 10 * 1024 * 1024)
write("Example.app/Contents/Resources/inside.gguf", 1024 * 1024)
for index in range(1250):
    write(f"many-files/empty-{index:04d}.txt", 0)
(root / "project/link-to-outside").symlink_to(root / "outside", target_is_directory=True)
write("no-access/private.dat", 4096)
(root / "no-access").chmod(0)
print(root)
