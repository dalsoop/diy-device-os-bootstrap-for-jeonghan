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
echo '{}' > "$catalog"

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
DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$output" --size 4294967296 --catalog "$catalog" >/dev/null

[ -f "$output" ]
[ -f "$output.sha256" ]
grep -q '^writer --device /dev/loop9 --catalog .* --image-build$' "$log"
grep -q '^blockdev --flushbufs /dev/loop9$' "$log"
grep -q '^losetup -d /dev/loop9$' "$log"

if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$output" --size 4294967296 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: existing output was overwritten" >&2
    exit 1
fi

if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    "$builder" --output "$temporary/small.raw" --size 1073741824 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: undersized image was accepted" >&2
    exit 1
fi

echo "image builder simulations: passed"
