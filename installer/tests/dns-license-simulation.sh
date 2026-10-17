#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
validator=$repo_root/build/verify-distribution-contracts
policy=$repo_root/build/distribution-policy.json
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

expect_failure() {
    description=$1
    shift
    if "$@" >"$temporary/rejected.stdout" 2>"$temporary/rejected.stderr"; then
        echo "dns-license-simulation: accepted $description" >&2
        exit 1
    fi
}

policy_sha256=$(sha256_file "$policy")
registry=$temporary/component-registry.json

jq -n \
    --arg policy_sha256 "$policy_sha256" \
    '{
      schema_version: 1,
      policy: {
        id: "dns-composite-image-redistribution-v1",
        sha256: $policy_sha256
      },
      components: [
        {id:"debian-package-closure",version:"13.7.0@20261011T000000Z",digest:{algorithm:"sha256",value:("a"*64)},status:"personal-use-only"},
        {id:"technitium-oci",version:"15.6.1",digest:{algorithm:"sha256",value:("b"*64)},source_identity:{kind:"oci-digest",value:("sha256:"+("1"*64))},status:"personal-use-only"},
        {id:"tailscale-archive",version:"1.104.1",digest:{algorithm:"sha256",value:("c"*64)},status:"personal-use-only"},
        {id:"tailscale-dependency-report",version:"1.104.1",digest:{algorithm:"sha256",value:("d"*64)},status:"personal-use-only"},
        {id:"repository-source-snapshot",version:("e"*40),digest:{algorithm:"sha256",value:("f"*64)},status:"personal-use-only"}
      ]
    }' > "$registry"

"$validator" --registry "$registry" --policy "$policy" >/dev/null

jq 'del(.components[0].version)' "$registry" > "$temporary/malformed.json"
expect_failure "a malformed component" \
    "$validator" --registry "$temporary/malformed.json" --policy "$policy"

jq 'del(.components[4])' "$registry" > "$temporary/missing.json"
expect_failure "a missing component" \
    "$validator" --registry "$temporary/missing.json" --policy "$policy"

jq '.components[4].id = .components[0].id' "$registry" > "$temporary/duplicate.json"
expect_failure "duplicate component IDs" \
    "$validator" --registry "$temporary/duplicate.json" --policy "$policy"

jq '.policy.sha256 = ("0"*64)' "$registry" > "$temporary/digest-mismatch.json"
expect_failure "a distribution-policy digest mismatch" \
    "$validator" --registry "$temporary/digest-mismatch.json" --policy "$policy"

review=$temporary/technitium-review.json
jq -n \
    --slurpfile policy "$policy" \
    '{
      schema_version: 1,
      status: "redistribution-reviewed",
      component_id: "technitium-oci",
      component_version: "15.6.1",
      artifact_sha256: ("b"*64),
      source_identity: {kind:"oci-digest",value:("sha256:"+("1"*64))},
      reviewed_at: "2026-10-17",
      reviewer: "license-reviewer@example.invalid",
      evidence: ($policy[0].evidence_kinds | map({kind:.,url:("https://evidence.example.invalid/"+.+".txt")})),
      obligations: ($policy[0].obligation_kinds | map({kind:.,disposition:"embedded-artifact",location:{scope:"artifact",path:("licenses/"+.+".txt"),sha256:("3"*64)}}))
    }' > "$review"

jq -n '
  ["SPDXRef-DebianPackageClosure","SPDXRef-Technitium","SPDXRef-Tailscale","SPDXRef-TailscaleDependencyReport","SPDXRef-DIYDeviceOSBootstrapForJeonghan"] as $described |
  {
    spdxVersion:"SPDX-2.3",
    dataLicense:"CC0-1.0",
    SPDXID:"SPDXRef-DOCUMENT",
    name:"dns-appliance-installer-dns-test-build",
    documentNamespace:"https://github.com/dalsoop/diy-device-os-bootstrap-for-jeonghan/sbom/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/dns-appliance-installer-dns-test-build",
    creationInfo:{created:"2026-10-17T00:00:00Z",creators:["Tool: dns-license-simulation"]},
    documentDescribes:$described,
    packages:($described | to_entries | map({
      name:("component-"+(.key|tostring)),
      versionInfo:"1.0.0",
      SPDXID:.value,
      downloadLocation:("https://artifacts.example.invalid/"+(.key|tostring)),
      filesAnalyzed:false,
      licenseDeclared:(if .key == 0 then "NOASSERTION" else "GPL-3.0-only" end),
      licenseConcluded:"GPL-3.0-only",
      copyrightText:"Copyright test"
    }))
  }
' > "$temporary/sbom-noassertion.json"

expect_failure "reviewed promotion while the SBOM contains NOASSERTION" \
    "$validator" --registry "$registry" --policy "$policy" \
    --component-review "$review" --sbom "$temporary/sbom-noassertion.json"

jq '.packages[0].licenseDeclared="GPL-3.0-only"' \
    "$temporary/sbom-noassertion.json" > "$temporary/sbom-complete.json"
jq '.artifact_sha256 = ("9"*64)' "$review" > "$temporary/component-digest-mismatch.json"
expect_failure "a component review artifact digest mismatch" \
    "$validator" --registry "$registry" --policy "$policy" \
    --component-review "$temporary/component-digest-mismatch.json" \
    --sbom "$temporary/sbom-complete.json"
jq 'del(.source_identity)' "$review" > "$temporary/component-source-identity-missing.json"
expect_failure "a component review that drops OCI source identity" \
    "$validator" --registry "$registry" --policy "$policy" \
    --component-review "$temporary/component-source-identity-missing.json" \
    --sbom "$temporary/sbom-complete.json"
