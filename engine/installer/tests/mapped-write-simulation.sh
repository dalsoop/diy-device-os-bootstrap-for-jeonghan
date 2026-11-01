#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# The block map and the mapped writer against regular files: only mapped blocks
# reach the "device", they read back equal to the image, unmapped blocks keep
# their old bytes, and an image whose unmapped blocks are not zero is refused
# before the device is touched.

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
make_bmap=$repo_root/usb-media/make-bmap.py
mapped_write=$repo_root/usb-media/mapped-write.py
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

fail() {
    echo "mapped-write-simulation: $*" >&2
    exit 1
}

# A 40 MiB sparse image: MBR with a data partition at 1 MiB (30 MiB) and a
# small partition at 32 MiB (4 MiB); data at blocks 10 and 25, written zeros at
# block 12, everything else a hole.
python3 - "$temporary/image.raw" <<'PY'
import os, sys
path = sys.argv[1]
MIB = 1 << 20
with open(path, "wb") as image:
    image.truncate(40 * MIB)
    mbr = bytearray(512)
    for index, (kind, start, count) in enumerate([(0x07, 2048, 30 * 2048), (0xEF, 32 * 2048, 4 * 2048)]):
        entry = 446 + 16 * index
        mbr[entry + 4] = kind
        mbr[entry + 8:entry + 12] = start.to_bytes(4, "little")
        mbr[entry + 12:entry + 16] = count.to_bytes(4, "little")
    mbr[510:512] = b"\x55\xaa"
    image.seek(0); image.write(bytes(mbr))
    image.seek(10 * MIB); image.write(b"\x11" * MIB)
    image.seek(25 * MIB + 4096); image.write(b"\x22" * 4096)
    image.seek(12 * MIB); image.write(bytes(MIB))
PY
python3 "$make_bmap" "$temporary/image.raw" --metadata-mib 1 > "$temporary/make.log" ||
    fail "make-bmap failed: $(cat "$temporary/make.log")"
# Some file systems (APFS for small files) report no holes; then every block
# is mapped, which is the safe fallback, and only the mapped checks apply.
holes=$(python3 - "$temporary/image.raw" <<'PY'
import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
try:
    print("yes" if os.lseek(fd, 0, os.SEEK_HOLE) < os.path.getsize(sys.argv[1]) else "no")
except (AttributeError, OSError):
    print("no")
PY
)
python3 - "$temporary/image.raw.bmap.json" "$holes" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
blocks = {block for start, count in document["ranges"] for block in range(start, start + count)}
for required in (0, 1, 10, 25, 32):
    assert required in blocks, f"block {required} is not mapped: {sorted(blocks)}"
if sys.argv[2] == "yes":
    for skipped in (2, 5, 20, 30, 33, 38, 39):
        assert skipped not in blocks, f"block {skipped} is mapped: {sorted(blocks)}"
else:
    assert blocks == set(range(40)), "without hole reporting every block must be mapped"
assert document["image_bytes"] == 40 << 20
PY

# The device starts full of old bytes.
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\xaa" * (40 << 20))' "$temporary/device"
python3 "$mapped_write" --image "$temporary/image.raw" --bmap "$temporary/image.raw.bmap.json" \
    --device "$temporary/device" > "$temporary/write.log" 2>&1 ||
    fail "the mapped write failed: $(cat "$temporary/write.log")"
python3 - "$temporary/image.raw" "$temporary/image.raw.bmap.json" "$temporary/device" <<'PY'
import json, sys
MIB = 1 << 20
image = open(sys.argv[1], "rb").read()
document = json.load(open(sys.argv[2]))
device = open(sys.argv[3], "rb").read()
blocks = {block for start, count in document["ranges"] for block in range(start, start + count)}
for block in range(40):
    span = slice(block * MIB, (block + 1) * MIB)
    if block in blocks:
        assert device[span] == image[span], f"mapped block {block} differs"
    else:
        assert device[span] == b"\xaa" * MIB, f"unmapped block {block} was written"
PY
echo "PASS mapped_write_writes_and_verifies_only_mapped_blocks"

if [ "$holes" != yes ]; then
    echo "SKIP the refusal cases need hole reporting, which this file system lacks"
    echo "mapped-write simulations: passed"
    exit 0
fi

# Data the map leaves out is refused before the device changes.
python3 -c 'import sys; f = open(sys.argv[1], "r+b"); f.seek(20 << 20); f.write(b"\x33")' "$temporary/image.raw"
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\xaa" * (40 << 20))' "$temporary/device"
if python3 "$mapped_write" --image "$temporary/image.raw" --bmap "$temporary/image.raw.bmap.json" \
    --device "$temporary/device" > "$temporary/refuse.log" 2>&1; then
    fail "an image with data outside the map was written"
fi
grep -q 'block 20 holds data but the block map leaves it out' "$temporary/refuse.log" ||
    fail "the refusal did not name the unmapped data: $(cat "$temporary/refuse.log")"
python3 -c 'import sys; assert open(sys.argv[1], "rb").read() == b"\xaa" * (40 << 20)' "$temporary/device" ||
    fail "a refused write changed the device"
echo "PASS mapped_write_refuses_data_outside_the_map_before_writing"

# A map made for another image is refused.
python3 -c 'import sys; open(sys.argv[1], "ab").write(bytes(1 << 20))' "$temporary/image.raw"
if python3 "$mapped_write" --image "$temporary/image.raw" --bmap "$temporary/image.raw.bmap.json" \
    --device "$temporary/device" > /dev/null 2>&1; then
    fail "a map for a different image size was accepted"
fi
echo "PASS mapped_write_refuses_a_map_for_another_image"
echo "mapped-write simulations: passed"
