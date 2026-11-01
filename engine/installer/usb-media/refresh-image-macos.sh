# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
# shellcheck shell=bash
#
# Sourced by write-image-macos --mode refresh. Brings a USB that this writer
# already made from the same composition up to a new raw image by copying only
# the files that differ, instead of rewriting every byte. It refuses unless the
# target's first MiB (MBR and Ventoy stage), partition map and Ventoy EFI
# partition equal the image's, and it passes only when the data partition and
# the enrollment partition hash equal to the image's file trees.

# Files macOS or Windows add to a mounted volume; never compared or copied.
refresh_ignored='^\./(\.fseventsd|\.Spotlight-V100|\.Trashes|\.TemporaryItems|\.DS_Store|\.metadata_never_index|System Volume Information)(/|$)|/\._'

# refresh_mbr_entry FILE INDEX prints "START_SECTOR SECTOR_COUNT TYPE" of MBR entry INDEX (1-4).
refresh_mbr_entry() {
    local offset=$((446 + ($2 - 1) * 16))
    local type start size
    type=$(od -An -tu1 -j $((offset + 4)) -N 1 "$1" | tr -d '[:space:]')
    start=$(od -An -tu4 -j $((offset + 8)) -N 4 "$1" | tr -d '[:space:]')
    size=$(od -An -tu4 -j $((offset + 12)) -N 4 "$1" | tr -d '[:space:]')
    printf '%s %s %s\n' "$start" "$size" "$type"
}

# refresh_region_sha256 FILE START_SECTOR SECTOR_COUNT hashes that region in 512-byte sectors.
refresh_region_sha256() {
    dd if="$1" bs=512 skip="$2" count="$3" 2>/dev/null | shasum -a 256 | awk 'NR == 1 { print $1 }'
}

# refresh_tree MOUNT prints "SHA256  ./relative/path" for every regular file
# outside the ignored metadata, sorted as whole lines for comm and cmp.
refresh_tree() {
    (
        cd "$1" || exit 1
        find . -type f | grep -Ev -e "$refresh_ignored" | while IFS= read -r file; do
            shasum -a 256 "$file"
        done | LC_ALL=C sort
    )
}

