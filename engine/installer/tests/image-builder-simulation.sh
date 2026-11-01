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
  }
}
EOF

checker=$temporary/checker
cat > "$checker" <<'EOF'
#!/bin/sh
[ "${DEVICE_OS_DISTRIBUTION_POLICY:-}" = "${EXPECTED_POLICY:?}" ] || exit 88
if [ "${TEST_POLICY_DENY:-0}" = 1 ]; then
  exit 1
fi
cat <<'JSON'
{"schema_version":1,"mode":"personal-use","decision":"allow","selected_artifacts":[{"id":"ventoy","kind":"bootloader","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","status":"personal-use-only"},{"id":"debian-live","kind":"catalog-entry","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","status":"personal-use-only"}],"blockers":[],"warnings":[{"code":"artifact-unreviewed","artifact_id":"ventoy","message":"Public redistribution is not approved."}]}
JSON
EOF
chmod +x "$checker"

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
[ -n "${DEVICE_OS_LICENSE_DECISION_OUTPUT:-}" ]
jq '.selected_artifacts += [
  {id:"runtime-component",kind:"component",sha256:("e"*64),status:"redistribution-reviewed"},
  {id:"media-final",kind:"final-artifact",sha256:("f"*64),status:"redistribution-reviewed"}
]' "$DEVICE_OS_LICENSE_DECISION_OUTPUT" > "$DEVICE_OS_LICENSE_DECISION_OUTPUT.next"
mv "$DEVICE_OS_LICENSE_DECISION_OUTPUT.next" "$DEVICE_OS_LICENSE_DECISION_OUTPUT"
printf 'writer %s\n' "$*" >> "$TEST_LOG"
EOF
chmod +x "$writer"

PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" \
EXPECTED_POLICY="$repo_root/usb-media/distribution-policy.json" \
DEVICE_OS_DISTRIBUTION_POLICY="$temporary/ambient-policy.json" \
DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
DEVICE_OS_IMAGE_WRITER="$writer" \
DEVICE_OS_LICENSE_CHECKER="$checker" \
    "$builder" --output "$output" --size 4294967296 --catalog "$catalog" >/dev/null

[ -f "$output" ]
[ -f "$output.sha256" ]
[ -f "$output.manifest.json" ]
grep -q '  device-os.raw$' "$output.sha256"
jq -e '
  .schema_version == 2 and
  .kind == "device-os-raw-image" and
  .image.filename == "device-os.raw" and
  .image.bytes == 4294967296 and
  .image.sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.revision == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .catalog.tree == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" and
  .license.mode == "personal-use" and
  .license.decision == "allow" and
  .license.distribution_policy_sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  [.license.selected_artifacts[].id] == ["ventoy", "debian-live", "runtime-component", "media-final"] and
  .license.selected_artifacts[2].sha256 == ("e"*64) and
  .license.selected_artifacts[2].status == "redistribution-reviewed" and
  .license.selected_artifacts[3].sha256 == ("f"*64) and
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

: > "$log"
policy_refusal=$temporary/policy-refusal.raw
if PATH="$mock_bin:/usr/bin:/bin" TEST_LOG="$log" TEST_POLICY_DENY=1 \
    EXPECTED_POLICY="$repo_root/usb-media/distribution-policy.json" \
    DEVICE_OS_DISTRIBUTION_POLICY="$temporary/ambient-policy.json" \
    DEVICE_OS_SKIP_LOOP_NODE_SETUP=1 \
    DEVICE_OS_IMAGE_WRITER="$writer" \
    DEVICE_OS_LICENSE_CHECKER="$checker" \
    "$builder" --output "$policy_refusal" --size 4294967296 --catalog "$catalog" \
    >/dev/null 2>&1; then
    echo "image-builder-simulation: denied license policy was accepted" >&2
    exit 1
fi
[ ! -e "$policy_refusal" ]
if grep -q '^writer ' "$log"; then
    echo "image-builder-simulation: policy refusal reached the image writer" >&2
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
        DNS_APPLIANCE_CACHE_DIR="$1" "$repo_root/dns-image/fetch-debian-installer"
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
"$repo_root/dns-image/disable-boot-timeouts" "$temporary" "$temporary" 1 "$boot_tree/CD1" amd64
grep -q '^TIMEOUT 0$' "$boot_tree/boot1/isolinux/spkgtk.cfg"
grep -q '^menu timeoutrow 16$' "$boot_tree/boot1/isolinux/spkgtk.cfg"
grep -q '^set timeout=-1$' "$boot_tree/CD1/boot/grub/grub.cfg"
if "$repo_root/dns-image/disable-boot-timeouts" "$temporary" "$temporary" 2 "$boot_tree/CD1" amd64; then
    echo 'image-builder-simulation: unexpected disc accepted' >&2; exit 1
fi
if "$repo_root/dns-image/disable-boot-timeouts" "$temporary" "$temporary" 1 "$temporary/missing" amd64; then
    echo 'image-builder-simulation: missing boot tree accepted' >&2; exit 1
fi

prepare_fixture=$temporary/prepare
mkdir -p "$prepare_fixture/bin"
cp "$repo_root/dns-image/scripts/prepare-installer" "$prepare_fixture/prepare-installer"
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
modprobe() {
    printf 'filesystem %s\n' "$*" >> "$DNS_TEST_PREPARE_LOG"
    [ "${DNS_TEST_PREPARE_FAILURE:-}" != filesystem ]
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
printf '%s\n' 'debconf debconf/language ko' 'queue simple-cdd-profiles fat-modules' \
    'components cdrom-retriever default' 'filesystem vfat' 'hardware --configure ethdetect' \
    'gate identify' > "$prepare_fixture/expected"
cmp "$prepare_fixture/expected" "$prepare_fixture/log"
for prepare_failure in components filesystem hardware; do
    : > "$prepare_fixture/log"
    if DNS_TEST_PREPARE_FAILURE=$prepare_failure /bin/sh "$prepare_fixture/prepare-installer"; then
        echo 'image-builder-simulation: failed preparation accepted' >&2; exit 1
    fi
    if grep -q '^gate ' "$prepare_fixture/log"; then
        echo 'image-builder-simulation: identity prompt reached after preparation failure' >&2; exit 1
    fi
done

installer_dir=$repo_root/dns-image
simulation_fail() {
    echo "image-builder-simulation: $*" >&2
    exit 1
}

# Installer target-package closure: every package from dns.packages and
# installer-target-packages must be in the offline DVD package list.
closure=$temporary/closure
mkdir -p "$closure"
awk '{ sub(/#.*/, "") } { for (i = 1; i <= NF; i++) print $i "=1.0-1" }' \
    "$installer_dir/simple-cdd/profiles/dns.packages" \
    "$installer_dir/installer-target-packages" | LC_ALL=C sort -u > "$closure/complete.txt"
printf 'unrelated-package=2.0\n' >> "$closure/complete.txt"
"$installer_dir/check-installer-closure" "$closure/complete.txt" > "$closure/pass.log" 2>&1 ||
    simulation_fail "complete offline package list rejected: $(cat "$closure/pass.log")"
"$installer_dir/check-installer-closure" "$closure/complete.txt" \
    "$installer_dir/simple-cdd/profiles/dns.packages" \
    "$installer_dir/installer-target-packages" > "$closure/pass.log" 2>&1 ||
    simulation_fail "explicit closure inputs rejected"
reject_closure() {
    expected=$1
    shift
    if "$installer_dir/check-installer-closure" "$@" > "$closure/reject.log" 2>&1; then
        simulation_fail "installer closure accepted a list that should fail: $expected"
    fi
    grep -q -F -- "$expected" "$closure/reject.log" ||
        simulation_fail "installer closure diagnostic lacks '$expected': $(cat "$closure/reject.log")"
}
grep -v '^zstd=' "$closure/complete.txt" > "$closure/no-zstd.txt"
reject_closure 'missing from the offline DVD: zstd (dns.packages, installer-target-packages)' \
    "$closure/no-zstd.txt"
grep -v '^tasksel=' "$closure/complete.txt" > "$closure/no-tasksel.txt"
reject_closure 'missing from the offline DVD: tasksel (installer-target-packages)' \
    "$closure/no-tasksel.txt"
grep -v '^grub-pc=' "$closure/complete.txt" > "$closure/no-grub-pc.txt"
reject_closure 'missing from the offline DVD: grub-pc' "$closure/no-grub-pc.txt"
grep -v '^podman=' "$closure/complete.txt" > "$closure/no-podman.txt"
reject_closure 'missing from the offline DVD: podman (dns.packages)' "$closure/no-podman.txt"
: > "$closure/empty.txt"
reject_closure 'offline DVD package list is empty' "$closure/empty.txt"
printf 'zstd 1.5\n' > "$closure/malformed.txt"
reject_closure 'malformed offline DVD package list line 1' "$closure/malformed.txt"
reject_closure 'cannot read' "$closure/absent.txt"
printf '# only a comment\n' > "$closure/comment-only.list"
reject_closure 'comment-only.list lists no packages' "$closure/complete.txt" \
    "$installer_dir/simple-cdd/profiles/dns.packages" "$closure/comment-only.list"
printf 'zstd\nBad_Name\n' > "$closure/bad-name.list"
reject_closure 'bad-name.list:2: invalid package name: Bad_Name' "$closure/complete.txt" \
    "$installer_dir/simple-cdd/profiles/dns.packages" "$closure/bad-name.list"
reject_closure 'usage:' "$closure/complete.txt" a b c

# Installer-screen glyphs: synthetic BOGL fonts and initrds only; no real
# font is ever committed or downloaded by this simulation.
glyphs=$temporary/glyphs
mkdir -p "$glyphs/bin"
cat > "$glyphs/make-fixture.py" <<'EOF'
import gzip, struct, sys

def bgf(codepoints, mask=0xFF):
    buckets = [[] for _ in range(mask + 1)]
    for codepoint in sorted(codepoints):
        buckets[codepoint & mask].append(codepoint)
    header = 4 + 8 + 4 + 4 + 8 + 8 + 8
    name = b"fixture\0\0\0\0\0"
    offset_ptr = header + len(name)
    index_ptr = offset_ptr + 4 * (mask + 1)
    offsets, index = [], []
    for bucket in buckets:
        offsets.append(len(index))
        for codepoint in bucket:
            index += [(codepoint & ~mask) | 8, 0]
        index.append(0)
    content_ptr = index_ptr + 4 * len(index)
    return (b"BGF1" + struct.pack("<QiiQQQ", header, 16, mask, offset_ptr, index_ptr, content_ptr)
            + name + struct.pack("<%di" % len(offsets), *offsets)
            + struct.pack("<%di" % len(index), *index) + b"\0" * 16)

def newc(entries):
    out = b""
    for inode, (name, mode, data) in enumerate(entries + [("TRAILER!!!", 0, b"")], 1):
        raw = name.encode() + b"\0"
        fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(raw), 0]
        out += b"070701" + b"".join(b"%08X" % f for f in fields) + raw
        out += b"\0" * (-len(out) % 4) + data
        out += b"\0" * (-len(out) % 4)
    return out

