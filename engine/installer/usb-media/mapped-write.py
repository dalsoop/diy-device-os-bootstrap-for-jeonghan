#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
"""Write only the mapped blocks of a raw image to a device and verify them.

Called by write-image-macos --mode mapped after its image, manifest, license
and target checks. Before touching the device it proves that every block the
map leaves out is all zero in the image, so the map can only skip empty space.
It hides the partition map (zeroes the first MiB), writes the mapped body
blocks, reads them back and compares SHA-256 digests, and writes and verifies
the first MiB last, like the full writer. Blocks outside the map keep whatever
the device held; file systems treat them as free space.
"""

import argparse
import hashlib
import json
import mmap
import os
import sys

BLOCK = 1 << 20


def fail(message):
    print(f"mapped-write: {message}", file=sys.stderr)
    sys.exit(1)


def load_map(path, image_bytes):
    try:
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"cannot read the block map: {error}")
    if not isinstance(document, dict) or document.get("schema_version") != 1 or \
            document.get("block_size") != BLOCK or document.get("image_bytes") != image_bytes:
        fail("the block map does not describe this image")
    ranges = document.get("ranges")
    total = (image_bytes + BLOCK - 1) // BLOCK
    if not isinstance(ranges, list) or not ranges:
        fail("the block map has no ranges")
    previous_end = -1
    blocks = []
    for item in ranges:
        if not (isinstance(item, list) and len(item) == 2 and all(isinstance(v, int) for v in item)):
            fail("the block map has a malformed range")
        start, count = item
        if start <= previous_end or count < 1 or start + count > total:
            fail("the block map's ranges are unsorted, overlapping or outside the image")
        previous_end = start + count - 1
        blocks.extend(range(start, start + count))
    if blocks[0] != 0:
        fail("the block map omits the first MiB")
    return blocks, total


def length_of(block, image_bytes):
    return min(BLOCK, image_bytes - block * BLOCK)


def read_into(fd, buffer, block, image_bytes):
    length = length_of(block, image_bytes)
    view = memoryview(buffer)[:length]
    done = 0
    while done < length:
        count = os.preadv(fd, [view[done:]], block * BLOCK + done)
        if count <= 0:
            fail(f"short read at block {block}")
        done += count
    return view


def write_from(fd, view, block):
    done = 0
    while done < len(view):
        count = os.pwrite(fd, view[done:], block * BLOCK + done)
        if count <= 0:
            fail(f"short write at block {block}")
        done += count


def digest(fd, blocks, buffer, image_bytes):
    hasher = hashlib.sha256()
    for block in blocks:
        hasher.update(read_into(fd, buffer, block, image_bytes))
    return hasher.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--image", required=True)
    parser.add_argument("--bmap", required=True)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()

    image_bytes = os.path.getsize(args.image)
    blocks, total = load_map(args.bmap, image_bytes)
    mapped = set(blocks)
    buffer = mmap.mmap(-1, BLOCK)  # page aligned, as raw devices may require
    image = os.open(args.image, os.O_RDONLY)

    # Every unmapped block must be zero: skip holes, read what is allocated.
    zero = bytes(BLOCK)
    offset = 0
    while offset < image_bytes:
        try:
            data = os.lseek(image, offset, os.SEEK_DATA)
        except OSError:
            break
        except AttributeError:
            data = offset
        hole = image_bytes
        try:
            hole = os.lseek(image, data, os.SEEK_HOLE)
        except (AttributeError, OSError):
            pass
        for block in range(data // BLOCK, (min(hole, image_bytes) - 1) // BLOCK + 1):
            if block in mapped:
                continue
            view = read_into(image, buffer, block, image_bytes)
            if view != zero[:len(view)]:
                fail(f"block {block} holds data but the block map leaves it out; regenerate the map")
        offset = hole

    body = [block for block in blocks if block != 0]
    image_body = digest(image, body, buffer, image_bytes)
    image_prefix = digest(image, [0], buffer, image_bytes)

    device = os.open(args.device, os.O_RDWR)
    try:
        # Hide the partition map while the body is written and verified.
        buffer.seek(0)
        buffer.write(zero)
        write_from(device, memoryview(buffer)[:length_of(0, image_bytes)], 0)
        os.fsync(device)
        for block in body:
            write_from(device, read_into(image, buffer, block, image_bytes), block)
        os.fsync(device)
        if digest(device, body, buffer, image_bytes) != image_body:
            fail(f"readback of the {len(body)} mapped body blocks does not match")
        write_from(device, read_into(image, buffer, 0, image_bytes), 0)
        os.fsync(device)
        if digest(device, [0], buffer, image_bytes) != image_prefix:
            fail("readback of the first MiB does not match")
    finally:
        os.close(device)
        os.close(image)
    written = sum(length_of(block, image_bytes) for block in blocks)
    print(f"mapped-write: wrote and verified {len(blocks)} of {total} blocks ({written} bytes)")


if __name__ == "__main__":
    main()
