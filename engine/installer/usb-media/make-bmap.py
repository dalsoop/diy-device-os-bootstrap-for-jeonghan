#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
"""Write IMAGE.bmap.json for an exact-size raw MBR image.

The map lists the 1 MiB blocks a writer must copy: every block the image
builder allocated in the raw file (its SEEK_DATA extents, so zeros a builder
wrote inside a file stay mapped), the first MiB, the first --metadata-mib of
every partition and the whole of any partition no larger than that, so file
system structures are always written. Run it where the raw image was built,
before the image is compressed: decompression can turn written zeros into
holes. write-image-macos --mode mapped writes and verifies only these blocks
and refuses an image whose unmapped blocks are not all zero.
"""

import argparse
import json
import os
import sys

BLOCK = 1 << 20


def fail(message):
    print(f"make-bmap: {message}", file=sys.stderr)
    sys.exit(1)


def partitions(path):
    with open(path, "rb") as image:
        mbr = image.read(512)
    if len(mbr) != 512 or mbr[510:512] != b"\x55\xaa":
        fail("the image has no MBR signature")
    found = []
    for index in range(4):
        entry = mbr[446 + 16 * index: 462 + 16 * index]
        kind = entry[4]
        start = int.from_bytes(entry[8:12], "little")
        count = int.from_bytes(entry[12:16], "little")
        if kind == 0xEE:
            fail("GPT images are not supported")
        if kind and count:
            found.append((start * 512, count * 512))
    if not found:
        fail("the image has no MBR partition")
    return found


def allocated_blocks(fd, size):
    """Indices of 1 MiB blocks that hold allocated extents of the raw file."""
    blocks = set()
    offset = 0
    try:
        while offset < size:
            try:
                data = os.lseek(fd, offset, os.SEEK_DATA)
            except OSError:
                break  # ENXIO: no data after offset
            hole = os.lseek(fd, data, os.SEEK_HOLE)
            blocks.update(range(data // BLOCK, (min(hole, size) - 1) // BLOCK + 1))
            offset = hole
    except (AttributeError, OSError):
        # No hole reporting here: every block counts as written.
        return set(range((size + BLOCK - 1) // BLOCK))
    return blocks


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image")
    parser.add_argument("--metadata-mib", type=int, default=64)
    parser.add_argument("--output")
    args = parser.parse_args()
    if args.metadata_mib < 1:
        fail("--metadata-mib must be at least 1")

    size = os.path.getsize(args.image)
    if size < 2 * BLOCK:
        fail("the image is too small")
    total = (size + BLOCK - 1) // BLOCK
    metadata = args.metadata_mib * BLOCK

    fd = os.open(args.image, os.O_RDONLY)
    try:
        mapped = allocated_blocks(fd, size)
    finally:
        os.close(fd)
    mapped.add(0)
    for start, length in partitions(args.image):
        if start % BLOCK:
            fail("a partition does not start on a 1 MiB boundary")
        span = length if length <= metadata else metadata
        mapped.update(range(start // BLOCK, min(total, (start + span + BLOCK - 1) // BLOCK)))

    ranges = []
    for block in sorted(mapped):
        if ranges and ranges[-1][0] + ranges[-1][1] == block:
            ranges[-1][1] += 1
        else:
            ranges.append([block, 1])
    mapped_bytes = sum(min(size, (start + count) * BLOCK) - start * BLOCK for start, count in ranges)
    document = {
        "schema_version": 1,
        "block_size": BLOCK,
        "image_bytes": size,
        "metadata_mib": args.metadata_mib,
        "mapped_bytes": mapped_bytes,
        "ranges": ranges,
    }
    output = args.output or args.image + ".bmap.json"
    temporary = output + f".tmp.{os.getpid()}"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=1)
        handle.write("\n")
    os.replace(temporary, output)
    print(f"make-bmap: {len(ranges)} ranges, {mapped_bytes} of {size} bytes mapped -> {output}")


if __name__ == "__main__":
    main()