"$validator" --registry "$registry" --policy "$policy" \
    --component-review "$review" --sbom "$temporary/sbom-complete.json" >/dev/null

reviewed_registry=$temporary/reviewed-registry.json
jq '.components |= map(.status="redistribution-reviewed")' "$registry" > "$reviewed_registry"
registry_sha256=$(sha256_file "$reviewed_registry")
sbom_sha256=$(sha256_file "$temporary/sbom-complete.json")

manifest=$temporary/build-manifest.json
jq -n \
    --arg registry_sha256 "$registry_sha256" \
    --arg policy_sha256 "$policy_sha256" \
    --arg sbom_sha256 "$sbom_sha256" \
    --slurpfile registry "$reviewed_registry" \
    '{
      schema_version: 1,
      artifact_id: "dns-appliance",
      build_id: "dns-test-build",
      iso: "dns-test.iso",
      iso_sha256: ("4"*64),
      distribution_status: "redistribution-reviewed",
      component_registry: "component-redistribution-registry.json",
      component_registry_sha256: $registry_sha256,
      distribution_policy_sha256: $policy_sha256,
      components: ($registry[0].components | map({id,status})),
      sbom: "sbom.spdx.json",
      sbom_sha256: $sbom_sha256,
      debian_point_release: "13.7.0",
      debian_snapshot: "20261011T000000Z",
      technitium_version: "15.6.1",
      technitium_image_digest: ("sha256:"+("1"*64)),
      technitium_archive_sha256: ("b"*64),
      tailscale_version: "1.104.1",
      tailscale_archive_sha256: ("c"*64),
      source_revision: ("e"*40),
      source_repository: "https://github.com/dalsoop/diy-device-os-bootstrap-for-jeonghan",
      source_archive: ("https://github.com/dalsoop/diy-device-os-bootstrap-for-jeonghan/archive/"+("e"*40)+".tar.gz")
    }' > "$manifest"
manifest_sha256=$(sha256_file "$manifest")

final_review=$temporary/final-review.json
jq -n \
    --arg registry_sha256 "$registry_sha256" \
    --arg manifest_sha256 "$manifest_sha256" \
    --slurpfile policy "$policy" \
    '{
      schema_version: 1,
      status: "redistribution-reviewed",
      artifact_id: "dns-appliance",
      artifact_sha256: ("4"*64),
      component_registry_sha256: $registry_sha256,
      build_manifest_sha256: $manifest_sha256,
      reviewed_at: "2026-10-17",
      reviewer: "license-reviewer@example.invalid",
      evidence: ($policy[0].evidence_kinds | map({kind:.,url:("https://evidence.example.invalid/"+.+".txt")})),
      obligations: ($policy[0].obligation_kinds | map({kind:.,disposition:"bundle-file",location:{scope:"release-bundle",path:("licenses/"+.+".txt"),sha256:("6"*64)}}))
    }' > "$final_review"

"$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$final_review" --build-manifest "$manifest" \
    --sbom "$temporary/sbom-complete.json" >/dev/null

incomplete_manifest=$temporary/incomplete-build-manifest.json
jq 'del(.debian_point_release)' "$manifest" > "$incomplete_manifest"
incomplete_manifest_sha256=$(sha256_file "$incomplete_manifest")
jq --arg sha256 "$incomplete_manifest_sha256" '.build_manifest_sha256=$sha256' \
    "$final_review" > "$temporary/incomplete-manifest-final-review.json"
expect_failure "a schema-incomplete build manifest with a matching review hash" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$temporary/incomplete-manifest-final-review.json" \
    --build-manifest "$incomplete_manifest" --sbom "$temporary/sbom-complete.json"

jq 'del(.sbom_sha256)' "$manifest" > "$temporary/unbound-sbom-build-manifest.json"
unbound_manifest_sha256=$(sha256_file "$temporary/unbound-sbom-build-manifest.json")
jq --arg sha256 "$unbound_manifest_sha256" '.build_manifest_sha256=$sha256' \
    "$final_review" > "$temporary/unbound-sbom-final-review.json"
expect_failure "a build manifest without an SBOM digest binding" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$temporary/unbound-sbom-final-review.json" \
    --build-manifest "$temporary/unbound-sbom-build-manifest.json" \
    --sbom "$temporary/sbom-complete.json"

printf '{}\n' > "$temporary/substitute-empty-sbom.json"
expect_failure "an empty substitute SBOM" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$final_review" --build-manifest "$manifest" \
    --sbom "$temporary/substitute-empty-sbom.json"

jq '.name += "-substitute"' "$temporary/sbom-complete.json" \
    > "$temporary/substitute-valid-sbom.json"
expect_failure "a valid-shaped SBOM whose bytes do not match the build manifest" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$final_review" --build-manifest "$manifest" \
    --sbom "$temporary/substitute-valid-sbom.json"

jq 'del(.obligations[3])' "$final_review" > "$temporary/incomplete-final-review.json"
expect_failure "an incomplete final review record" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$temporary/incomplete-final-review.json" \
    --build-manifest "$manifest" --sbom "$temporary/sbom-complete.json"

jq '.component_registry_sha256 = ("7"*64)' "$final_review" \
    > "$temporary/final-digest-mismatch.json"
expect_failure "a final-review registry digest mismatch" \
    "$validator" --registry "$reviewed_registry" --policy "$policy" \
    --final-review "$temporary/final-digest-mismatch.json" \
    --build-manifest "$manifest" --sbom "$temporary/sbom-complete.json"

echo "DNS license simulations: passed"
