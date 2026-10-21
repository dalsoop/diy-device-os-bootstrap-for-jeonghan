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

installer_fixture=$temporary/debian-installer-fixture
installer_bin=$temporary/installer-bin
mkdir -p "$installer_fixture" "$installer_bin"
printf 'test component\n' > "$installer_fixture/component"
component_digest=$(sha256sum "$installer_fixture/component" | awk '{print $1}')
for file in cdrom/initrd.gz cdrom/vmlinuz cdrom/debian-cd_info.tar.gz \
    cdrom/gtk/initrd.gz cdrom/gtk/vmlinuz cdrom/gtk/debian-cd_info.tar.gz; do
    printf '%s  ./%s\n' "$component_digest" "$file"
done > "$installer_fixture/SHA256SUMS"
list_digest=$(sha256sum "$installer_fixture/SHA256SUMS" | awk '{print $1}')
printf 'SHA256:\n %s 1 main/installer-amd64/current/images/SHA256SUMS\n' \
    "$list_digest" > "$installer_fixture/Release"
printf 'test signature\n' > "$installer_fixture/Release.gpg"
cat > "$installer_bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output=$2; shift 2 ;;
        --proto|--tlsv1.2) if [ "$1" = --proto ]; then shift 2; else shift; fi ;;
        --fail|--location) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in
    */Release) source=Release ;;
    */Release.gpg) source=Release.gpg ;;
    */SHA256SUMS) source=SHA256SUMS ;;
    *) source=component ;;
esac
cp "$DNS_TEST_INSTALLER_FIXTURE/$source" "$output"
if [ "$source" = component ] && [ "${DNS_TEST_TAMPER_COMPONENT:-false}" = true ]; then
    printf 'tampered\n' >> "$output"
fi
EOF
cat > "$installer_bin/gpgv" <<'EOF'
#!/bin/sh
[ "${DNS_TEST_BAD_SIGNATURE:-false}" = false ]
EOF
chmod 0755 "$installer_bin/curl" "$installer_bin/gpgv"
fetch_installer() {
    PATH="$installer_bin:$PATH" DNS_TEST_INSTALLER_FIXTURE="$installer_fixture" \
        DNS_APPLIANCE_CACHE_DIR="$1" "$repo_root/installer/fetch-debian-installer"
}
fetch_installer "$temporary/verified-installer" > "$temporary/installer-fetch.log" 2>&1
fetch_installer "$temporary/verified-installer" >> "$temporary/installer-fetch.log" 2>&1
cached_component=$(find "$temporary/verified-installer" -name vmlinuz -print -quit)
printf 'tampered\n' >> "$cached_component"
if fetch_installer "$temporary/verified-installer" >> "$temporary/installer-fetch.log" 2>&1; then
    echo 'image-builder-simulation: tampered installer cache accepted' >&2; exit 1
fi
if DNS_TEST_BAD_SIGNATURE=true fetch_installer "$temporary/bad-signature" >> "$temporary/installer-fetch.log" 2>&1; then
    echo 'image-builder-simulation: unsigned installer metadata accepted' >&2; exit 1
fi
if DNS_TEST_TAMPER_COMPONENT=true fetch_installer "$temporary/bad-component" >> "$temporary/installer-fetch.log" 2>&1; then
    echo 'image-builder-simulation: tampered installer download accepted' >&2; exit 1
fi
printf 'tampered metadata\n' >> "$installer_fixture/SHA256SUMS"
if fetch_installer "$temporary/bad-checksums" >> "$temporary/installer-fetch.log" 2>&1; then
    echo 'image-builder-simulation: unbound installer checksum list accepted' >&2; exit 1
fi
[ -z "$(find "$temporary/verified-installer" "$temporary/bad-signature" \
    "$temporary/bad-component" "$temporary/bad-checksums" -name '.verify.*' -print)" ]

boot_tree=$temporary/boot-tree
mkdir -p "$boot_tree/boot1/isolinux" "$boot_tree/CD1/boot/grub"
printf 'timeout 0\ninclude spkgtk.cfg\n' > "$boot_tree/boot1/isolinux/isolinux.cfg"
printf 'label installspk\nTIMEOUT 300\nmenu timeoutrow 16\n' > "$boot_tree/boot1/isolinux/spkgtk.cfg"
printf 'set timeout=0\nmenuentry install\n' > "$boot_tree/CD1/boot/grub/grub.cfg"
"$repo_root/installer/disable-boot-timeouts" "$temporary" "$temporary" 1 "$boot_tree/CD1" amd64
grep -q '^TIMEOUT 0$' "$boot_tree/boot1/isolinux/spkgtk.cfg"
grep -q '^menu timeoutrow 16$' "$boot_tree/boot1/isolinux/spkgtk.cfg"
grep -q '^set timeout=-1$' "$boot_tree/CD1/boot/grub/grub.cfg"
if "$repo_root/installer/disable-boot-timeouts" "$temporary" "$temporary" 2 "$boot_tree/CD1" amd64; then
    echo 'image-builder-simulation: unexpected disc accepted' >&2; exit 1
fi
if "$repo_root/installer/disable-boot-timeouts" "$temporary" "$temporary" 1 "$temporary/missing" amd64; then
    echo 'image-builder-simulation: missing boot tree accepted' >&2; exit 1
fi

prepare_fixture=$temporary/prepare
mkdir -p "$prepare_fixture/bin"
cp "$repo_root/installer/scripts/prepare-installer" "$prepare_fixture/prepare-installer"
cat > "$prepare_fixture/install-gate" <<'EOF'
#!/bin/sh
printf 'gate %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"
EOF
cat > "$prepare_fixture/confmodule" <<'EOF'
db_set() { printf 'debconf %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"; }
anna() {
    printf 'components %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"
    [ "${DNS_TEST_PREPARE_FAILURE:-}" != components ]
}
udpkg() {
    printf 'hardware %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"
    [ "${DNS_TEST_PREPARE_FAILURE:-}" != hardware ]
}
EOF
cat > "$prepare_fixture/bin/anna-install" <<'EOF'
#!/bin/sh
printf 'queue %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"
EOF
chmod 0755 "$prepare_fixture/bin/anna-install"
PATH="$prepare_fixture/bin:$PATH"
export PATH
export DNS_INSTALLER_DEBCONF_MODULE=$prepare_fixture/confmodule
export DNS_TEST_PREPARE_LOG=$prepare_fixture/log
/bin/sh "$prepare_fixture/prepare-installer"
printf '%s\n' 'debconf debconf/language ko' 'queue simple-cdd-profiles' \
    'components cdrom-retriever default' 'hardware --configure ethdetect' \
    'gate identify' > "$prepare_fixture/expected"
cmp "$prepare_fixture/expected" "$prepare_fixture/log"
for prepare_failure in components hardware; do
    : > "$prepare_fixture/log"
    if DNS_TEST_PREPARE_FAILURE=$prepare_failure /bin/sh "$prepare_fixture/prepare-installer"; then
        echo 'image-builder-simulation: failed preparation accepted' >&2; exit 1
    fi
    if grep -q '^gate ' "$prepare_fixture/log"; then
        echo 'image-builder-simulation: identity prompt reached after preparation failure' >&2; exit 1
    fi
done

echo "image builder, offline preparation, boot menus and signed Debian installer fetch simulations: passed"
