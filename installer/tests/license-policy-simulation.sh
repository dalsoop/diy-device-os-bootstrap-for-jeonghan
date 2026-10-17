#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
checker=$repo_root/usb-media/check-license-policy
distribution_renderer=$repo_root/usb-media/render-distribution-record
writer_bash=$(command -v bash)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

fail() {
    echo "license-policy-simulation: $*" >&2
    exit 1
}

personal=$($checker --mode personal-use --json)
printf '%s\n' "$personal" | jq -e '
  keys == ["blockers","decision","mode","schema_version","selected_artifacts","warnings"] and
  .schema_version == 1 and .mode == "personal-use" and .decision == "allow" and
  .blockers == [] and (.warnings | length > 0) and
  (all(.warnings[]; keys == ["artifact_id","code","message"] and (.artifact_id | type == "string"))) and
  ([.selected_artifacts[].id] | index("ventoy")) != null and
  ([.selected_artifacts[].id] | index("dns-appliance")) != null and
  ([.selected_artifacts[] | select(.kind == "component") | .id] ==
    ["debian-package-closure","technitium-oci","tailscale-archive","tailscale-dependency-report","repository-source-snapshot"]) and
  ([.selected_artifacts[] | select(.id == "dns-appliance") | .kind] ==
    ["runtime-artifact","final-artifact"]) and
  (.warnings | length) == ([.selected_artifacts[] | select(.status == "personal-use-only")] | length) and
  (all(.selected_artifacts[];
    keys == ["id","kind","sha256","status"] and
    (.status == "personal-use-only" or .status == "redistribution-reviewed")))
' >/dev/null || fail "personal-use decision is not fully enumerated"

# Both Linux writers must refuse policy/evidence before target inspection.
USB_MEDIA_CATALOG="$temporary/writer-catalog.json" "$repo_root/usb-media/resolve-catalog" >/dev/null
mock_bin=$temporary/bin
mkdir -p "$mock_bin"
cat > "$mock_bin/uname" <<'EOF'
#!/bin/sh
echo Linux
EOF
cat > "$mock_bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat > "$mock_bin/deny-checker" <<'EOF'
#!/bin/sh
[ -z "${DNS_CHECKER_MARKER:-}" ] || printf 'called\n' > "$DNS_CHECKER_MARKER"
[ -z "${POLICY_CAPTURE:-}" ] || printf '%s\n' "${DEVICE_OS_DISTRIBUTION_POLICY:-}" > "$POLICY_CAPTURE"
exit 1
EOF
chmod +x "$mock_bin/uname" "$mock_bin/id" "$mock_bin/deny-checker"
for command_name in lsblk findmnt sfdisk blockdev udevadm mkfs.exfat mkfs.vfat blkid; do
    cat > "$mock_bin/$command_name" <<'EOF'
#!/bin/sh
printf '%s\n' "$(basename "$0") $*" >> "$TEST_COMMAND_LOG"
exit 99
EOF
    chmod +x "$mock_bin/$command_name"
done
: > "$temporary/writer-commands.log"
if PATH="$mock_bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TEST_COMMAND_LOG="$temporary/writer-commands.log" \
    DEVICE_OS_LICENSE_CHECKER="$mock_bin/deny-checker" \
    "$writer_bash" "$repo_root/usb-media/write-usb-linux" --device /dev/not-a-device \
        --catalog "$temporary/writer-catalog.json" >/dev/null 2>&1; then
    fail "general Linux writer accepted a denied personal-use policy"
fi
[ ! -s "$temporary/writer-commands.log" ] || fail "general Linux writer inspected or modified a target after policy denial"

