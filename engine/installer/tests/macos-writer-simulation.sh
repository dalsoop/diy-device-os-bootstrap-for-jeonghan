#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
writer=$repo_root/usb-media/write-image-macos
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mock_bin=$temporary/bin
log=$temporary/commands.log
image=$temporary/device-os.raw
catalog=$temporary/catalog.json
jq_bin=$(command -v jq)
jq_dir=$(dirname -- "$jq_bin")
test_path=$mock_bin:$jq_dir:/usr/bin:/bin
mkdir -p "$mock_bin"
truncate -s 2097152 "$image"
cat > "$catalog" <<EOF
{
  "schema_version": 2,
  "distribution_policy": {
    "schema_version": 1,
    "source_release": {"enabled": true},
    "generated_artifacts": {"enabled": false},
    "prebuilt_release": {"enabled": false, "required_github_environment": "prebuilt-distribution"}
  },
  "bootloader": {"id": "ventoy", "redistribution": {"status": "personal-use-only"}},
  "entries": [{"id": "debian-live", "source": {"kind": "locked-download", "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}, "redistribution": {"status": "personal-use-only"}}],
  "catalog": {
    "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "tree": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  },
  "world": {
    "world": {"slug": "test-home"},
    "media": {"id": "inventory-capture"},
    "overlays": ["tailscale", "netbird"]
  }
}
EOF
# The resolved Catalog is hashed for real so that its digest binds the World
# plan it embeds; the image and the policy keep fixed mock digests.
real_hash=$temporary/real-hash
# shellcheck disable=SC2016
if command -v sha256sum >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec %s "$1"\n' "$(command -v sha256sum)" > "$real_hash"
else
    printf '#!/bin/sh\nexec %s -a 256 "$1"\n' "$(command -v shasum)" > "$real_hash"
fi
chmod +x "$real_hash"
catalog_digest=$("$real_hash" "$catalog")
catalog_digest=${catalog_digest%% *}
export TEST_CATALOG=$catalog TEST_REAL_HASH=$real_hash
cat > "$image.manifest.json" <<EOF
{
  "schema_version": 2,
  "kind": "device-os-raw-image",
  "image": {
    "filename": "device-os.raw",
    "bytes": 2097152,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "catalog": {
    "sha256": "$catalog_digest",
    "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "tree": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  },
  "license": {
    "mode": "personal-use",
    "decision": "allow",
    "distribution_policy_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "selected_artifacts": [
      {"id":"ventoy","kind":"bootloader","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","status":"personal-use-only"},
      {"id":"debian-live","kind":"catalog-entry","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","status":"personal-use-only"}
    ]
  },
  "world": {"slug": "test-home", "media_id": "inventory-capture"}
}
EOF

checker=$temporary/checker
cat > "$checker" <<'EOF'
#!/bin/sh
if [ "${TEST_POLICY_DENY:-0}" = 1 ]; then
  exit 1
fi
cat <<'JSON'
{"schema_version":1,"mode":"personal-use","decision":"allow","selected_artifacts":[{"id":"ventoy","kind":"bootloader","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","status":"personal-use-only"},{"id":"debian-live","kind":"catalog-entry","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","status":"personal-use-only"}],"blockers":[],"warnings":[]}
JSON
EOF
chmod +x "$checker"

make_mock() {
    name=$1
    shift
    printf '%s\n' '#!/bin/sh' "$@" > "$mock_bin/$name"
    chmod +x "$mock_bin/$name"
}

make_mock uname 'echo Darwin'
make_mock id 'echo 0'
make_mock stat 'echo 2097152'
# A file argument hashes that file; stdin is a mock dd read whose arguments name
# the region. TEST_FAIL_BODY_COMPARE corrupts the device body readback.
# shellcheck disable=SC2016
make_mock shasum '
if [ "$#" -ge 3 ] && [ "$3" = "$TEST_CATALOG" ]; then
  exec "$TEST_REAL_HASH" "$3"
fi
if [ "$#" -ge 3 ]; then
  echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  $3"
  exit 0
fi
read_args=$(cat)
case "$read_args" in
  *"if=/dev/rdisk9 bs=1m count=1"*)
    if [ "${TEST_FAIL_PREFIX:-0}" = 1 ]; then
      echo "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd  -"
      exit 0
    fi ;;
  *"if=/dev/rdisk9 bs=1m skip=1"*)
    if [ "${TEST_FAIL_BODY_COMPARE:-0}" = 1 ]; then
      echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  -"
      exit 0
    fi ;;
esac
echo "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  -"'
# shellcheck disable=SC2016
make_mock plutil '
case "$2" in
  WholeDisk) echo true ;;
  Internal) echo false ;;
  Removable) echo true ;;
  WritableMedia) echo true ;;
  VirtualOrPhysical) echo Physical ;;
  MediaName) echo "Test USB" ;;
  TotalSize) echo 2097152 ;;
  DeviceTreePath) echo "IODeviceTree:/test/usb@00100000" ;;
  *) exit 1 ;;