kind, output = sys.argv[1], sys.argv[2]
chars = set()
for path in sys.argv[3:]:
    if path.startswith("drop:"):
        chars.discard(ord(path[5:]))
    else:
        chars |= {ord(c) for c in open(path, encoding="utf-8").read() if ord(c) > 127}
font = bgf(chars | {ord("A")})
if kind == "bad-magic":
    font = b"XXXX" + font[4:]
if kind == "truncated":
    font = font[:200]
members = [(".", 0o040755, b""), ("usr", 0o040755, b""), ("usr/lib", 0o040755, b"")]
if kind != "no-font":
    members.append(("usr/lib/unifont.bgf", 0o100644, font))
archive = newc(members)
if kind == "not-gzip":
    open(output, "wb").write(archive)
else:
    open(output, "wb").write(gzip.compress(newc([("early", 0o100644, b"x")])) + gzip.compress(archive))
EOF
templates=$installer_dir/scripts/guided.templates
make_initrd() {
    python3 -I "$glyphs/make-fixture.py" "$@"
}
make_initrd ok "$glyphs/ok.gz" "$templates"
make_initrd ok "$glyphs/no-yeok.gz" "$templates" "drop:역"
make_initrd bad-magic "$glyphs/bad-magic.gz" "$templates"
make_initrd truncated "$glyphs/truncated.gz" "$templates"
make_initrd no-font "$glyphs/no-font.gz" "$templates"
make_initrd not-gzip "$glyphs/not-gzip.gz" "$templates"
"$installer_dir/check-installer-glyphs" --initrd "$glyphs/ok.gz" > "$glyphs/pass.log" 2>&1 ||
    simulation_fail "guided templates rejected by a font that has every glyph: $(cat "$glyphs/pass.log")"
"$installer_dir/check-installer-glyphs" --initrd "$glyphs/ok.gz" "$templates" > "$glyphs/pass.log" 2>&1 ||
    simulation_fail "explicit guided templates rejected"
cp "$templates" "$glyphs/guided.templates"
printf ' 디스크를 삭제합니다.\n' >> "$glyphs/guided.templates"
sak_line=$(awk 'END { print NR }' "$glyphs/guided.templates")
reject_glyphs() {
    expected=$1
    shift
    if "$installer_dir/check-installer-glyphs" "$@" > "$glyphs/reject.log" 2>&1; then
        simulation_fail "glyph check accepted input that should fail: $expected"
    fi
    grep -q -F -- "$expected" "$glyphs/reject.log" ||
        simulation_fail "glyph diagnostic lacks '$expected': $(cat "$glyphs/reject.log")"
}
reject_glyphs "guided.templates:$sak_line: U+C0AD '삭' is not in the installer font" \
    --initrd "$glyphs/ok.gz" "$glyphs/guided.templates"
yeok_line=$(grep -n '역' "$templates" | awk -F: 'NR == 1 { print $1 }')
reject_glyphs "guided.templates:$yeok_line: U+C5ED '역' is not in the installer font" \
    --initrd "$glyphs/no-yeok.gz"
reject_glyphs 'is not a BGF1 font' --initrd "$glyphs/bad-magic.gz"
reject_glyphs 'font is truncated' --initrd "$glyphs/truncated.gz"
reject_glyphs 'initrd has no usr/lib/unifont.bgf' --initrd "$glyphs/no-font.gz"
reject_glyphs 'initrd is not gzip-compressed' --initrd "$glyphs/not-gzip.gz"
printf '\377\376 invalid\n' > "$glyphs/not-utf8.templates"
reject_glyphs 'not-utf8.templates is not UTF-8' --initrd "$glyphs/ok.gz" "$glyphs/not-utf8.templates"
reject_glyphs 'cannot read' --initrd "$glyphs/absent.gz"
reject_glyphs 'usage:' --font "$glyphs/ok.gz"

# A file-backed xorriso stand-in: an "ISO" is a directory tree next to the
# image file. Only the operations used by refresh-guided-iso and the glyph
# check are emulated; /install.amd/initrd.gz is served from DNS_TEST_INITRD.
cat > "$glyphs/bin/xorriso" <<'EOF'
#!/bin/sh
set -eu
[ "${DNS_TEST_XORRISO_FAIL:-false}" = false ] || exit 5
indev= outdev= maps= extract_from= extract_to=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -indev) indev=$2; shift 2 ;;
        -outdev) outdev=$2; shift 2 ;;
        -map) maps="$maps$2|$3
"; shift 3 ;;
        -extract) extract_from=$2; extract_to=$3; shift 3 ;;
        -osirrox|-boot_image) shift 2 ;;
        replay) shift ;;
        *) shift ;;
    esac
done
if [ -n "$outdev" ]; then
    rm -rf "$outdev.tree"
    cp -R "$indev.tree" "$outdev.tree"
    printf '%s' "$maps" | while IFS='|' read -r source target; do
        [ -n "$source" ] || continue
        mkdir -p "$(dirname "$outdev.tree$target")"
        cp "$source" "$outdev.tree$target"
    done
    : > "$outdev"
    exit 0
fi
[ -n "$extract_from" ]
if [ "$extract_from" = /install.amd/initrd.gz ]; then
    cp "$DNS_TEST_INITRD" "$extract_to"
else
    [ -e "$indev.tree$extract_from" ]
    cp -R "$indev.tree$extract_from" "$extract_to"
fi
EOF
chmod 0755 "$glyphs/bin/xorriso"
iso_glyphs() {
    PATH="$glyphs/bin:$PATH" DNS_TEST_INITRD=$1 "$installer_dir/check-installer-glyphs" --iso "$2"
}
: > "$glyphs/plain.iso"
iso_glyphs "$glyphs/ok.gz" "$glyphs/plain.iso" > "$glyphs/pass.log" 2>&1 ||
    simulation_fail "ISO glyph check rejected a font that has every glyph"
if iso_glyphs "$glyphs/no-yeok.gz" "$glyphs/plain.iso" > "$glyphs/reject.log" 2>&1; then
    simulation_fail "ISO glyph check accepted a font without a template glyph"
fi
if PATH="$glyphs/bin:$PATH" DNS_TEST_XORRISO_FAIL=true DNS_TEST_INITRD="$glyphs/ok.gz" \
    "$installer_dir/check-installer-glyphs" --iso "$glyphs/plain.iso" > "$glyphs/reject.log" 2>&1; then
    simulation_fail "ISO glyph check accepted an ISO without an installer initrd"
fi
grep -q -F 'ISO has no /install.amd/initrd.gz' "$glyphs/reject.log" ||
    simulation_fail "missing initrd diagnostic: $(cat "$glyphs/reject.log")"

# gate-built-iso: a failed check deletes the Simple-CDD ISO and leaves no
# build manifest, SBOM or checksum list that could be paired with it.
gate=$temporary/gate
run_gate() {
    rm -rf "$gate"
    mkdir -p "$gate/images" "$gate/artifacts"
    printf 'iso\n' > "$gate/images/debian.iso"
    for stale in build-manifest.json sbom.spdx.json SHA256SUMS; do
        printf 'stale\n' > "$gate/artifacts/$stale"
    done
    PATH="$glyphs/bin:$PATH" DNS_TEST_INITRD=$1 \
        "$installer_dir/gate-built-iso" "$gate/images/debian.iso" "$2" "$gate/artifacts" \
        > "$gate.log" 2>&1
}
run_gate "$glyphs/ok.gz" "$closure/complete.txt" ||
    simulation_fail "gate rejected a complete build: $(cat "$gate.log")"
[ -f "$gate/images/debian.iso" ] || simulation_fail "gate removed an accepted ISO"
reject_gate() {
    expected=$1
    shift
    if run_gate "$@"; then
        simulation_fail "gate accepted a build that should fail: $expected"
    fi
    grep -q -F -- "$expected" "$gate.log" ||
        simulation_fail "gate diagnostic lacks '$expected': $(cat "$gate.log")"
    [ ! -e "$gate/images/debian.iso" ] || simulation_fail "gate kept a rejected ISO ($expected)"
    for stale in build-manifest.json sbom.spdx.json SHA256SUMS; do
        [ ! -e "$gate/artifacts/$stale" ] ||
            simulation_fail "gate kept $stale beside a rejected ISO ($expected)"
    done
}
reject_gate 'missing from the offline DVD: zstd' "$glyphs/ok.gz" "$closure/no-zstd.txt"
reject_gate "U+C5ED '역' is not in the installer font" "$glyphs/no-yeok.gz" "$closure/complete.txt"
reject_gate 'offline DVD package list is empty' "$glyphs/ok.gz" "$closure/empty.txt"

# build-image must gate before it renders the manifest, and refresh-guided-iso
# must gate before it promotes the candidate.
awk '
    /gate-built-iso/ && !gate { gate = NR }
    /^"\$script_dir\/render-build-records" "\$@"$/ && !manifest { manifest = NR }
    /debian-packages\.txt/ && !packages { packages = NR }
    END { exit !(packages && gate && manifest && packages < gate && gate < manifest) }
' "$installer_dir/build-image" ||
    simulation_fail "build-image does not gate the ISO between the package list and the manifest"

refresh=$temporary/refresh
mkdir -p "$refresh/base.iso.tree/simple-cdd" "$refresh/base.iso.tree/boot/grub" \
    "$refresh/base.iso.tree/isolinux"
: > "$refresh/base.iso"
printf 'guided\n' > "$refresh/base.iso.tree/simple-cdd/install-mode"
printf 'tailscale\nnetbird\n' > "$refresh/base.iso.tree/simple-cdd/overlays"
printf 'set timeout=-1\n' > "$refresh/base.iso.tree/boot/grub/grub.cfg"
printf 'timeout 0\n' > "$refresh/base.iso.tree/isolinux/isolinux.cfg"
run_refresh() {
    PATH="$glyphs/bin:$PATH" DNS_TEST_INITRD=$1 TMPDIR=$refresh \
        "$installer_dir/refresh-guided-iso" "$refresh/base.iso" "$2" > "$refresh.log" 2>&1
}
run_refresh "$glyphs/ok.gz" "$refresh/out/ok.iso" ||
    simulation_fail "refresh rejected guided files the font can draw: $(cat "$refresh.log")"
