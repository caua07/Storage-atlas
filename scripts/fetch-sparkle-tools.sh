#!/bin/zsh
set -eu
cd "${0:A:h:h}"
folder="$PWD/.build/sparkle-tools"
mkdir -p "$folder"
archive="$folder/Sparkle-2.10.1.tar.xz"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' --silent --show-error \
      https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$archive"
fi
python3 - "$archive" <<'PY'
import hashlib,sys
from pathlib import Path
expected='1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()!=expected:
    raise SystemExit('Sparkle tool archive checksum mismatch; refusing extraction.')
PY
if [[ ! -x "$folder/bin/sign_update" ]]; then tar -xJf "$archive" -C "$folder"; fi