esac'
make_mock ioreg '
cat <<EOF
+-o IOUSBMassStorageInterfaceNub
  "kUSBSerialNumberString" = "TEST-SERIAL-9"
  "BSD Name" = "disk9"
EOF'
# shellcheck disable=SC2016
make_mock od '
case " $* " in
  *" -j 450 "*) echo " ${TEST_MBR_TYPE:-7}" ;;
  *" -j 510 "*) echo " 55 aa" ;;
  *) exit 1 ;;
esac'
# shellcheck disable=SC2016
make_mock diskutil '
printf "diskutil %s\n" "$*" >> "$TEST_LOG"
case "$1" in
  info) echo plist ;;
  unmountDisk|eject) : ;;
  *) exit 1 ;;
esac'
# shellcheck disable=SC2016
make_mock dd '
printf "dd %s\n" "$*" >> "$TEST_LOG"
case " $* " in *" of="*) ;; *) printf "%s\n" "$*" ;; esac'
# shellcheck disable=SC2016
make_mock sync '
echo sync >> "$TEST_LOG"'
# shellcheck disable=SC2016
make_mock cmp '
printf "cmp %s\n" "$*" >> "$TEST_LOG"'

run_writer() {
    PATH="$test_path" TEST_LOG="$log" \
    USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    DEVICE_OS_WRITE_EVIDENCE="$temporary/evidence.json" "$writer" \
        --image "$image" \
        --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152'
}

run_writer >/dev/null
"$jq_bin" -e '
  .schema_version == 1 and
  .writer == "macos-mbr-last" and
  .device_path == "/dev/disk9" and
  .target.display_name == "Test USB" and
  .target.bytes == 2097152 and
  .readback == {method:"mbr-last-raw-compare",status:"passed"} and
  (.completed_at | type == "string") and
  (has("serial") | not)
' "$temporary/evidence.json" >/dev/null
cat > "$temporary/expected.log" <<EOF
diskutil info -plist /dev/disk9
dd if=$image bs=1m skip=1
dd if=$image bs=1m count=1
diskutil unmountDisk /dev/disk9
dd if=/dev/zero of=/dev/rdisk9 bs=1m count=1 conv=notrunc
sync
dd if=$image of=/dev/rdisk9 bs=1m skip=1 seek=1 conv=notrunc
sync
dd if=/dev/rdisk9 bs=1m skip=1
dd if=$image of=/dev/rdisk9 bs=1m count=1 conv=notrunc
sync
dd if=/dev/rdisk9 bs=1m count=1
diskutil unmountDisk /dev/disk9
diskutil eject /dev/disk9
EOF
diff -u "$temporary/expected.log" "$log"

: > "$log"
if PATH="$test_path" TEST_LOG="$log" TEST_POLICY_DENY=1 \
    USB_MEDIA_CATALOG="$catalog" DEVICE_OS_LICENSE_CHECKER="$checker" \
    "$writer" --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: denied license policy was accepted" >&2
    exit 1
fi
if [ -s "$log" ]; then
    echo "macos-writer-simulation: policy refusal reached target inspection or write commands" >&2
    exit 1
fi

: > "$log"
cp "$image.manifest.json" "$temporary/valid-image-manifest.json"
"$jq_bin" '.world.media_id = "dns-install"' \
    "$temporary/valid-image-manifest.json" > "$image.manifest.json"
if PATH="$test_path" TEST_LOG="$log" USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    DEVICE_OS_WRITE_EVIDENCE="$temporary/mismatched-manifest-evidence.json" \
    "$writer" --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: mismatched World media was accepted" >&2
    exit 1
fi
if grep -qE '^(dd |diskutil unmountDisk |diskutil eject )' "$log"; then
    echo "macos-writer-simulation: manifest rejection reached a destructive command" >&2
    exit 1
fi
cp "$temporary/valid-image-manifest.json" "$image.manifest.json"