[ -e "$refresh/out/ok.iso" ] || simulation_fail "refresh did not promote the candidate"
if run_refresh "$glyphs/no-yeok.gz" "$refresh/out/missing-glyph.iso"; then
    simulation_fail "refresh promoted a candidate whose prompts the font cannot draw"
fi
grep -q -F "U+C5ED '역' is not in the installer font" "$refresh.log" ||
    simulation_fail "refresh glyph diagnostic missing: $(cat "$refresh.log")"
[ ! -e "$refresh/out/missing-glyph.iso" ] ||
    simulation_fail "refresh left a rejected candidate at the output path"

# ---------------------------------------------------------------------------
# Overlay clients follow the World: NetBird pin, selection, fetch, build
# records, appliance installation and first boot.
monorepo_root=$(CDPATH='' cd -- "$repo_root/../.." && pwd)
overlay=$temporary/overlay
mkdir -p "$overlay"

# verify-locks accepts only the exact version-pinned NetBird release.
locks=$overlay/locks
mkdir -p "$locks/build/locks" "$locks/dns-image/simple-cdd"
cp -p "$repo_root/build/verify-locks" "$repo_root/build/distribution-policy.json" "$locks/build/"
cp -p "$repo_root/dns-image/simple-cdd/simple-cdd.conf" "$locks/dns-image/simple-cdd/"
cp -p "$repo_root/build/locks/sources.env" "$locks/build/locks/sources.env"
"$locks/build/verify-locks" > "$overlay/locks.log" 2>&1 ||
    simulation_fail "verify-locks rejected the reviewed locks: $(cat "$overlay/locks.log")"
grep -qx 'NETBIRD_VERSION=0.82.0' "$repo_root/build/locks/sources.env" ||
    simulation_fail "NetBird is not pinned to 0.82.0"
grep -qx 'NETBIRD_AMD64_URL=https://github.com/netbirdio/netbird/releases/download/v0.82.0/netbird_0.82.0_linux_amd64.tar.gz' \
    "$repo_root/build/locks/sources.env" || simulation_fail "NetBird URL is not the pinned release asset"
reject_lock() {
    description=$1
    key=$2
    value=$3
    awk -F= -v key="$key" -v value="$value" '
        $1 == key { if (value != "-") print key "=" value; next }
        { print }
    ' "$repo_root/build/locks/sources.env" > "$locks/build/locks/sources.env"
    if "$locks/build/verify-locks" > "$overlay/locks.log" 2>&1; then
        simulation_fail "verify-locks accepted $description"
    fi
}
release_base=https://github.com/netbirdio/netbird/releases
reject_lock "a two-part NetBird version" NETBIRD_VERSION 0.82
reject_lock "a moving NetBird version" NETBIRD_VERSION latest
reject_lock "a missing NetBird version" NETBIRD_VERSION -
reject_lock "a moving NetBird URL" NETBIRD_AMD64_URL \
    "$release_base/latest/download/netbird_0.82.0_linux_amd64.tar.gz"
reject_lock "a NetBird URL for another tag" NETBIRD_AMD64_URL \
    "$release_base/download/v0.81.0/netbird_0.82.0_linux_amd64.tar.gz"
reject_lock "a NetBird URL for another architecture" NETBIRD_AMD64_URL \
    "$release_base/download/v0.82.0/netbird_0.82.0_linux_arm64.tar.gz"
reject_lock "a plain-HTTP NetBird URL" NETBIRD_AMD64_URL \
    "http://github.com/netbirdio/netbird/releases/download/v0.82.0/netbird_0.82.0_linux_amd64.tar.gz"
reject_lock "a NetBird URL from another host" NETBIRD_AMD64_URL \
    "https://example.test/netbirdio/netbird/releases/download/v0.82.0/netbird_0.82.0_linux_amd64.tar.gz"
reject_lock "a missing NetBird URL" NETBIRD_AMD64_URL -
reject_lock "an uppercase NetBird SHA-256" NETBIRD_AMD64_SHA256 \
    B569F65DE303D21317BC716F3116002E2CF175AE22A9F6D2BED91200A2F5000B
reject_lock "a short NetBird SHA-256" NETBIRD_AMD64_SHA256 b569f65de303d213
reject_lock "a missing NetBird SHA-256" NETBIRD_AMD64_SHA256 -
cp -p "$repo_root/build/locks/sources.env" "$locks/build/locks/sources.env"
jq '.component_ids |= map(select(. != "netbird-archive"))' "$repo_root/build/distribution-policy.json" \
    > "$locks/build/distribution-policy.json"
if "$locks/build/verify-locks" > "$overlay/locks.log" 2>&1; then
    simulation_fail "verify-locks accepted a policy without the NetBird component"
fi

# A disposable checkout holding the World resolver, the overlay tools and a
# playbook with three Worlds that differ only in their overlay selection.
tree=$overlay/tree
mkdir -p "$tree/engine/world/bin" "$tree/engine/installer/dns-image" \
    "$tree/engine/installer/build/locks" "$tree/burn-history"
cp -p "$monorepo_root/engine/world/bin/resolve-world" "$tree/engine/world/bin/"
cp -p "$repo_root/dns-image/overlay-selection" "$repo_root/dns-image/fetch-locked-sources" \
    "$tree/engine/installer/dns-image/"
ruby -ryaml -e '
  source, directory = ARGV
  world = YAML.safe_load_file(source)
  { "jeonghan-home" => %w[tailscale netbird], "tailscale-home" => %w[tailscale],
    "netbird-home" => %w[netbird], "reverse-home" => %w[netbird tailscale] }.each do |slug, overlays|
    world["metadata"]["slug"] = slug
    world["spec"]["overlays"] = overlays
    File.write(File.join(directory, "#{slug}.yaml"), YAML.dump(world))
  end
' "$monorepo_root/burn-history/home.yaml" "$tree/burn-history"
playbook() {
    {
        printf '%s\n' 'apiVersion: device-os.bootstrap/v1alpha1' 'kind: WorldPlaybook' \
            'metadata:' '  name: Overlay fixture' 'spec:' '  timezone: Asia/Seoul' '  drafts:'
        for slug in "$@"; do
            printf '    - slug: %s\n      path: %s.yaml\n' "$slug" "$slug"
        done
        printf '%s\n' '  generations:' '    root: logs/usb' \
            '    idFormat: "{YYYYMMDDHHmmss}-{world-slug}"' \
            '    publishAfter: verified-physical-usb-write'
    } > "$tree/burn-history/.paths.yaml"
}
playbook jeonghan-home tailscale-home netbird-home reverse-home
selection_of() {
    DEVICE_OS_WORLD=$1 "$tree/engine/installer/dns-image/overlay-selection" resolve
}
[ "$(selection_of jeonghan-home)" = "$(printf 'tailscale\nnetbird')" ] ||
    simulation_fail "dual-overlay World did not resolve in canonical order"
[ "$(selection_of tailscale-home)" = tailscale ] || simulation_fail "Tailscale-only World did not resolve"
[ "$(selection_of netbird-home)" = netbird ] || simulation_fail "NetBird-only World did not resolve"
[ "$(selection_of reverse-home)" = "$(printf 'tailscale\nnetbird')" ] ||
    simulation_fail "World order leaked into the canonical image selection"
if "$tree/engine/installer/dns-image/overlay-selection" resolve > "$overlay/select.log" 2>&1; then
    simulation_fail "overlay selection ignored an ambiguous World without DEVICE_OS_WORLD"
fi
if DEVICE_OS_WORLD=missing-home "$tree/engine/installer/dns-image/overlay-selection" resolve \
    > "$overlay/select.log" 2>&1; then
    simulation_fail "overlay selection accepted an undeclared World"
fi

# The selection is validated again after the resolver, independent of it.
fake_tree=$overlay/fake-tree
mkdir -p "$fake_tree/engine/world/bin" "$fake_tree/engine/installer/dns-image"
cp -p "$repo_root/dns-image/overlay-selection" "$fake_tree/engine/installer/dns-image/"
cat > "$fake_tree/engine/world/bin/resolve-world" <<'EOF'
#!/bin/sh
printf '%s\n' "$FAKE_WORLD_PLAN"
EOF
chmod 0755 "$fake_tree/engine/world/bin/resolve-world"
for plan in '{"overlays":["wireguard"]}' '{"overlays":[]}' '{"overlays":["tailscale","tailscale"]}' \
    '{"overlays":"tailscale"}' '{"overlays":[1]}' '{}' 'not-json'; do
    if FAKE_WORLD_PLAN=$plan "$fake_tree/engine/installer/dns-image/overlay-selection" resolve \
        > "$overlay/select.log" 2>&1; then
        simulation_fail "overlay selection accepted resolver output $plan"
    fi
done
FAKE_WORLD_PLAN='{"overlays":["netbird"]}' "$fake_tree/engine/installer/dns-image/overlay-selection" \
    resolve > "$overlay/select.log" || simulation_fail "overlay selection rejected a valid resolver output"
[ "$(cat "$overlay/select.log")" = netbird ] || simulation_fail "overlay selection changed a valid selection"

# Selection files: exactly one canonical value per line.
for content in 'tailscale\n' 'netbird\n' 'tailscale\nnetbird\n'; do
    printf '%b' "$content" > "$overlay/selection"
    "$repo_root/dns-image/overlay-selection" check "$overlay/selection" ||
        simulation_fail "valid selection file rejected: $content"
done
for content in '' 'netbird\ntailscale\n' 'tailscale\ntailscale\n' 'wireguard\n' 'tailscale \n' '\n' \
    'tailscale\n\nnetbird\n'; do
    printf '%b' "$content" > "$overlay/selection"
    if "$repo_root/dns-image/overlay-selection" check "$overlay/selection" 2>/dev/null; then
        simulation_fail "malformed selection file accepted: $content"
    fi
done
if "$repo_root/dns-image/overlay-selection" check "$overlay/absent" 2>/dev/null; then
    simulation_fail "missing selection file accepted"
fi

# Notices bundled into the image keep only the selected overlay sections.
for selection in tailscale netbird; do
    printf '%s\n' "$selection" > "$overlay/selection"
    "$repo_root/dns-image/overlay-selection" notices "$overlay/selection" \
        "$monorepo_root/docs/licenses/THIRD_PARTY_NOTICES.md" > "$overlay/notices.md"
    other=netbird
    [ "$selection" = netbird ] && other=tailscale
    grep -q "overlay:$selection:begin" "$overlay/notices.md" ||
        simulation_fail "notices lost the selected $selection section"
    if grep -q -i -e "overlay:$other:" -e "### $other" "$overlay/notices.md"; then
        simulation_fail "notices kept the unselected $other section"
    fi