printf '%s\n' "$personal" > "$temporary/personal.json"
cat > "$mock_bin/allow-checker" <<EOF
#!/bin/sh
[ "\${DEVICE_OS_DISTRIBUTION_POLICY:-}" = "$repo_root/usb-media/distribution-policy.json" ] || exit 88
cat "$temporary/personal.json"
EOF
cat > "$mock_bin/deny-renderer" <<'EOF'
#!/bin/sh
printf 'called\n' > "$RENDERER_MARKER"
exit 1
EOF
chmod +x "$mock_bin/allow-checker" "$mock_bin/deny-renderer"
: > "$temporary/writer-commands.log"
if PATH="$mock_bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TEST_COMMAND_LOG="$temporary/writer-commands.log" \
    DEVICE_OS_DISTRIBUTION_POLICY="$temporary/ambient-policy.json" \
    DEVICE_OS_LICENSE_CHECKER="$mock_bin/allow-checker" \
    DEVICE_OS_DISTRIBUTION_RENDERER="$mock_bin/deny-renderer" \
    RENDERER_MARKER="$temporary/renderer-called" \
    "$writer_bash" "$repo_root/usb-media/write-usb-linux" --device /dev/not-a-device \
        --catalog "$temporary/writer-catalog.json" >"$temporary/writer-output" 2>&1; then
    fail "general Linux writer accepted a denied distribution renderer"
fi
if [ ! -s "$temporary/renderer-called" ]; then
    cat "$temporary/writer-output" >&2
    fail "general Linux writer did not prevalidate the distribution record"
fi
[ ! -s "$temporary/writer-commands.log" ] || fail "renderer denial reached target inspection or write commands"

if $checker --mode prebuilt-release \
    --catalog /missing/catalog.json \
    --artifact ventoy=/missing/ventoy.tar.gz \
    --manifest dns-appliance=/missing/build-manifest.json \
    --review dns-appliance=/missing/final-review.json \
    --release-root /missing/release --json > "$temporary/denied.json" 2>/dev/null; then
    fail "current policy allowed a prebuilt release"
fi
jq -e '
  .decision == "deny" and (.blockers | length > 1) and
  ([.blockers[].code] | index("policy-disabled")) != null and
  ([.blockers[].code] | index("artifact-unreviewed")) != null
' "$temporary/denied.json" >/dev/null || fail "prebuilt denial did not aggregate blockers"

jq '.prebuilt_release.extra = true' "$repo_root/usb-media/distribution-policy.json" > "$temporary/unknown-policy.json"
if DEVICE_OS_DISTRIBUTION_POLICY="$temporary/unknown-policy.json" \
    $checker --mode personal-use --json > "$temporary/malformed.json" 2>/dev/null; then
    fail "unknown policy field was accepted"
fi
jq -e '.decision == "deny" and ([.blockers[].code] | index("policy-disabled")) != null' \
    "$temporary/malformed.json" >/dev/null || fail "malformed policy did not fail closed"

source_result=$($checker --mode source-release --json || true)
printf '%s\n' "$source_result" | jq -e '
  .mode == "source-release" and
  (.selected_artifacts | length == 1) and
  .selected_artifacts[0].kind == "final-artifact" and
  (.selected_artifacts[0].sha256 | test("^[a-f0-9]{64}$")) and
  .selected_artifacts[0].status == "redistribution-reviewed" and
  (all(.blockers[]; keys == ["artifact_id","code","message"] and .artifact_id == null))
' >/dev/null || fail "source-release surface is malformed"

real_git=$(command -v git)
git_mock_bin=$temporary/git-bin
mkdir -p "$git_mock_bin"
cat > "$git_mock_bin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" status --porcelain --untracked-files=no "*) exit 71 ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF
chmod +x "$git_mock_bin/git"
if PATH="$git_mock_bin:/usr/bin:/bin" "$checker" --mode source-release --json > "$temporary/status-failed.json"; then
    fail "source release allowed a failed git status command"
fi
jq -e '.decision == "deny" and
  ([.blockers[].message] | index("Git tracked-status inspection failed")) != null' \
  "$temporary/status-failed.json" >/dev/null || fail "git status failure was not preserved as a blocker"