# The World's overlays change after `world build-image`: the re-resolved
# Catalog embeds the new World plan, its digest no longer matches the one the
# raw-image manifest bound, and the writer refuses before inspecting the target.
cp "$catalog" "$temporary/built-catalog.json"
for changed_overlays in '["tailscale"]' '["netbird"]'; do
    # shellcheck disable=SC2016
    "$jq_bin" --argjson overlays "$changed_overlays" '.world.overlays = $overlays' \
        "$temporary/built-catalog.json" > "$catalog"
    : > "$log"
    if PATH="$test_path" TEST_LOG="$log" USB_MEDIA_CATALOG="$catalog" \
        DEVICE_OS_LICENSE_CHECKER="$checker" \
        DEVICE_OS_WRITE_EVIDENCE="$temporary/changed-overlays-evidence.json" \
        "$writer" --image "$image" --device /dev/disk9 \
            --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' \
            >/dev/null 2> "$temporary/changed-overlays.err"; then
        echo "macos-writer-simulation: World overlays $changed_overlays changed after the build were accepted" >&2
        exit 1
    fi
    grep -q 'raw image manifest does not match the image and selected media' "$temporary/changed-overlays.err" || {
        echo "macos-writer-simulation: changed World overlays were not refused by the Catalog binding" >&2
        exit 1
    }
    if [ -s "$log" ] || [ -e "$temporary/changed-overlays-evidence.json" ]; then
        echo "macos-writer-simulation: changed World overlays reached target inspection" >&2
        exit 1
    fi
done
cp "$temporary/built-catalog.json" "$catalog"
: > "$log"
run_writer >/dev/null ||
    { echo "macos-writer-simulation: the unchanged World was refused" >&2; exit 1; }

: > "$log"
if PATH="$test_path" TEST_LOG="$log" TEST_FAIL_BODY_COMPARE=1 \
    USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    DEVICE_OS_WRITE_EVIDENCE="$temporary/body-failure-evidence.json" \
    "$writer" --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: body readback failure was accepted" >&2
    exit 1
fi
if grep -q 'count=1 conv=notrunc$' "$log" &&
    [ "$(grep -c 'count=1 conv=notrunc$' "$log")" -gt 1 ]; then
    echo "macos-writer-simulation: partition map was exposed after body failure" >&2
    exit 1
fi
if grep -q '^diskutil eject ' "$log"; then
    echo "macos-writer-simulation: failed media was ejected as successful" >&2
    exit 1
fi

: > "$log"
if PATH="$test_path" TEST_LOG="$log" TEST_MBR_TYPE=238 \
    USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    DEVICE_OS_WRITE_EVIDENCE="$temporary/gpt-evidence.json" \
    "$writer" --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: GPT image was accepted" >&2
    exit 1
fi
if grep -qE '^(dd |diskutil unmountDisk |diskutil eject )' "$log"; then
    echo "macos-writer-simulation: GPT rejection reached a destructive command" >&2
    exit 1
fi

# Refresh mode: its own confirmation word, and a refusal before any mount or
# write when the target's boot region is not the image's.
: > "$log"
if PATH="$test_path" TEST_LOG="$log" USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    "$writer" --mode refresh --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: refresh accepted the ERASE confirmation" >&2
    exit 1
fi
if grep -qE '^(dd |diskutil unmountDisk |diskutil mount|diskutil eject )' "$log"; then
    echo "macos-writer-simulation: a refused refresh confirmation reached the target" >&2
    exit 1
fi
: > "$log"
rm -f "$temporary/refresh-evidence.json"
if PATH="$test_path" TEST_LOG="$log" TEST_FAIL_PREFIX=1 USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    DEVICE_OS_WRITE_EVIDENCE="$temporary/refresh-evidence.json" \
    "$writer" --mode refresh --image "$image" --device /dev/disk9 \
        --confirm 'REFRESH /dev/disk9 Test USB TEST-SERIAL-9 2097152' \
        >/dev/null 2> "$temporary/refresh.err"; then
    echo "macos-writer-simulation: refresh accepted a target whose first MiB differs" >&2
    exit 1
fi
grep -q 'refresh refused: the target.s first MiB' "$temporary/refresh.err" || {
    echo "macos-writer-simulation: refresh did not name the differing boot region" >&2
    exit 1
}
if grep -qE '^(dd if=[^ ]* of=|diskutil unmountDisk |diskutil mount|diskutil eject )' "$log"; then
    echo "macos-writer-simulation: a refused refresh wrote, mounted or ejected the target" >&2
    exit 1
fi
"$jq_bin" -e '.writer == "macos-file-refresh" and .readback == {method:"file-tree-compare",status:"pending"}' \
    "$temporary/refresh-evidence.json" >/dev/null || {
    echo "macos-writer-simulation: a refused refresh left other than pending refresh evidence" >&2
    exit 1
}
if PATH="$test_path" TEST_LOG="$log" USB_MEDIA_CATALOG="$catalog" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    "$writer" --mode clone --image "$image" --device /dev/disk9 \
        --confirm 'ERASE /dev/disk9 Test USB TEST-SERIAL-9 2097152' >/dev/null 2>&1; then
    echo "macos-writer-simulation: an unknown mode was accepted" >&2
    exit 1
fi

echo "macOS writer simulations: passed"