done
printf 'tailscale\nnetbird\n' > "$overlay/selection"
"$repo_root/dns-image/overlay-selection" notices "$overlay/selection" \
    "$monorepo_root/docs/licenses/THIRD_PARTY_NOTICES.md" > "$overlay/notices.md"
cmp -s "$overlay/notices.md" "$monorepo_root/docs/licenses/THIRD_PARTY_NOTICES.md" ||
    simulation_fail "dual-overlay notices differ from the repository notices"
grep -v 'overlay:netbird:end' "$monorepo_root/docs/licenses/THIRD_PARTY_NOTICES.md" > "$overlay/broken-notices.md"
if "$repo_root/dns-image/overlay-selection" notices "$overlay/selection" "$overlay/broken-notices.md" \
    > /dev/null 2>&1; then
    simulation_fail "notices without a closing overlay marker were accepted"
fi

# fetch-locked-sources fetches only the selected clients, verifies every
# digest, promotes atomically, and re-verifies cached copies.
fixtures=$overlay/fixtures
mkdir -p "$fixtures/tailscale_1.104.1_amd64" "$fixtures/netbird-root"
printf 'tailscale archive\n' > "$fixtures/tailscale_1.104.1_amd64/tailscale"
tar -czf "$fixtures/tailscale.tgz" -C "$fixtures" tailscale_1.104.1_amd64
printf 'dependency report\n' > "$fixtures/licenses.md"
printf 'netbird client\n' > "$fixtures/netbird-root/netbird"
chmod 0755 "$fixtures/netbird-root/netbird"
tar -czf "$fixtures/netbird.tar.gz" -C "$fixtures/netbird-root" netbird
digest_of() {
    sha256sum "$1" | awk '{print $1}'
}
awk -F= -v ts="$(digest_of "$fixtures/tailscale.tgz")" -v report="$(digest_of "$fixtures/licenses.md")" \
    -v nb="$(digest_of "$fixtures/netbird.tar.gz")" '
    $1 == "TAILSCALE_AMD64_SHA256" { print $1 "=" ts; next }
    $1 == "TAILSCALE_LICENSES_SHA256" { print $1 "=" report; next }
    $1 == "NETBIRD_AMD64_SHA256" { print $1 "=" nb; next }
    { print }
' "$repo_root/build/locks/sources.env" > "$tree/engine/installer/build/locks/sources.env"
fetch_bin=$overlay/fetch-bin
mkdir -p "$fetch_bin"
cat > "$fetch_bin/skopeo" <<'EOF'
#!/bin/sh
case "$1" in
    inspect) printf '%s\n' "$TEST_TECHNITIUM_DIGEST" ;;
    copy)
        for argument in "$@"; do last=$argument; done
        destination=${last#oci-archive:}
        printf 'oci archive\n' > "${destination%%:*}"
        ;;
    *) exit 64 ;;
esac
EOF
cat > "$fetch_bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output=$2; shift 2 ;;
        --proto) shift 2 ;;
        --*) shift ;;
        *) url=$1; shift ;;
    esac
done
printf '%s\n' "$url" >> "$TEST_CURL_LOG"
case "$url" in
    */tailscale_*_amd64.tgz) cp "$TEST_FIXTURES/tailscale.tgz" "$output" ;;
    */licenses/tailscale.md) cp "$TEST_FIXTURES/licenses.md" "$output" ;;
    */netbird_*_linux_amd64.tar.gz)
        cp "$TEST_FIXTURES/netbird.tar.gz" "$output"
        [ "${TEST_TAMPER_NETBIRD:-false}" = false ] || printf 'tampered\n' >> "$output"
        ;;
    *) exit 22 ;;
esac
EOF
chmod 0755 "$fetch_bin/skopeo" "$fetch_bin/curl"
technitium_digest=$(awk -F= '$1 == "TECHNITIUM_AMD64_DIGEST" { print $2 }' "$repo_root/build/locks/sources.env")
run_fetch() {
    world=$1
    cache=$2
    shift 2
    : > "$overlay/curl.log"
    env PATH="$fetch_bin:$PATH" TEST_CURL_LOG="$overlay/curl.log" TEST_FIXTURES="$fixtures" \
        TEST_TECHNITIUM_DIGEST="$technitium_digest" DEVICE_OS_WORLD="$world" \
        DNS_APPLIANCE_CACHE_DIR="$cache" "$@" \
        "$tree/engine/installer/dns-image/fetch-locked-sources" > "$overlay/fetch.log" 2>&1
}
netbird_cache_name=netbird-0.82.0-linux-amd64.tar.gz
run_fetch jeonghan-home "$overlay/cache-both" ||
    simulation_fail "dual-overlay fetch failed: $(cat "$overlay/fetch.log")"
for cached in tailscale-1.104.1-amd64.tgz tailscale-1.104.1-dependency-licenses.md "$netbird_cache_name"; do
    [ -s "$overlay/cache-both/$cached" ] || simulation_fail "dual-overlay fetch did not cache $cached"
done
jq -e '
  .overlays == ["tailscale","netbird"] and
  [.components[].id] == ["technitium-oci","tailscale-archive","tailscale-dependency-report","netbird-archive"] and
  (.components[] | select(.id == "netbird-archive") | .version) == "0.82.0"
' "$overlay/cache-both/component-source-evidence.json" >/dev/null ||
    simulation_fail "dual-overlay source evidence is incomplete"
run_fetch jeonghan-home "$overlay/cache-both" || simulation_fail "verified cache was not reusable"
[ ! -s "$overlay/curl.log" ] || simulation_fail "a verified cache was downloaded again"

run_fetch netbird-home "$overlay/cache-netbird" ||
    simulation_fail "NetBird-only fetch failed: $(cat "$overlay/fetch.log")"
[ -s "$overlay/cache-netbird/$netbird_cache_name" ] || simulation_fail "NetBird-only fetch missed NetBird"
if grep -q tailscale "$overlay/curl.log" ||
    find "$overlay/cache-netbird" -name 'tailscale*' | grep -q .; then
    simulation_fail "NetBird-only fetch downloaded Tailscale"
fi
jq -e '.overlays == ["netbird"] and [.components[].id] == ["technitium-oci","netbird-archive"]' \
    "$overlay/cache-netbird/component-source-evidence.json" >/dev/null ||
    simulation_fail "NetBird-only source evidence names unselected components"

run_fetch tailscale-home "$overlay/cache-tailscale" ||
    simulation_fail "Tailscale-only fetch failed: $(cat "$overlay/fetch.log")"
if grep -q netbird "$overlay/curl.log" || [ -e "$overlay/cache-tailscale/$netbird_cache_name" ]; then
    simulation_fail "Tailscale-only fetch downloaded NetBird"
fi
jq -e '.overlays == ["tailscale"] and
  [.components[].id] == ["technitium-oci","tailscale-archive","tailscale-dependency-report"]' \
    "$overlay/cache-tailscale/component-source-evidence.json" >/dev/null ||
    simulation_fail "Tailscale-only source evidence names unselected components"

if run_fetch netbird-home "$overlay/cache-tampered" TEST_TAMPER_NETBIRD=true; then
    simulation_fail "a NetBird download with the wrong digest was promoted"
fi
[ ! -e "$overlay/cache-tampered/$netbird_cache_name" ] ||
    simulation_fail "a rejected NetBird download reached the cache"
[ -z "$(find "$overlay/cache-tampered" -name '*.partial*' -print)" ] ||
    simulation_fail "a rejected NetBird download left a partial file"
printf 'tampered\n' >> "$overlay/cache-netbird/$netbird_cache_name"
if run_fetch netbird-home "$overlay/cache-netbird"; then
    simulation_fail "a tampered cached NetBird archive was accepted"
fi
if run_fetch missing-home "$overlay/cache-unresolved"; then
    simulation_fail "fetch proceeded without a resolvable World"
fi
[ ! -s "$overlay/curl.log" ] || simulation_fail "fetch downloaded before resolving the World"

# Only the readiness inputs of the selected overlays are required.
readiness() {
    env DNS_APPLIANCE_CACHE_DIR="$overlay/empty-cache" DNS_APPLIANCE_ARTIFACT_DIR="$overlay/no-artifacts" \
        "$@" "$repo_root/dns-image/check-readiness" > "$overlay/readiness.json" 2>/dev/null || true
}
readiness DEVICE_OS_WORLD=jeonghan-home
jq -e --arg netbird "$netbird_cache_name" '
  (.blockers | index("missing locked DNS build input " + $netbird)) != null and
  (.blockers | index("missing locked DNS build input tailscale-1.104.1-amd64.tgz")) != null and
  (.blockers | index("missing locked DNS build input tailscale-1.104.1-dependency-licenses.md")) != null
' "$overlay/readiness.json" >/dev/null || simulation_fail "readiness does not require every selected overlay input"
readiness DEVICE_OS_WORLD=missing-home
jq -e '(.blockers | index("World overlay selection cannot be resolved")) != null and
  ([.blockers[] | select(test("tailscale|netbird"))] | length) == 0' "$overlay/readiness.json" >/dev/null ||
    simulation_fail "readiness did not block an unresolvable overlay selection"

# Build records follow the selection: registry, manifest and SBOM.
records=$overlay/records
mkdir -p "$records/inputs"
for input in dns-appliance.iso technitium tailscale report netbird closure snapshot; do
    printf '%s bytes\n' "$input" > "$records/inputs/$input"
done
printf '%s\n' 'bind9-dnsutils=1:9.20.15-1' 'zstd=1.5.7+dfsg-1' > "$records/inputs/packages"
render_records() {
    selection=$1
    output=$2
    shift 2
    printf '%b' "$selection" > "$records/inputs/overlays"
    mkdir -p "$output"
    "$repo_root/dns-image/render-build-records" --artifact-dir "$output" \
        --iso "$records/inputs/dns-appliance.iso" --install-mode guided --overlays "$records/inputs/overlays" \
        --technitium-archive "$records/inputs/technitium" \
        --closure-manifest "$records/inputs/closure" --packages "$records/inputs/packages" \
        --source-revision "$(printf 'a%.0s' $(seq 40))" --source-snapshot "$records/inputs/snapshot" \
        "$@" > "$records/render.log" 2>&1
}
tailscale_inputs="--tailscale-archive $records/inputs/tailscale --tailscale-report $records/inputs/report"
netbird_inputs="--netbird-archive $records/inputs/netbird"
# shellcheck disable=SC2086
render_records 'tailscale\nnetbird\n' "$records/both" $tailscale_inputs $netbird_inputs ||
    simulation_fail "dual-overlay records were not rendered: $(cat "$records/render.log")"
