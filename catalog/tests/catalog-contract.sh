#!/bin/sh
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
verify=$repo_root/bin/verify-catalog
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

fail() {
    echo "catalog contract simulation: $*" >&2
    exit 1
}

reset_fixture() {
    rm -rf "$temporary/catalog"
    cp -R "$repo_root/catalog" "$temporary/catalog"
}

replace_entry() {
    filter=$1
    jq "$filter" "$temporary/catalog/entries/proxmox-ve.json" > "$temporary/changed.json"
    mv "$temporary/changed.json" "$temporary/catalog/entries/proxmox-ve.json"
}

replace_bootloader() {
    filter=$1
    jq "$filter" "$temporary/catalog/bootloaders/ventoy.json" > "$temporary/changed.json"
    mv "$temporary/changed.json" "$temporary/catalog/bootloaders/ventoy.json"
}

expect_rejected() {
    description=$1
    if DEVICE_MEDIA_CATALOG_ROOT=$temporary "$verify" >/dev/null 2>&1; then
        fail "invalid fixture was accepted: $description"
    fi
}

reviewed_redistribution='{
  "status": "redistribution-reviewed",
  "artifact_version": "9.2-1",
  "artifact_url": "https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso",
  "artifact_sha256": "4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c",
  "reviewed_at": "2026-10-17",
  "reviewer": "catalog-contract-fixture",
  "evidence": [
    {"kind": "license", "url": "https://example.com/license"},
    {"kind": "notices", "url": "https://example.com/notices"},
    {"kind": "corresponding-source", "url": "https://example.com/source"},
    {"kind": "trademark", "url": "https://example.com/trademark"}
  ],
  "obligations": [
    {"kind": "license-text", "disposition": "embedded-artifact", "location": {"scope": "artifact", "path": "licenses/LICENSE.txt", "sha256": "1111111111111111111111111111111111111111111111111111111111111111"}},
    {"kind": "notices", "disposition": "bundle-file", "location": {"scope": "release-bundle", "path": "licenses/NOTICES.txt", "sha256": "2222222222222222222222222222222222222222222222222222222222222222"}},
    {"kind": "corresponding-source", "disposition": "not-required"},
    {"kind": "trademark", "disposition": "not-required"}
  ]
}'

"$verify" >/dev/null

for record in "$repo_root"/catalog/entries/*.json "$repo_root"/catalog/bootloaders/*.json; do
    jq -e '
      .schema_version == 2 and
      .redistribution == {"status": "personal-use-only"}
    ' "$record" >/dev/null ||
        fail "current real record is not personal-use-only: $record"
done

reset_fixture
replace_entry '.source.sha256 = "not-a-digest"'
expect_rejected "malformed source digest"

reset_fixture
jq '.entries[1].id = .entries[0].id' \
    "$temporary/catalog/index.json" > "$temporary/changed.json"
mv "$temporary/changed.json" "$temporary/catalog/index.json"
expect_rejected "duplicate index ID"

reset_fixture
replace_entry 'del(.redistribution)'
expect_rejected "missing redistribution metadata"

reset_fixture
replace_entry '.redistribution = {"status": "unknown"}'
expect_rejected "unknown redistribution status"

reset_fixture
replace_entry '.redistribution.reviewed_at = "2026-10-17"'
expect_rejected "review-only field on personal-use-only record"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution"
DEVICE_MEDIA_CATALOG_ROOT=$temporary "$verify" >/dev/null ||
    fail "complete reviewed fixture was rejected"

reset_fixture
replace_bootloader ".redistribution = $reviewed_redistribution |
    .redistribution.artifact_version = .version |
    .redistribution.artifact_url = .source.url |
    .redistribution.artifact_sha256 = .source.sha256"
DEVICE_MEDIA_CATALOG_ROOT=$temporary "$verify" >/dev/null ||
    fail "complete reviewed bootloader fixture was rejected"

reset_fixture
replace_bootloader ".redistribution = $reviewed_redistribution |
    .redistribution.artifact_version = .version |
    .redistribution.artifact_url = .source.url |
    .redistribution.artifact_sha256 = .source.sha256 |
    .redistribution.artifact_version = \"different\""
expect_rejected "reviewed bootloader artifact identity mismatch"

for field in artifact_version artifact_url artifact_sha256 reviewed_at reviewer evidence obligations; do
    reset_fixture
    replace_entry ".redistribution = $reviewed_redistribution | del(.redistribution.$field)"
    expect_rejected "reviewed record missing $field"
done

for mismatch in \
    '.redistribution.artifact_version = "different"' \
    '.redistribution.artifact_url = "https://example.com/different.iso"' \
    '.redistribution.artifact_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; do
    reset_fixture
    replace_entry ".redistribution = $reviewed_redistribution | $mismatch"
    expect_rejected "reviewed artifact identity mismatch"
done

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.reviewed_at = \"17-10-2026\""
expect_rejected "malformed review date"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.reviewer = \"\""
expect_rejected "empty reviewer"

for kind in license notices corresponding-source trademark; do
    reset_fixture
    replace_entry ".redistribution = $reviewed_redistribution | .redistribution.evidence |= map(select(.kind != \"$kind\"))"
    expect_rejected "missing $kind evidence"
done

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.evidence[0].url = \"http://example.com/license\""
expect_rejected "non-HTTPS evidence URL"

for kind in license-text notices corresponding-source trademark; do
    reset_fixture
    replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations |= map(select(.kind != \"$kind\"))"
    expect_rejected "missing $kind obligation"
done

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[3].kind = \"license-text\""
expect_rejected "duplicate obligation"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[0].disposition = \"unknown\""
expect_rejected "unknown obligation disposition"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[0].location.scope = \"release-bundle\""
expect_rejected "embedded obligation with wrong scope"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[1].location.scope = \"artifact\""
expect_rejected "bundle obligation with wrong scope"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[0].location.path = \"../LICENSE\""
expect_rejected "unsafe obligation path"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[0].location.sha256 = \"BAD\""
expect_rejected "malformed obligation digest"

reset_fixture
replace_entry ".redistribution = $reviewed_redistribution | .redistribution.obligations[2].location = {\"scope\": \"artifact\", \"path\": \"source\", \"sha256\": \"3333333333333333333333333333333333333333333333333333333333333333\"}"
expect_rejected "location on not-required obligation"

for mutation in \
    '.unexpected = true' \
    '.source.command = "run-me"' \
    '.redistribution.unexpected = true' \
    '.redistribution.evidence[0].unexpected = true' \
    '.redistribution.obligations[0].unexpected = true' \
    '.redistribution.obligations[0].location.unexpected = true'; do
    reset_fixture
    replace_entry ".redistribution = $reviewed_redistribution | $mutation"
    expect_rejected "unknown field: $mutation"
done

echo "catalog contract simulations: passed"
