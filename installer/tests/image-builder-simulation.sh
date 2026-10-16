#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
builder=$repo_root/usb-media/build-image-linux
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mock_bin=$temporary/bin
log=$temporary/commands.log
catalog=$temporary/catalog.json
output=$temporary/device-os.raw
mkdir -p "$mock_bin"
cat > "$catalog" <<EOF
{
  "catalog": {
    "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "tree": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
}
EOF

make_mock() {
    name=$1
    shift
    printf '%s\n' '#!/bin/sh' "$@" > "$mock_bin/$name"
    chmod +x "$mock_bin/$name"
}

make_mock uname 'echo Linux'
make_mock id 'echo 0'
# shellcheck disable=SC2016
make_mock losetup '
if [ "$1" = --find ]; then
  echo /dev/loop9
else
  printf "losetup %s\n" "$*" >> "$TEST_LOG"
fi'
make_mock lsblk 'echo loop'
# shellcheck disable=SC2016
make_mock blockdev '
case "$1" in
  --getsize64) echo 4294967296 ;;
  --flushbufs) printf "blockdev %s\n" "$*" >> "$TEST_LOG" ;;
  *) exit 1 ;;
esac'
make_mock stat 'echo 4294967296'
# shellcheck disable=SC2016
make_mock sha256sum 'printf "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  %s\n" "$1"'

writer=$temporary/writer
cat > "$writer" <<'EOF'
#!/bin/sh
[ "${DEVICE_OS_INTERNAL_IMAGE_BUILD:-0}" = 1 ]
printf 'writer %s\n' "$*" >> "$TEST_LOG"
EOF
chmod +x "$writer"

PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$output" --size 4294967296 --catalog "$catalog" >/dev/null

[ -f "$output" ]
[ -f "$output.sha256" ]
[ -f "$output.manifest.json" ]
grep -q '  device-os.raw$' "$output.sha256"
jq -e '
  .schema_version == 1 and
  .kind == "device-os-raw-image" and
  .image.filename == "device-os.raw" and
  .image.bytes == 4294967296 and
  .image.sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.revision == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.tree == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" and
  .world == null
' "$output.manifest.json" >/dev/null
grep -q '^writer --device /dev/loop9 --catalog .* --image-build$' "$log"
grep -q '^blockdev --flushbufs /dev/loop9$' "$log"
grep -q '^losetup -d /dev/loop9$' "$log"

if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$output" --size 4294967296 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: existing output was overwritten" >&2
    exit 1
fi

sidecar_only=$temporary/sidecar-only.raw
: > "$sidecar_only.sha256"
if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$sidecar_only" --size 4294967296 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: existing checksum was overwritten" >&2
    exit 1
fi
[ ! -e "$sidecar_only" ]

manifest_only=$temporary/manifest-only.raw
: > "$manifest_only.manifest.json"
if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$manifest_only" --size 4294967296 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: existing image manifest was overwritten" >&2
    exit 1
fi
[ ! -e "$manifest_only" ]

if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$temporary/small.raw" --size 1073741824 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: undersized image was accepted" >&2
    exit 1
fi

echo "image builder simulations: passed"