# shellcheck disable=SC2086
render_records 'tailscale\n' "$records/tailscale" $tailscale_inputs ||
    simulation_fail "Tailscale-only records were not rendered: $(cat "$records/render.log")"
# shellcheck disable=SC2086
render_records 'netbird\n' "$records/netbird" $netbird_inputs ||
    simulation_fail "NetBird-only records were not rendered: $(cat "$records/render.log")"
jq -e --arg netbird "$(digest_of "$records/inputs/netbird")" '
  .overlays == ["tailscale","netbird"] and .netbird_version == "0.82.0" and
  .netbird_archive_sha256 == $netbird and .tailscale_version == "1.104.1" and
  [.components[].id] == ["debian-package-closure","technitium-oci","tailscale-archive","tailscale-dependency-report","netbird-archive","repository-source-snapshot"]
' "$records/both/build-manifest.json" >/dev/null || simulation_fail "dual-overlay manifest is incomplete"
jq -e '.overlays == ["netbird"] and (has("tailscale_version") | not) and
  (has("tailscale_archive_sha256") | not) and
  [.components[].id] == ["debian-package-closure","technitium-oci","netbird-archive","repository-source-snapshot"]
' "$records/netbird/build-manifest.json" >/dev/null || simulation_fail "NetBird-only manifest names Tailscale"
jq -e '.overlays == ["tailscale"] and (has("netbird_version") | not) and (has("netbird_archive_sha256") | not)' \
    "$records/tailscale/build-manifest.json" >/dev/null || simulation_fail "Tailscale-only manifest names NetBird"
jq -e '
  .documentDescribes == ["SPDXRef-DebianPackageClosure","SPDXRef-Technitium","SPDXRef-NetBird","SPDXRef-DIYDeviceOSBootstrapForJeonghan"] and
  ([.packages[].SPDXID] | index("SPDXRef-Tailscale")) == null and
  (.packages[] | select(.SPDXID == "SPDXRef-NetBird") |
    .name == "netbird-linux-static" and .versionInfo == "0.82.0" and
    .licenseDeclared == "BSD-3-Clause" and .licenseConcluded == "NOASSERTION")
' "$records/netbird/sbom.spdx.json" >/dev/null || simulation_fail "NetBird-only SBOM is wrong"
jq -e '
  .documentDescribes == ["SPDXRef-DebianPackageClosure","SPDXRef-Technitium","SPDXRef-Tailscale","SPDXRef-TailscaleDependencyReport","SPDXRef-DIYDeviceOSBootstrapForJeonghan"] and
  ([.packages[].SPDXID] | index("SPDXRef-NetBird")) == null
' "$records/tailscale/sbom.spdx.json" >/dev/null || simulation_fail "Tailscale-only SBOM is wrong"
python3 - "$repo_root/schemas" "$records" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

schemas, records = Path(sys.argv[1]), Path(sys.argv[2])
for name, schema in (("build-manifest.json", "dns-build-manifest.schema.json"),
                     ("component-redistribution-registry.json", "component-redistribution-registry.schema.json")):
    validator = Draft202012Validator(json.loads((schemas / schema).read_text()))
    for selection in ("both", "tailscale", "netbird"):
        errors = list(validator.iter_errors(json.loads((records / selection / name).read_text())))
        if errors:
            sys.exit(f"{selection} {name} violates {schema}: {errors[0].message}")
PY
for selection in both tailscale netbird; do
    "$repo_root/build/verify-distribution-contracts" \
        --registry "$records/$selection/component-redistribution-registry.json" \
        --build-manifest "$records/$selection/build-manifest.json" \
        --sbom "$records/$selection/sbom.spdx.json" >/dev/null ||
        simulation_fail "$selection build records do not verify"
done
reject_records() {
    description=$1
    shift
    rm -rf "$records/rejected"
    if render_records "$@"; then
        simulation_fail "records rendered for $description"
    fi
    [ ! -e "$records/rejected/build-manifest.json" ] ||
        simulation_fail "a manifest was left behind for $description"
}
# shellcheck disable=SC2086
reject_records "an unselected NetBird archive" 'tailscale\n' "$records/rejected" $tailscale_inputs $netbird_inputs
# shellcheck disable=SC2086
reject_records "a missing NetBird archive" 'tailscale\nnetbird\n' "$records/rejected" $tailscale_inputs
# shellcheck disable=SC2086
reject_records "an unselected Tailscale archive" 'netbird\n' "$records/rejected" $tailscale_inputs $netbird_inputs
# shellcheck disable=SC2086
reject_records "a Tailscale archive without its report" 'tailscale\n' "$records/rejected" \
    --tailscale-archive "$records/inputs/tailscale"
# shellcheck disable=SC2086
reject_records "a reversed selection" 'netbird\ntailscale\n' "$records/rejected" $tailscale_inputs $netbird_inputs
# shellcheck disable=SC2086
reject_records "an unknown overlay" 'wireguard\n' "$records/rejected" $netbird_inputs