refresh_from_image() {
    local image=$1 device=$2
    local raw_device=/dev/r${device#/dev/}
    local work image_disk entry data efi enroll
    local image_prefix device_prefix

    image_prefix=$(dd if="$image" bs=1m count=1 2>/dev/null | shasum -a 256 | awk 'NR == 1 { print $1 }')
    device_prefix=$(dd if="$raw_device" bs=1m count=1 2>/dev/null | shasum -a 256 | awk 'NR == 1 { print $1 }')
    [ "$image_prefix" = "$device_prefix" ] ||
        fail "refresh refused: the target's first MiB (MBR and Ventoy stage) differs from the image; write it in full"
    for entry in 1 2 3 4; do
        [ "$(refresh_mbr_entry "$image" "$entry")" = "$(refresh_mbr_entry "$raw_device" "$entry")" ] ||
            fail "refresh refused: partition $entry differs from the image; write it in full"
    done
    read -r -a data <<<"$(refresh_mbr_entry "$image" 1)"
    read -r -a efi <<<"$(refresh_mbr_entry "$image" 2)"
    read -r -a enroll <<<"$(refresh_mbr_entry "$image" 3)"
    if [ "${data[0]}" -le 0 ] || [ "${efi[0]}" -le 0 ] || [ "${enroll[0]}" -le 0 ]; then
        fail "refresh refused: the image is not a Ventoy layout with an enrollment partition"
    fi
    [ "$(refresh_region_sha256 "$image" "${efi[0]}" "${efi[1]}")" = \
        "$(refresh_region_sha256 "$raw_device" "${efi[0]}" "${efi[1]}")" ] ||
        fail "refresh refused: the Ventoy EFI partition differs from the image; write it in full"

    work=$(mktemp -d /tmp/device-os-refresh.XXXXXX)
    image_disk=
    refresh_cleanup() {
        for mounted in "$work/image-data" "$work/image-enroll" "$work/usb-data" "$work/usb-enroll"; do
            if [ -d "$mounted" ]; then
                diskutil unmount force "$mounted" >/dev/null 2>&1 || true
            fi
        done
        [ -z "$image_disk" ] || hdiutil detach -force "$image_disk" >/dev/null 2>&1 || true
        image_disk=
        rm -rf "$work"
        cleanup
    }
    trap refresh_cleanup EXIT HUP INT TERM

    image_disk=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -readonly -nomount "$image" |
        awk 'NR == 1 { print $1 }')
    [[ "$image_disk" =~ ^/dev/disk[0-9]+$ ]] || fail "could not attach the raw image read-only"
    diskutil unmountDisk "$device" >/dev/null
    mkdir -p "$work/image-data" "$work/image-enroll" "$work/usb-data" "$work/usb-enroll"
    diskutil mount readOnly -mountPoint "$work/image-data" "${image_disk}s1" >/dev/null ||
        fail "could not mount the image's data partition"
    diskutil mount readOnly -mountPoint "$work/image-enroll" "${image_disk}s3" >/dev/null ||
        fail "could not mount the image's enrollment partition"
    diskutil mount -mountPoint "$work/usb-data" "${device}s1" >/dev/null ||
        fail "could not mount the target's data partition"
    diskutil mount -mountPoint "$work/usb-enroll" "${device}s3" >/dev/null ||
        fail "could not mount the target's enrollment partition"

    if [ -n "$(cd "$work/usb-enroll" && find ./records ./reinstall -type f 2>/dev/null | grep -Ev -e "$refresh_ignored")" ]; then
        fail "refresh refused: DNS-ENROLL already holds enrollment or reinstall records; keep this USB or write a new one in full"
    fi

    refresh_tree "$work/image-data" > "$work/image-data.sums"
    refresh_tree "$work/usb-data" > "$work/usb-data.sums"
    local changed=0 removed=0 path
    # Copy every file whose hash or presence differs, then delete files the image lacks.
    while IFS= read -r path; do
        mkdir -p "$(dirname -- "$work/usb-data/$path")"
        COPYFILE_DISABLE=1 cp -X "$work/image-data/$path" "$work/usb-data/$path.refresh-tmp"
        mv -f "$work/usb-data/$path.refresh-tmp" "$work/usb-data/$path"
        changed=$((changed + 1))
    done < <(LC_ALL=C comm -23 "$work/image-data.sums" "$work/usb-data.sums" | sed -E 's/^[0-9a-f]{64}  //')
    while IFS= read -r path; do
        [ -e "$work/image-data/$path" ] && continue
        rm -f "$work/usb-data/$path"
        removed=$((removed + 1))
    done < <(LC_ALL=C comm -13 "$work/image-data.sums" "$work/usb-data.sums" | sed -E 's/^[0-9a-f]{64}  //')
    echo "refresh: $changed data file(s) copied, $removed removed"

    for path in installer.json; do
        cmp -s "$work/image-enroll/$path" "$work/usb-enroll/$path" ||
            COPYFILE_DISABLE=1 cp -X "$work/image-enroll/$path" "$work/usb-enroll/$path"
    done
    mkdir -p "$work/usb-enroll/records" "$work/usb-enroll/reinstall"

    sync
    diskutil unmount "$work/usb-data" >/dev/null
    diskutil unmount "$work/usb-enroll" >/dev/null
    # Read back from a fresh read-only mount, not from the page cache of the write.
    diskutil mount readOnly -mountPoint "$work/usb-data" "${device}s1" >/dev/null ||
        fail "could not remount the target's data partition for readback"
    diskutil mount readOnly -mountPoint "$work/usb-enroll" "${device}s3" >/dev/null ||
        fail "could not remount the target's enrollment partition for readback"
    refresh_tree "$work/usb-data" > "$work/usb-data.after"
    cmp -s "$work/image-data.sums" "$work/usb-data.after" ||
        fail "readback: the data partition does not match the image after the refresh"
    refresh_tree "$work/image-enroll" > "$work/image-enroll.sums"
    refresh_tree "$work/usb-enroll" > "$work/usb-enroll.after"
    cmp -s "$work/image-enroll.sums" "$work/usb-enroll.after" ||
        fail "readback: the enrollment partition does not match the image after the refresh"

    refresh_cleanup
    # Hand the writer's own cleanup back its traps.
    trap cleanup EXIT HUP INT TERM
    diskutil unmountDisk "$device" >/dev/null
    diskutil eject "$device" >/dev/null
}