# Exercise all fail-closed prebuilt evidence paths without enabling publication.
USB_MEDIA_CATALOG="$temporary/reviewed-catalog.json" "$repo_root/usb-media/resolve-catalog" >/dev/null
mkdir -p "$temporary/release" "$temporary/runtime"
cp "$temporary/reviewed-catalog.json" "$temporary/reviewed-catalog.next"
artifact_args=()
while IFS= read -r id; do
    printf '%s\n' "$id bytes" > "$temporary/$id.bin"
    digest=$(sha256sum "$temporary/$id.bin" | awk '{print $1}')
    artifact_args+=(--artifact "$id=$temporary/$id.bin")
    jq --arg id "$id" --arg digest "$digest" '
      def evidence: [
        {kind:"license",url:"https://example.test/license"},
        {kind:"notices",url:"https://example.test/notices"},
        {kind:"corresponding-source",url:"https://example.test/source"},
        {kind:"trademark",url:"https://example.test/trademark"}
      ];
      def obligations: [
        {kind:"license-text",disposition:"bundle-file",location:{scope:"release-bundle",path:"missing-license.txt",sha256:("0"*64)}},
        {kind:"notices",disposition:"embedded-artifact",location:{scope:"artifact",path:"NOTICES.txt",sha256:("1"*64)}},
        {kind:"corresponding-source",disposition:"not-required"},
        {kind:"trademark",disposition:"not-required"}
      ];
      if .bootloader.id == $id then
        .bootloader.source.sha256 = $digest |
        .bootloader.redistribution = {
          status:"redistribution-reviewed",artifact_version:.bootloader.version,
          artifact_url:.bootloader.source.url,artifact_sha256:$digest,
          reviewed_at:"2026-10-17",reviewer:"fixture",evidence:evidence,obligations:obligations
        }
      else
        .entries |= map(if .id == $id then
          .source.sha256 = $digest |
          .redistribution = {
            status:"redistribution-reviewed",artifact_version:(.version // "fixture"),
            artifact_url:(.source.url // "https://example.test/runtime"),artifact_sha256:$digest,
            reviewed_at:"2026-10-17",reviewer:"fixture",evidence:evidence,obligations:obligations
          }
        else . end)
      end
    ' "$temporary/reviewed-catalog.next" > "$temporary/reviewed-catalog.swap"
    mv "$temporary/reviewed-catalog.swap" "$temporary/reviewed-catalog.next"
done < <(jq -r '.bootloader.id, (.entries[] | select(.source.kind == "locked-download") | .id)' "$temporary/reviewed-catalog.json")

printf 'dns bytes\n' > "$temporary/runtime/dns-appliance.iso"
dns_digest=$(sha256sum "$temporary/runtime/dns-appliance.iso" | awk '{print $1}')
artifact_args+=(--artifact "dns-appliance=$temporary/runtime/dns-appliance.iso")
cat > "$temporary/runtime/component-redistribution-registry.json" <<EOF
{"schema_version":1,"artifact_id":"dns-appliance","components":[
 {"id":"debian-package-closure","version":"1","digest":{"algorithm":"sha256","value":"$(printf '2%.0s' {1..64})"},"redistribution":{"status":"personal-use-only"}},
 {"id":"technitium-oci","version":"1","digest":{"algorithm":"sha256","value":"$(printf '3%.0s' {1..64})"},"source_identity":{"kind":"oci-digest","value":"sha256:$(printf '4%.0s' {1..64})"},"redistribution":{"status":"personal-use-only"}},
 {"id":"tailscale-archive","version":"1","digest":{"algorithm":"sha256","value":"$(printf '5%.0s' {1..64})"},"redistribution":{"status":"personal-use-only"}},
 {"id":"tailscale-dependency-report","version":"1","digest":{"algorithm":"sha256","value":"$(printf '6%.0s' {1..64})"},"redistribution":{"status":"personal-use-only"}},
 {"id":"repository-source-snapshot","version":"1","digest":{"algorithm":"sha256","value":"$(printf '7%.0s' {1..64})"},"redistribution":{"status":"personal-use-only"}}
]}
EOF
cat > "$temporary/runtime/sbom.spdx.json" <<'EOF'
{"spdxVersion":"SPDX-2.3","dataLicense":"CC0-1.0","packages":[],"licenseConcluded":"NOASSERTION"}
EOF
registry_digest=$(sha256sum "$temporary/runtime/component-redistribution-registry.json" | awk '{print $1}')
sbom_digest=$(sha256sum "$temporary/runtime/sbom.spdx.json" | awk '{print $1}')
cat > "$temporary/runtime/build-manifest.json" <<EOF
{"iso_sha256":"$dns_digest","component_registry_sha256":"$registry_digest","sbom_sha256":"$sbom_digest"}
EOF
manifest_digest=$(sha256sum "$temporary/runtime/build-manifest.json" | awk '{print $1}')
cat > "$temporary/runtime/dns-final-review-record.json" <<EOF
{"artifact":{"id":"dns-appliance","sha256":"$(printf '8%.0s' {1..64})"},"inputs":{"component_registry_sha256":"$registry_digest","build_manifest_sha256":"$manifest_digest"},"obligations":[{"kind":"license-text","disposition":"bundle-file","location":{"scope":"release-bundle","path":"missing-dns-license.txt","sha256":"$(printf '9%.0s' {1..64})"}}]}
EOF
jq --arg digest "$dns_digest" '
  .entries |= map(if .id == "dns-appliance" then
    .redistribution = {
      status:"redistribution-reviewed",artifact_version:"fixture",
      artifact_url:"https://example.test/runtime",artifact_sha256:$digest,
      reviewed_at:"2026-10-17",reviewer:"fixture",
      evidence:[
        {kind:"license",url:"https://example.test/license"},
        {kind:"notices",url:"https://example.test/notices"},
        {kind:"corresponding-source",url:"https://example.test/source"},
        {kind:"trademark",url:"https://example.test/trademark"}
      ],
      obligations:[
        {kind:"license-text",disposition:"not-required"},
        {kind:"notices",disposition:"not-required"},
        {kind:"corresponding-source",disposition:"not-required"},
        {kind:"trademark",disposition:"not-required"}
      ]
    }
  else . end) |
  .entries[0].redistribution.artifact_sha256 = ("f"*64)
' "$temporary/reviewed-catalog.next" > "$temporary/reviewed-catalog.json"

if "$checker" --mode prebuilt-release --catalog "$temporary/reviewed-catalog.json" \
    "${artifact_args[@]}" \
    --manifest "dns-appliance=$temporary/runtime/build-manifest.json" \
    --review "dns-appliance=$temporary/runtime/dns-final-review-record.json" \
    --release-root "$temporary/release" --json > "$temporary/evidence-denied.json"; then
    fail "invalid reviewed evidence was accepted"
fi
jq -e '
  (all(.blockers[]; keys == ["artifact_id","code","message"] and
    (.artifact_id == null or (.artifact_id | type == "string")))) and
  (all(.warnings[]; keys == ["artifact_id","code","message"] and
    (.artifact_id == null or (.artifact_id | type == "string")))) and
  (all(.selected_artifacts[];
    .status == "personal-use-only" or .status == "redistribution-reviewed")) and
  ([.selected_artifacts[] | select(.id == "dns-appliance") | .kind] | index("final-artifact")) != null and
  ([.blockers[].code] | index("policy-disabled")) != null and
  ([.blockers[].code] | index("artifact-unreviewed")) != null and
  ([.blockers[].code] | index("review-digest-mismatch")) != null and
  ([.blockers[].code] | index("component-unreviewed")) != null and
  ([.blockers[].code] | index("obligation-unfulfilled")) != null and
  ([.blockers[].code] | index("noassertion-present")) != null and
  ([.blockers[].code] | index("unsupported-artifact-inspection")) != null
' "$temporary/evidence-denied.json" >/dev/null || fail "prebuilt evidence blocker coverage is incomplete"

if "$checker" --mode prebuilt-release --catalog "$temporary/reviewed-catalog.json" \
    "${artifact_args[@]}" \
    --manifest "dns-appliance=$temporary/runtime/missing-build-manifest.json" \
    --review "dns-appliance=$temporary/runtime/dns-final-review-record.json" \
    --release-root "$temporary/release" --json > "$temporary/missing-manifest-denied.json"; then
    fail "prebuilt release allowed a missing runtime manifest"
fi
jq -e '
  ([.blockers[].code] | index("artifact-unreviewed")) != null and
  ([.blockers[].code] | index("component-unreviewed")) != null and
  ([.blockers[].code] | index("noassertion-present")) != null and
  ([.blockers[].code] | index("obligation-unfulfilled")) != null and
  ([.selected_artifacts[] | select(.id == "dns-appliance") | .kind] | index("final-artifact")) != null
' "$temporary/missing-manifest-denied.json" >/dev/null ||
    fail "missing manifest short-circuited independently determinable evidence"

mkdir -p "$temporary/malformed-runtime"
printf '{bad\n' > "$temporary/malformed-runtime/build-manifest.json"
printf '{bad\n' > "$temporary/malformed-runtime/component-redistribution-registry.json"
printf '{bad\n' > "$temporary/malformed-runtime/sbom.spdx.json"
printf '{bad\n' > "$temporary/malformed-runtime/dns-final-review-record.json"
if "$checker" --mode prebuilt-release --catalog "$temporary/reviewed-catalog.json" \
    "${artifact_args[@]}" \
    --manifest "dns-appliance=$temporary/malformed-runtime/build-manifest.json" \
    --review "dns-appliance=$temporary/malformed-runtime/dns-final-review-record.json" \
    --release-root "$temporary/release" --json > "$temporary/malformed-evidence.json"; then
    fail "prebuilt release allowed malformed runtime evidence"
fi
jq -e '
  ([.blockers[].message] | index("runtime build manifest is malformed: dns-appliance")) != null and
  ([.blockers[].message] | index("component registry is malformed: dns-appliance")) != null and
  ([.blockers[].message] | index("SPDX SBOM is malformed: dns-appliance")) != null and
  ([.blockers[].message] | index("final review is malformed: dns-appliance")) != null and
  ([.selected_artifacts[] | select(.kind == "component") | .id] ==
    ["debian-package-closure","technitium-oci","tailscale-archive","tailscale-dependency-report","repository-source-snapshot"])
' "$temporary/malformed-evidence.json" >/dev/null || fail "malformed evidence was not independently aggregated"

mkdir -p "$temporary/missing-runtime"
if "$checker" --mode prebuilt-release --catalog "$temporary/reviewed-catalog.json" \
    "${artifact_args[@]}" \
    --manifest "dns-appliance=$temporary/missing-runtime/build-manifest.json" \
    --review "dns-appliance=$temporary/missing-runtime/dns-final-review-record.json" \
    --release-root "$temporary/release" --json > "$temporary/missing-evidence.json"; then
    fail "prebuilt release allowed missing runtime evidence"
fi
jq -e '
  ([.blockers[].message] | index("runtime build manifest is missing: dns-appliance")) != null and
  ([.blockers[].message] | index("component registry is missing: dns-appliance")) != null and
  ([.blockers[].message] | index("SPDX SBOM is missing: dns-appliance")) != null and
  ([.blockers[].message] | index("exact final review is missing: dns-appliance")) != null and
  ([.selected_artifacts[] | select(.kind == "component")] | length) == 5
' "$temporary/missing-evidence.json" >/dev/null || fail "missing evidence was not independently aggregated"

"$distribution_renderer" "$temporary/denied.json" "$repo_root/usb-media/distribution-policy.json" \
    > "$temporary/DISTRIBUTION.json"
policy_digest=$(sha256sum "$repo_root/usb-media/distribution-policy.json" | awk '{print $1}')
jq -e --arg digest "$policy_digest" '
  keys == ["decision","distribution_policy_sha256","mode","schema_version","selected_artifacts"] and
  .schema_version == 1 and .distribution_policy_sha256 == $digest and
  .mode == "prebuilt-release" and .decision == "deny"
' "$temporary/DISTRIBUTION.json" >/dev/null || fail "USB distribution stamp is malformed"

expect_render_rejected() {
    fixture=$1
    if "$distribution_renderer" "$fixture" "$repo_root/usb-media/distribution-policy.json" >/dev/null 2>&1; then
        fail "renderer accepted malformed nested decision: $fixture"
    fi
}
jq '.selected_artifacts[0].id = "BAD"' "$temporary/denied.json" > "$temporary/bad-artifact-id.json"
expect_render_rejected "$temporary/bad-artifact-id.json"
jq '.selected_artifacts[0].kind = "unknown"' "$temporary/denied.json" > "$temporary/bad-artifact-kind.json"
expect_render_rejected "$temporary/bad-artifact-kind.json"
jq '.blockers[0].code = "BAD_CODE"' "$temporary/denied.json" > "$temporary/bad-finding-code.json"
expect_render_rejected "$temporary/bad-finding-code.json"
jq '.blockers[0].message = 7' "$temporary/denied.json" > "$temporary/bad-finding-message.json"
expect_render_rejected "$temporary/bad-finding-message.json"
jq '.warnings = {}' "$temporary/denied.json" > "$temporary/bad-warning-array.json"
expect_render_rejected "$temporary/bad-warning-array.json"
jq '.selected_artifacts = {}' "$temporary/denied.json" > "$temporary/bad-artifact-array.json"
expect_render_rejected "$temporary/bad-artifact-array.json"
mkdir -p "$temporary/usb/licenses" "$temporary/usb/manifests"
cp "$temporary/DISTRIBUTION.json" "$temporary/usb/licenses/DISTRIBUTION.json"
(cd "$temporary/usb" && find licenses -type f -exec sha256sum {} + | LC_ALL=C sort > manifests/LICENSES.SHA256)
(cd "$temporary/usb" && sha256sum -c manifests/LICENSES.SHA256 >/dev/null) ||
    fail "distribution stamp checksum readback failed"

dns_mock_bin=$temporary/dns-bin
mkdir -p "$dns_mock_bin"
cp "$mock_bin/uname" "$dns_mock_bin/uname"
cp "$mock_bin/id" "$dns_mock_bin/id"
cat > "$dns_mock_bin/lsblk" <<'EOF'
#!/bin/sh
echo "lsblk $*" >> "$TEST_COMMAND_LOG"
exit 99
EOF
chmod +x "$dns_mock_bin/lsblk"
: > "$temporary/dns-writer-commands.log"
if PATH="$dns_mock_bin:/usr/bin:/bin" TEST_COMMAND_LOG="$temporary/dns-writer-commands.log" \
    DNS_CHECKER_MARKER="$temporary/dns-checker-called" POLICY_CAPTURE="$temporary/dns-policy-path" \
    DEVICE_OS_DISTRIBUTION_POLICY="$temporary/ambient-policy.json" \
    DEVICE_OS_LICENSE_CHECKER="$mock_bin/deny-checker" \
    "$repo_root/installer/write-usb-linux" --device /dev/not-a-device \
        --iso "$temporary/runtime/dns-appliance.iso" \
        --manifest "$temporary/runtime/build-manifest.json" \
        --registry "$temporary/runtime/component-redistribution-registry.json" \
        --sbom "$temporary/runtime/sbom.spdx.json" \
        --confirm 'ERASE /dev/not-a-device' >/dev/null 2>&1; then
    fail "DNS Linux writer accepted invalid distribution evidence"
fi
[ -s "$temporary/dns-checker-called" ] || fail "DNS Linux writer did not invoke the shared license checker"
[ "$(cat "$temporary/dns-policy-path")" = "$repo_root/usb-media/distribution-policy.json" ] ||
    fail "DNS Linux writer allowed ambient policy override"
[ ! -s "$temporary/dns-writer-commands.log" ] || fail "DNS Linux writer inspected a target after policy refusal"

echo "license policy simulations: passed"