# A DNS image is used only with the World it was built for. The build
# manifest's overlays are compared with the World's as a set.
agreement=$overlay/agreement
mkdir -p "$agreement"
selection_tool=$tree/engine/installer/dns-image/overlay-selection
cp -p "$repo_root/dns-image/overlay-selection" "$selection_tool"
jq 'del(.overlays)' "$records/both/build-manifest.json" > "$agreement/no-overlays.json"
jq '.overlays = ["netbird","tailscale"]' "$records/both/build-manifest.json" > "$agreement/reordered.json"
for case_name in "both|tailscale\nnetbird" "tailscale|tailscale" "netbird|netbird"; do
    "$selection_tool" manifest "$records/${case_name%%|*}/build-manifest.json" > "$agreement/selection" ||
        simulation_fail "the ${case_name%%|*} manifest selection was rejected"
    [ "$(cat "$agreement/selection")" = "$(printf '%b' "${case_name#*|}")" ] ||
        simulation_fail "the ${case_name%%|*} manifest selection was misread"
done
"$selection_tool" manifest "$agreement/reordered.json" > "$agreement/selection" ||
    simulation_fail "a manifest selection was not compared as a set"
[ "$(cat "$agreement/selection")" = "$(printf 'tailscale\nnetbird')" ] ||
    simulation_fail "a reordered manifest selection was not canonicalized"
if "$selection_tool" manifest "$agreement/no-overlays.json" > /dev/null 2> "$agreement/selection.err"; then
    simulation_fail "a manifest without overlays was accepted"
fi
grep -q 'DNS build manifest has no overlays' "$agreement/selection.err" ||
    simulation_fail "a manifest without overlays was not named as such"
for invalid in '[]' '["wireguard"]' '["tailscale","tailscale"]' '"tailscale"' 'null'; do
    jq --argjson overlays "$invalid" '.overlays = $overlays' "$records/both/build-manifest.json" \
        > "$agreement/invalid.json"
    if "$selection_tool" manifest "$agreement/invalid.json" > /dev/null 2>&1; then
        simulation_fail "manifest overlays $invalid were accepted"
    fi
done

agree_with_world() {
    DEVICE_OS_WORLD=$1 "$selection_tool" agree "$2" > "$agreement/agree.out" 2> "$agreement/agree.err"
}
expect_agreement() {
    agree_with_world "$1" "$2" ||
        simulation_fail "World $1 rejected the matching manifest $2: $(cat "$agreement/agree.err")"
}
expect_disagreement() {
    if agree_with_world "$1" "$2"; then
        simulation_fail "World $1 accepted the manifest $2"
    fi
    grep -q -F "$3" "$agreement/agree.err" ||
        simulation_fail "the refusal for World $1 does not name both selections: $(cat "$agreement/agree.err")"
}
expect_agreement jeonghan-home "$records/both/build-manifest.json"
[ "$(cat "$agreement/agree.out")" = "$(printf 'tailscale\nnetbird')" ] ||
    simulation_fail "an agreeing selection was not reported"
expect_agreement reverse-home "$records/both/build-manifest.json"
expect_agreement jeonghan-home "$agreement/reordered.json"
expect_agreement tailscale-home "$records/tailscale/build-manifest.json"
expect_agreement netbird-home "$records/netbird/build-manifest.json"
expect_disagreement tailscale-home "$records/both/build-manifest.json" \
    'DNS image overlays (tailscale, netbird) differ from the World overlays (tailscale)'
expect_disagreement jeonghan-home "$records/tailscale/build-manifest.json" \
    'DNS image overlays (tailscale) differ from the World overlays (tailscale, netbird)'
expect_disagreement netbird-home "$records/tailscale/build-manifest.json" \
    'DNS image overlays (tailscale) differ from the World overlays (netbird)'
expect_disagreement jeonghan-home "$agreement/no-overlays.json" 'DNS build manifest has no overlays'
if agree_with_world missing-home "$records/both/build-manifest.json"; then
    simulation_fail "agreement was accepted without a resolvable World"
fi

# A World plan or a resolved Catalog that embeds one supplies the selection.
agree_with_plan() {
    printf '%s\n' "$2" > "$agreement/plan.json"
    "$selection_tool" agree "$1" "$agreement/plan.json" > "$agreement/agree.out" 2> "$agreement/agree.err"
}
agree_with_plan "$records/netbird/build-manifest.json" '{"world":{"slug":"x"},"overlays":["netbird"]}' ||
    simulation_fail "a matching World plan was rejected"
agree_with_plan "$records/tailscale/build-manifest.json" \
    '{"catalog":{},"world":{"world":{"slug":"x"},"media":{"id":"dns-install"},"overlays":["tailscale"]}}' ||
    simulation_fail "a matching resolved Catalog was rejected"
if agree_with_plan "$records/both/build-manifest.json" '{"world":{"slug":"x"},"overlays":["netbird"]}'; then
    simulation_fail "a World plan with fewer overlays was accepted"
fi
grep -q -F 'DNS image overlays (tailscale, netbird) differ from the World overlays (netbird)' \
    "$agreement/agree.err" || simulation_fail "a plan refusal does not name both selections"
if agree_with_plan "$records/netbird/build-manifest.json" \
    '{"world":{"world":{"slug":"x"},"media":{"id":"dns-install"},"overlays":["tailscale","netbird"]}}'; then
    simulation_fail "a resolved Catalog with more overlays was accepted"
fi
for plan in '{"overlays":[]}' '{"overlays":["wireguard"]}' '{"world":{"slug":"x"}}' '{}' \
    '{"world":{"world":{"slug":"x"},"media":{"id":"dns-install"}}}' 'null'; do
    if agree_with_plan "$records/both/build-manifest.json" "$plan"; then
        simulation_fail "agreement accepted the World selection $plan"
    fi
done

# Readiness blocks a DNS build whose overlays differ from the World's.
cp -p "$repo_root/dns-image/check-readiness" "$tree/engine/installer/dns-image/"
tree_readiness() {
    rm -rf "$agreement/artifacts"
    mkdir -p "$agreement/artifacts"
    cp "$2" "$agreement/artifacts/build-manifest.json"
    env DEVICE_OS_WORLD="$1" DNS_APPLIANCE_CACHE_DIR="$overlay/empty-cache" \
        DNS_APPLIANCE_ARTIFACT_DIR="$agreement/artifacts" \
        "$tree/engine/installer/dns-image/check-readiness" > "$agreement/readiness.json" 2>/dev/null || true
}
tree_readiness jeonghan-home "$records/both/build-manifest.json"
jq -e '(.passed | index("DNS image overlays match the World (tailscale, netbird)")) != null and
  ([.blockers[] | select(test("overlays"))] | length) == 0' "$agreement/readiness.json" >/dev/null ||
    simulation_fail "readiness did not accept a DNS build for the World's overlays"
tree_readiness tailscale-home "$records/both/build-manifest.json"
jq -e '(.blockers | index("DNS image overlays (tailscale, netbird) differ from the World overlays (tailscale); rebuild the DNS image for this World")) != null and .ready == false' \
    "$agreement/readiness.json" >/dev/null ||
    simulation_fail "readiness accepted a DNS build with more overlays than the World"
tree_readiness jeonghan-home "$records/netbird/build-manifest.json"
jq -e '(.blockers | index("DNS image overlays (netbird) differ from the World overlays (tailscale, netbird); rebuild the DNS image for this World")) != null' \
    "$agreement/readiness.json" >/dev/null ||
    simulation_fail "readiness accepted a DNS build with fewer overlays than the World"
tree_readiness jeonghan-home "$agreement/no-overlays.json"
jq -e '[.blockers[] | select(startswith("DNS build manifest has no overlays"))] | length == 1' \
    "$agreement/readiness.json" >/dev/null ||
    simulation_fail "readiness accepted a DNS build manifest without overlays"

# Both Linux writers accept every selection shape, carry only the selected
# overlays' fields and licenses, and refuse a disagreeing or overlay-less
# manifest before they inspect any target.
writer_bin=$agreement/bin
mkdir -p "$writer_bin"
printf '#!/bin/sh\necho Linux\n' > "$writer_bin/uname"
printf '#!/bin/sh\necho 0\n' > "$writer_bin/id"
for command_name in lsblk findmnt sfdisk blockdev udevadm mkfs.exfat mkfs.vfat blkid; do
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nprintf "%%s\\n" "$(basename "$0") $*" >> "$TEST_COMMAND_LOG"\nexit 99\n' \
        > "$writer_bin/$command_name"
done
# The writers refuse uncommitted source changes; this simulation runs from a
# working copy, so only that comparison is answered here.
printf '#!/bin/sh\ncase " $* " in *" diff "*) exit 0 ;; esac\nexec %s "$@"\n' "$(command -v git)" \
    > "$writer_bin/git"
chmod 0755 "$writer_bin"/*
ruby "$monorepo_root/engine/world/bin/resolve-world" --output "$agreement/world.json"
DEVICE_MEDIA_WORLD_PLAN=$agreement/world.json USB_MEDIA_CATALOG=$agreement/world-catalog.json \
    "$repo_root/usb-media/resolve-catalog" >/dev/null
writer_cache=$agreement/cache
mkdir -p "$writer_cache"
bootloader_name=$(jq -er '.bootloader.source.filename' "$agreement/world-catalog.json")
printf 'bootloader fixture\n' > "$writer_cache/$bootloader_name"
jq --arg digest "$(digest_of "$writer_cache/$bootloader_name")" '.bootloader.source.sha256 = $digest' \
    "$agreement/world-catalog.json" > "$agreement/world-catalog.next"
mv "$agreement/world-catalog.next" "$agreement/world-catalog.json"
jq -e '[.entries[].profile_adapter] == ["dns-appliance"] and .world.overlays == ["tailscale","netbird"]' \
    "$agreement/world-catalog.json" >/dev/null || simulation_fail "the writer World catalog is unexpected"
cp -R "$records/both" "$agreement/no-overlays"
cp "$agreement/no-overlays.json" "$agreement/no-overlays/build-manifest.json"
usb_writer() {
    world_overlays=$1
    manifest_dir=$2
    jq --argjson overlays "$world_overlays" '.world.overlays = $overlays' \
        "$agreement/world-catalog.json" > "$agreement/catalog.json"
    : > "$agreement/commands.log"
    rm -f "$agreement/decision.json"
    set +e
    env PATH="$writer_bin:$PATH" TEST_COMMAND_LOG="$agreement/commands.log" \
        USB_MEDIA_CACHE_DIR="$writer_cache" DEVICE_OS_LICENSE_DECISION_OUTPUT="$agreement/decision.json" \
        "$repo_root/usb-media/write-usb-linux" --device /dev/not-a-device --catalog "$agreement/catalog.json" \
        --runtime-artifact "dns-appliance=$records/inputs/dns-appliance.iso" \
        --runtime-manifest "dns-appliance=$manifest_dir/build-manifest.json" \
        > "$agreement/writer.out" 2> "$agreement/writer.err"
    writer_status=$?
    set -e
    [ ! -s "$agreement/commands.log" ] ||
        simulation_fail "the Ventoy writer inspected a target during $manifest_dir: $(cat "$agreement/commands.log")"
}
dns_writer() {
    manifest_dir=$1
    : > "$agreement/commands.log"
    set +e
    env PATH="$writer_bin:$PATH" TEST_COMMAND_LOG="$agreement/commands.log" \
        "$repo_root/dns-image/write-usb-linux" --device /dev/not-a-device \
        --iso "$records/inputs/dns-appliance.iso" --manifest "$manifest_dir/build-manifest.json" \
        --registry "$manifest_dir/component-redistribution-registry.json" \
        --sbom "$manifest_dir/sbom.spdx.json" --confirm 'ERASE /dev/not-a-device' \
        > "$agreement/writer.out" 2> "$agreement/writer.err"
    writer_status=$?
    set -e
    [ ! -s "$agreement/commands.log" ] ||
        simulation_fail "the DNS writer inspected a target during $manifest_dir: $(cat "$agreement/commands.log")"
}
# An accepted manifest reaches only the block-device check of the absent target.
for case_name in '["tailscale","netbird"]|both' '["tailscale"]|tailscale' '["netbird"]|netbird' \
    '["netbird","tailscale"]|both'; do
    usb_writer "${case_name%%|*}" "$records/${case_name#*|}"
    { [ "$writer_status" -eq 2 ] && [ -s "$agreement/decision.json" ]; } ||
        simulation_fail "the Ventoy writer refused the ${case_name#*|} manifest for World ${case_name%%|*}: $(cat "$agreement/writer.err")"
    jq -e --arg selection "${case_name#*|}" '
      [.selected_artifacts[] | select(.kind == "component") | .id] ==
        (["debian-package-closure","technitium-oci"] +
         (if $selection == "netbird" then [] else ["tailscale-archive","tailscale-dependency-report"] end) +
         (if $selection == "tailscale" then [] else ["netbird-archive"] end) +
         ["repository-source-snapshot"]) and
      all(.selected_artifacts[] | select(.kind == "component"); .sha256 != null)
    ' "$agreement/decision.json" >/dev/null ||
        simulation_fail "the Ventoy writer did not bind the ${case_name#*|} components"
done
for selection in both tailscale netbird; do
    dns_writer "$records/$selection"
    { [ "$writer_status" -eq 2 ] && grep -q '^usage:' "$agreement/writer.err"; } ||
        simulation_fail "the DNS writer refused the $selection manifest: $(cat "$agreement/writer.err")"
done
expect_usb_writer_refusal() {
    usb_writer "$1" "$2"
    { [ "$writer_status" -eq 1 ] && [ ! -e "$agreement/decision.json" ]; } ||
        simulation_fail "the Ventoy writer accepted $2 for World $1"
    grep -q -F "$3" "$agreement/writer.err" ||
        simulation_fail "the Ventoy writer refusal for $2 is unclear: $(cat "$agreement/writer.err")"
}
expect_usb_writer_refusal '["tailscale","netbird"]' "$records/tailscale" \
    'DNS image overlays (tailscale) differ from the World overlays (tailscale, netbird)'
expect_usb_writer_refusal '["netbird"]' "$records/both" \
    'DNS image overlays (tailscale, netbird) differ from the World overlays (netbird)'
expect_usb_writer_refusal '["tailscale","netbird"]' "$agreement/no-overlays" 'DNS build manifest has no overlays'
dns_writer "$agreement/no-overlays"
{ [ "$writer_status" -eq 1 ] && grep -q 'DNS build manifest has no overlays' "$agreement/writer.err"; } ||
    simulation_fail "the DNS writer accepted a manifest without overlays: $(cat "$agreement/writer.err")"
# Fields of an unselected overlay are refused even when the rest agrees.
cp -R "$records/netbird" "$agreement/stray-field"
jq '.tailscale_version = "1.104.1"' "$records/netbird/build-manifest.json" \
    > "$agreement/stray-field/build-manifest.json"
expect_usb_writer_refusal '["netbird"]' "$agreement/stray-field" 'DNS build manifest distribution evidence is invalid'
dns_writer "$agreement/stray-field"
{ [ "$writer_status" -eq 1 ] && grep -q 'DNS distribution manifest is invalid' "$agreement/writer.err"; } ||
    simulation_fail "the DNS writer accepted a field of an unselected overlay"
# An SBOM must describe at least the packages of the selected overlays.
for writer_case in usb dns; do
    cp -R "$records/tailscale" "$agreement/short-sbom"
    jq '.packages |= .[0:4]' "$records/tailscale/sbom.spdx.json" > "$agreement/short-sbom/sbom.spdx.json"
    jq --arg digest "$(digest_of "$agreement/short-sbom/sbom.spdx.json")" '.sbom_sha256 = $digest' \
        "$records/tailscale/build-manifest.json" > "$agreement/short-sbom/build-manifest.json"
    if [ "$writer_case" = usb ]; then
        expect_usb_writer_refusal '["tailscale"]' "$agreement/short-sbom" 'DNS SPDX SBOM is malformed'
    else
        dns_writer "$agreement/short-sbom"
        { [ "$writer_status" -eq 1 ] && grep -q 'DNS SPDX SBOM is invalid' "$agreement/writer.err"; } ||
            simulation_fail "the DNS writer accepted an SBOM without the Tailscale packages"
    fi
    rm -rf "$agreement/short-sbom"
done

# The DNS-ENROLL summary and the USB license texts follow the selection.
python3 - "$repo_root/usb-media/write-usb-linux" "$repo_root/dns-image/write-usb-linux" "$agreement" <<'PY'
import pathlib
import re
import sys

usb_writer, dns_writer, output = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
for label, path, names in (("usb", usb_writer, ("installer_summary", "overlay_licenses")),
                           ("dns", dns_writer, ("installer_summary",))):
    source = pathlib.Path(path).read_text()
    for name in names:
        function = re.search(rf"^{name}\(\) \{{\n.*?^\}}", source, re.M | re.S)
        assert function, f"{path} has no {name} function"
        (output / f"{label}-{name}.sh").write_text(
            "set -eu\n" + function.group() + f'\n{name} "$1"\n')
PY
for writer_case in usb dns; do
    for selection in both tailscale netbird; do
        bash "$agreement/$writer_case-installer_summary.sh" "$records/$selection/build-manifest.json" \
            > "$agreement/installer.json"
        jq -e --slurpfile manifest "$records/$selection/build-manifest.json" '
          . as $summary | $manifest[0] as $m |
          (["schema_version","build_id","image_sha256","debian_point_release","technitium_version","technitium_image_digest","overlays"] +
           [$m.overlays[] | (. + "_version"), (. + "_archive_sha256")]) as $fields |
          (keys | sort) == ($fields | sort) and .schema_version == 1 and
          .image_sha256 == $m.iso_sha256 and
          all($fields[] | select(. != "schema_version" and . != "image_sha256"); . as $k | $m[$k] == $summary[$k])
        ' "$agreement/installer.json" >/dev/null ||
            simulation_fail "the $writer_case writer summary does not follow the $selection selection"
    done
done
for case_name in "tailscale|docs/licenses/Tailscale-BSD-3-Clause.txt" \
    "netbird|docs/licenses/NetBird-BSD-3-Clause.txt" \
    "tailscale netbird|docs/licenses/Tailscale-BSD-3-Clause.txt docs/licenses/NetBird-BSD-3-Clause.txt"; do
    licenses=$(bash "$agreement/usb-overlay_licenses.sh" "${case_name%%|*}" | tr '\n' ' ')
    [ "$licenses" = "${case_name#*|} " ] ||
        simulation_fail "the Ventoy writer licenses for ${case_name%%|*} are '$licenses'"
done
if bash "$agreement/usb-overlay_licenses.sh" wireguard > /dev/null 2>&1; then
    simulation_fail "the Ventoy writer named a license for an unknown overlay"
fi

# The appliance installs exactly the embedded selection.
finish=$overlay/finish
make_finish_root() {
    root=$1
    selection=$2
    rm -rf "$root"
    mkdir -p "$root/cdrom/simple-cdd" "$root/run" "$root/tmp" "$root/bin"
    for directory in usr/bin usr/sbin usr/local/sbin lib/systemd/system etc/default etc/sudoers.d \
        etc/sysctl.d etc/systemd/system etc/ssh home/dns-operator var/lib var/log; do
        mkdir -p "$root/target/$directory"
    done
    cp "$installer_dir"/payload/* "$root/cdrom/simple-cdd/"
    cp "$repo_root/build/locks/sources.env" "$root/cdrom/simple-cdd/sources.env"
    for generated in age-recipient technitium.oci.tar enrollment-record.schema.json \
        diy-device-os-bootstrap-for-jeonghan-license.txt license-history.md third-party-notices.md \
        tailscale-license.txt tailscale-dependency-licenses.md netbird-license.txt source.md \
        source-snapshot.tar.gz distribution-policy.json distribution-status.md \
        component-redistribution-registry.schema.json component-review-record.schema.json \
        dns-build-manifest.schema.json dns-final-review-record.schema.json operator-authorized-keys; do
        printf '%s\n' "$generated" > "$root/cdrom/simple-cdd/$generated"
    done
    mkdir -p "$root/stage/tailscale_1.104.1_amd64/systemd"
    for program in tailscale tailscaled; do
        printf '#!/bin/sh\n' > "$root/stage/tailscale_1.104.1_amd64/$program"
        chmod 0755 "$root/stage/tailscale_1.104.1_amd64/$program"
    done
    printf '[Unit]\n' > "$root/stage/tailscale_1.104.1_amd64/systemd/tailscaled.service"
    printf 'FLAGS=\n' > "$root/stage/tailscale_1.104.1_amd64/systemd/tailscaled.defaults"
    tar -czf "$root/cdrom/simple-cdd/tailscale.tgz" -C "$root/stage" tailscale_1.104.1_amd64
    cp "$fixtures/netbird.tar.gz" "$root/cdrom/simple-cdd/netbird.tar.gz"
    for number in 1 2 3; do
        printf 'role=dns0%s\naddress=10.77.5.%s\n' "$number" "$number" \
            > "$root/cdrom/simple-cdd/dns0$number.conf"
    done
    if [ "$selection" != absent ]; then
        printf '%b' "$selection" > "$root/cdrom/simple-cdd/overlays"
    fi
    printf '%s\n' ROLE=dns01 ADDRESS=10.77.5.1 NETMASK=255.255.0.0 GATEWAY=10.77.0.1 \
        DNS_SERVERS=10.77.0.1 DOMAIN=home.arpa LAN_CIDR=10.77.0.0/16 \
        MANAGEMENT_CIDR=10.77.0.0/24 CLUSTER_DOMAIN=home.arpa NIC_NAME=eno1 TARGET_DISK=/dev/sda \
        > "$root/run/install.env"
    cat > "$root/bin/in-target" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FINISH_LOG"
EOF
    chmod 0755 "$root/bin/in-target"
    sed -e "s#/cdrom/#$root/cdrom/#g" -e "s#/target/#$root/target/#g" \
        -e "s#/target #$root/target #g" \
        -e "s#/run/dns-appliance/install.env#$root/run/install.env#g" \
        -e "s#/tmp/dns-appliance-#$root/tmp/dns-appliance-#g" \
        "$installer_dir/scripts/dns-finish-install" > "$root/dns-finish-install"
}
run_finish() {
    root=$finish/$1
    make_finish_root "$root" "$2"
    PATH="$root/bin:$PATH" FINISH_LOG="$root/in-target.log" sh "$root/dns-finish-install" \
        > "$root/finish.log" 2>&1
}
doc=usr/share/doc/diy-device-os-bootstrap-for-jeonghan
run_finish both 'tailscale\nnetbird\n' ||
    simulation_fail "dual-overlay installation failed: $(cat "$finish/both/finish.log")"
[ "$(cat "$finish/both/target/etc/dns-appliance/overlays")" = "$(printf 'tailscale\nnetbird')" ] ||
    simulation_fail "the installed system lost the overlay selection"
for installed in usr/bin/tailscale usr/sbin/tailscaled lib/systemd/system/tailscaled.service \
    usr/bin/netbird etc/systemd/system/netbird.service "$doc/Tailscale-BSD-3-Clause.txt" \
    "$doc/Tailscale-Dependencies.md" "$doc/NetBird-BSD-3-Clause.txt"; do
    [ -e "$finish/both/target/$installed" ] || simulation_fail "dual-overlay install lacks $installed"
done
[ -d "$finish/both/target/var/log/netbird" ] || simulation_fail "NetBird log directory is missing"
cmp -s "$finish/both/target/etc/systemd/system/netbird.service" "$installer_dir/payload/netbird.service" ||
    simulation_fail "the installed NetBird unit is not the repository-owned unit"
grep -qx 'systemctl enable tailscaled.service' "$finish/both/in-target.log" ||
    simulation_fail "tailscaled was not enabled"
grep -qx 'systemctl enable netbird.service' "$finish/both/in-target.log" ||
    simulation_fail "netbird was not enabled"

run_finish netbird 'netbird\n' ||
    simulation_fail "NetBird-only installation failed: $(cat "$finish/netbird/finish.log")"
[ -x "$finish/netbird/target/usr/bin/netbird" ] || simulation_fail "NetBird-only install lacks netbird"
for absent in usr/bin/tailscale usr/sbin/tailscaled lib/systemd/system/tailscaled.service \
    "$doc/Tailscale-BSD-3-Clause.txt" "$doc/Tailscale-Dependencies.md"; do
    [ ! -e "$finish/netbird/target/$absent" ] || simulation_fail "NetBird-only install has $absent"
done
if grep -q tailscale "$finish/netbird/in-target.log"; then
    simulation_fail "NetBird-only install enabled Tailscale"
fi

run_finish tailscale 'tailscale\n' ||
    simulation_fail "Tailscale-only installation failed: $(cat "$finish/tailscale/finish.log")"
for absent in usr/bin/netbird etc/systemd/system/netbird.service "$doc/NetBird-BSD-3-Clause.txt" var/log/netbird; do
    [ ! -e "$finish/tailscale/target/$absent" ] || simulation_fail "Tailscale-only install has $absent"
done
if grep -q netbird "$finish/tailscale/in-target.log"; then
    simulation_fail "Tailscale-only install enabled NetBird"
fi

# The installed firewall covers exactly the selected overlay interfaces, and
# nftables.service stops and reloads only the appliance table.
for case_name in 'both|"tailscale0", "wt0"' 'netbird|"wt0"' 'tailscale|"tailscale0"'; do
    target=$finish/${case_name%%|*}/target
    grep -qxF "        iifname != { ${case_name#*|} } accept" "$target/etc/nftables.conf" ||
        simulation_fail "the ${case_name%%|*} install does not limit exactly its overlay interfaces"
    if grep -q '@@' "$target/etc/nftables.conf"; then
        simulation_fail "the ${case_name%%|*} install left a firewall marker"
    fi
    cmp -s "$installer_dir/payload/nftables-own-table.conf" \
        "$target/etc/systemd/system/nftables.service.d/60-dns-appliance.conf" ||
        simulation_fail "the ${case_name%%|*} install lacks the nftables.service drop-in"
done

# A kernel package's postinst runs /etc/kernel/postinst.d through run-parts.
# The installed hook is run exactly that way, as root in a private mount
# namespace whose /run is a fresh tmpfs, so the marker it writes is the one
# the installed dns-appliance-reboot reads at its default path. A read-only
# /run must not fail the kernel installation. This needs passwordless sudo and
# mount namespaces; without them the check fails, it never skips.
kernel_hook=$finish/both/target/etc/kernel/postinst.d/zz-dns-appliance-reboot-required
[ -f "$kernel_hook" ] || simulation_fail "the installed system has no kernel reboot-required hook"
cmp -s "$installer_dir/payload/dns-appliance-reboot-required" "$kernel_hook" ||
    simulation_fail "the installed kernel hook is not the repository-owned hook"
[ "$(stat -c %a "$kernel_hook")" = 755 ] || simulation_fail "the installed kernel hook is not mode 0755"
for installed in etc/dns-appliance/peers usr/local/sbin/dns-appliance-reboot; do
    [ -e "$finish/both/target/$installed" ] || simulation_fail "the dual-overlay install lacks $installed"
done
hook_bin=$overlay/hook-bin
mkdir -p "$hook_bin"
printf '#!/bin/sh\nprintf "127.0.0.1\\n"\n' > "$hook_bin/dig"
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$SIM_JOURNAL"\n' > "$hook_bin/logger"
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$SIM_REBOOTS"\n' > "$hook_bin/systemctl"
chmod 0755 "$hook_bin/dig" "$hook_bin/logger" "$hook_bin/systemctl"
cat > "$overlay/kernel-hook-check.sh" <<'EOF'
set -eu
hook_dir=$1
reboot=$2
peers=$3
sim_bin=$4
version=6.12.113+deb13-amd64
fail() {
    echo "kernel hook check: $*" >&2
    exit 1
}
kernel_postinst() {
    run-parts --report --exit-on-error --arg="$1" --arg="/boot/vmlinuz-$1" "$hook_dir"
}
window() {
    : > /run/dns-sim/reboots
    env -u DNS_APPLIANCE_REBOOT_REQUIRED_FILE PATH="$sim_bin:$PATH" \
        SIM_JOURNAL=/run/dns-sim/journal SIM_REBOOTS=/run/dns-sim/reboots \
        DNS_APPLIANCE_REBOOT_STATE_DIR=/run/dns-sim/state DNS_APPLIANCE_PEERS_FILE="$peers" \
        "$reboot" window
}

mount -t tmpfs -o mode=0755 tmpfs /run || fail "cannot mount a private /run"
[ -z "$(ls -A /run)" ] || fail "the private /run is not empty"
mkdir /run/dns-sim
window || fail "the reboot window failed before any kernel was installed"
[ ! -s /run/dns-sim/reboots ] || fail "a reboot was issued before any kernel was installed"

(DPKG_MAINTSCRIPT_PACKAGE="linux-image-$version"; export DPKG_MAINTSCRIPT_PACKAGE
    kernel_postinst "$version") || fail "the kernel postinst hooks failed"
[ "$(cat /run/reboot-required)" = '*** System restart required ***' ] ||
    fail "the marker reads '$(cat /run/reboot-required)'"
[ "$(stat -c %a /run/reboot-required)" = 644 ] || fail "the marker is not mode 0644"
[ "$(cat /run/reboot-required.pkgs)" = "linux-image-$version" ] ||
    fail "the package list reads '$(cat /run/reboot-required.pkgs)'"
(DPKG_MAINTSCRIPT_PACKAGE="linux-image-$version"; export DPKG_MAINTSCRIPT_PACKAGE
    kernel_postinst "$version") || fail "the repeated kernel postinst hooks failed"
[ "$(cat /run/reboot-required.pkgs)" = "linux-image-$version" ] ||
    fail "a repeated kernel install duplicated its package: '$(cat /run/reboot-required.pkgs)'"
(unset DPKG_MAINTSCRIPT_PACKAGE; kernel_postinst 6.12.114+deb13-amd64) ||
    fail "the kernel postinst hooks failed without a package name"
[ "$(cat /run/reboot-required.pkgs)" = "$(printf 'linux-image-%s\nlinux-image-6.12.114+deb13-amd64' "$version")" ] ||
    fail "the package list after a second kernel reads '$(cat /run/reboot-required.pkgs)'"
[ "$(ls -A /run | tr '\n' ' ')" = 'dns-sim reboot-required reboot-required.pkgs ' ] ||
    fail "the hook left other files in /run: $(ls -A /run | tr '\n' ' ')"

window || fail "the reboot window failed after the kernel install"
[ "$(cat /run/dns-sim/reboots)" = reboot ] || fail "the reboot guard did not reboot into the new kernel"
grep -q 'rebooting' /run/dns-sim/journal || fail "the reboot was not logged"

mount -t tmpfs -o ro tmpfs /run || fail "cannot mount a read-only /run"
output=$(DPKG_MAINTSCRIPT_PACKAGE="linux-image-$version"; export DPKG_MAINTSCRIPT_PACKAGE
    kernel_postinst "$version" 2>&1) || fail "an unwritable /run failed the kernel installation: $output"
printf '%s\n' "$output" | grep -q 'dns-appliance-reboot-required: cannot write /run/reboot-required' ||
    fail "an unwritable /run was not reported: $output"
[ ! -e /run/reboot-required ] || fail "a marker appeared on a read-only /run"
echo "kernel hook check: passed"
EOF
# The log is written by this unprivileged shell on purpose, so the temporary
# tree stays removable; only the check itself runs as root.
# shellcheck disable=SC2024
sudo -n unshare --mount --propagation private sh "$overlay/kernel-hook-check.sh" \
    "$(dirname "$kernel_hook")" "$finish/both/target/usr/local/sbin/dns-appliance-reboot" \
    "$finish/both/target/etc/dns-appliance/peers" "$hook_bin" > "$overlay/kernel-hook.log" 2>&1 ||
    simulation_fail "the installed kernel hook check failed: $(cat "$overlay/kernel-hook.log")"
grep -qx 'kernel hook check: passed' "$overlay/kernel-hook.log" ||
    simulation_fail "the installed kernel hook check did not complete: $(cat "$overlay/kernel-hook.log")"

for case_name in absent empty unknown reversed duplicate; do
    case "$case_name" in
        absent) selection=absent ;;
        empty) selection='' ;;
        unknown) selection='wireguard\n' ;;
        reversed) selection='netbird\ntailscale\n' ;;
        duplicate) selection='netbird\nnetbird\n' ;;
    esac
    if run_finish "$case_name" "$selection"; then
        simulation_fail "installation accepted a $case_name overlay selection"
    fi
    [ ! -e "$finish/$case_name/target/etc/dns-appliance" ] ||
        simulation_fail "a $case_name overlay selection reached the target before aborting"
done
printf '#!/bin/sh\n' > "$finish/not-netbird"
tar -czf "$finish/no-binary.tar.gz" -C "$finish" not-netbird
make_finish_root "$finish/no-binary" 'netbird\n'
cp "$finish/no-binary.tar.gz" "$finish/no-binary/cdrom/simple-cdd/netbird.tar.gz"
if PATH="$finish/no-binary/bin:$PATH" FINISH_LOG="$finish/no-binary/in-target.log" \
    sh "$finish/no-binary/dns-finish-install" > "$finish/no-binary/finish.log" 2>&1; then
    simulation_fail "installation accepted a NetBird archive without the client"
fi

# The repository-owned unit mirrors `netbird service install` of the pinned
# client: default daemon socket, profile state and log locations.
unit=$installer_dir/payload/netbird.service
grep -qx 'ExecStart=/usr/bin/netbird "service" "run" "--log-level" "info" "--daemon-addr" "unix:///var/run/netbird.sock" "--config" "/var/lib/netbird/default.json" "--log-file" "/var/log/netbird/client.log"' "$unit" ||
    simulation_fail "NetBird unit does not run the daemon with the upstream defaults"
grep -qx 'WantedBy=multi-user.target' "$unit" || simulation_fail "NetBird unit is not installable"
grep -qx 'Environment=SYSTEMD_UNIT=netbird' "$unit" || simulation_fail "NetBird unit lacks its unit name"

# First boot enables exactly the selected overlay daemons.
python3 - "$installer_dir/payload/dns-appliance-firstboot" "$overlay/overlay-units" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
function = re.search(r"^overlay_units\(\) \{\n.*?^\}", source, re.M | re.S)
assert function, "first-boot overlay unit selection is missing"
pathlib.Path(sys.argv[2]).write_text("set -eu\n" + function.group() + '\noverlay_units "$1"\n')
PY
# The literal shell text is matched; it is not expanded here.
# shellcheck disable=SC2016
grep -q -F 'overlay_units "$overlay_selection"' "$installer_dir/payload/dns-appliance-firstboot" ||
    simulation_fail "first boot does not enable the selected overlay units"
if grep -q 'enable --now tailscaled.service' "$installer_dir/payload/dns-appliance-firstboot"; then
    simulation_fail "first boot enables Tailscale regardless of the selection"
fi
for case_name in 'tailscale\n|tailscaled.service' 'netbird\n|netbird.service' \
    'tailscale\nnetbird\n|tailscaled.service netbird.service'; do
    printf '%b' "${case_name%%|*}" > "$overlay/firstboot-selection"
    units=$(bash "$overlay/overlay-units" "$overlay/firstboot-selection" | tr '\n' ' ')
    [ "$units" = "${case_name#*|} " ] || simulation_fail "first boot selected '$units' for ${case_name%%|*}"
done
for content in '' 'wireguard\n' 'netbird\ntailscale\n' 'netbird\nnetbird\n'; do
    printf '%b' "$content" > "$overlay/firstboot-selection"
    if bash "$overlay/overlay-units" "$overlay/firstboot-selection" >/dev/null 2>&1; then
        simulation_fail "first boot accepted overlay selection '$content'"
    fi
done

# The ISO carries every possible overlay payload path; build-image creates
# only the selected ones, and Simple-CDD skips absent extra files.
for listed in generated/overlays generated/tailscale.tgz generated/tailscale-license.txt \
    generated/tailscale-dependency-licenses.md generated/netbird.tar.gz generated/netbird-license.txt \
    ../payload/netbird.service ../payload/nftables.conf ../payload/nftables-own-table.conf \
    ../payload/dns-appliance-reboot-required; do
    grep -qx "$listed" "$installer_dir/simple-cdd/profiles/default.extra" ||
        simulation_fail "default.extra does not list $listed"
done

echo "image builder, offline preparation, boot menus, signed Debian installer fetch, installer package closure, installer glyph, overlay selection, NetBird pin, overlay fetch, build record and overlay installation simulations: passed"
