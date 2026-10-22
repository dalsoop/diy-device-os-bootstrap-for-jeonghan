#!/bin/sh
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

"$repo_root/build/verify-locks" >/dev/null

for file in \
    installer/payload/dns-appliance-firstboot \
    installer/payload/dns-appliance-health \
    installer/payload/dns-appliance-backup \
    installer/payload/dns-appliance-technitium-run \
    installer/fetch-locked-sources \
    installer/disk-identity \
    installer/write-usb-linux \
    management/cluster-bootstrap \
    management/dnsctl \
    management/restore-node \
    management/authorize-reinstall \
    management/network-preflight \
    management/import-enrollment \
    management/collect-backups \
    management/tailscale-enroll \
    ../agent/run \
    ../agent/server.py \
    ../agent/tests/gateway_simulation.py \
    device-os \
    usb-media/fetch-images \
    usb-media/resolve-catalog \
    usb-media/verify-catalog \
    usb-media/render-ventoy-config \
    usb-media/calculate-capacity \
    usb-media/check-license-policy \
    usb-media/build-image \
    usb-media/build-image-linux \
    usb-media/build-image-container \
    usb-media/inspect-targets \
    usb-media/write-usb-linux \
    usb-media/write-image-macos \
    usb-media/render-distribution-record \
    build/verify-distribution-contracts \
    management/dns-appliance-status-monitor/start \
    tests/dns-license-simulation.sh \
    tests/license-policy-simulation.sh \
    tests/media-catalog-simulation.sh \
    tests/image-builder-simulation.sh \
    tests/macos-writer-simulation.sh \
    tests/management-simulation.sh \
    ../world/bin/resolve-world \
    ../world/bin/record-usb-event \
    ../world/tests/usb-event-simulation.rb \
    ../world/tests/world-contract-simulation.rb; do
    [ -x "$repo_root/$file" ] || {
        echo "repository-contract: $file must be executable" >&2
        exit 1
    }
done

for required in \
    installer/inputs/age-recipient.example \
    build/locks/sources.env \
    build/distribution-policy.json \
    schemas/component-redistribution-registry.schema.json \
    schemas/component-review-record.schema.json \
    schemas/dns-build-manifest.schema.json \
    schemas/dns-final-review-record.schema.json \
    schemas/enrollment-record.schema.json \
    schemas/license-check.schema.json \
    schemas/raw-image-manifest.schema.json \
    zones/home.arpa.zone \
    management/tailscale-policy.example.hujson \
    usb-media/composition.json \
    usb-media/distribution-policy.json \
    usb-media/local-entries/dns-appliance.json \
    collections/device-os.json \
    usb-media/guides/dns-inventory.md \
    installer/inventory-wizard \
    ../docs/tracking/decisions/0010-resolve-media-through-declarative-catalog.md \
    ../docs/tracking/decisions/0012-default-to-source-only-releases.md \
    management/dns-appliance-status-monitor/config.json \
    management/dns-appliance-status-monitor/server.py \
    ../agent/AGENTS.md \
    ../agent/README.md \
    ../agent/requirements.lock \
    ../agent/tailscale-policy.example.hujson \
    ../world/world-playbook.yaml \
    ../world/drafts/jeonghan-home/world.yaml \
    ../world/events/README.md \
    ../world/schemas/usb-event.schema.json \
    ../world/schemas/usb-verification.schema.json \
    ../.github/workflows/ci.yml \
    ../.github/workflows/release.yml \
    ../LICENSE \
    ../docs/licenses/LICENSE_HISTORY.md \
    ../docs/licenses/THIRD_PARTY_NOTICES.md \
    ../docs/licenses/Tailscale-BSD-3-Clause.txt; do
    [ -r "$repo_root/$required" ] || {
        echo "repository-contract: missing $required" >&2
        exit 1
    }
done

grep -q '@@LAN_CIDR@@' "$repo_root/installer/payload/nftables.conf"
grep -q '@@MANAGEMENT_CIDR@@' "$repo_root/installer/payload/nftables.conf"
grep -q 'ConditionPathExists=!/var/lib/dns-appliance/COMPLETE' \
    "$repo_root/installer/payload/dns-appliance-firstboot.service"
grep -q 'DNS-ENROLL' "$repo_root/installer/payload/dns-appliance-firstboot"
grep -q 'previous_generation' "$repo_root/installer/scripts/install-gate"
grep -q 'Authorization: Bearer' "$repo_root/installer/payload/dns-appliance-health"
grep -q 'unzip -t' "$repo_root/installer/payload/dns-appliance-backup"
grep -q 'iifname "tailscale0"' "$repo_root/installer/payload/nftables.conf"
grep -q 'preauthorized:true' "$repo_root/management/tailscale-enroll"
grep -q 'TAILSCALE_LICENSES_SHA256' "$repo_root/build/locks/sources.env"
grep -q 'tailscale-dependency-licenses.md' "$repo_root/installer/build-image"
grep -q 'licenseDeclared:"NOASSERTION"' "$repo_root/installer/build-image"
grep -q 'licenseDeclared:"GPL-3.0-only"' "$repo_root/installer/build-image"
grep -q '/usr/share/doc/diy-device-os-bootstrap-for-jeonghan/SOURCE.md' \
    "$repo_root/installer/scripts/dns-finish-install"
grep -q 'preseed/late_command string /bin/sh /cdrom/simple-cdd/dns-finish-install' \
    "$repo_root/installer/simple-cdd/profiles/default.preseed"
[ ! -e "$repo_root/installer/simple-cdd/profiles/dns.postinst" ]
grep -q 'debian-installer/locale string ko_KR.UTF-8' \
    "$repo_root/installer/simple-cdd/profiles/default.preseed"
grep -q 'built ISO is missing /simple-cdd/' "$repo_root/installer/build-image"
grep -q 'exactly one role must have destructive_install_enabled=true' \
    "$repo_root/installer/build-image"
grep -q 'repository bundle tree may not contain symlinks' \
    "$repo_root/usb-media/write-usb-linux"
grep -q 'manifests/LICENSES.SHA256' "$repo_root/usb-media/write-usb-linux"
grep -q 'Source revision:' "$repo_root/usb-media/write-usb-linux"
grep -q 'resolved catalog revision does not match the checkout' \
    "$repo_root/usb-media/write-usb-linux"

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/schemas/enrollment-record.schema.json"
for schema in \
    component-redistribution-registry.schema.json \
    component-review-record.schema.json \
    dns-build-manifest.schema.json \
    dns-final-review-record.schema.json \
    license-check.schema.json; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
        "$repo_root/schemas/$schema"
done
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/schemas/raw-image-manifest.schema.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/management/dns-appliance-status-monitor/config.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/usb-media/composition.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/collections/device-os.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/usb-media/local-entries/dns-appliance.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/../world/schemas/usb-event.schema.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$repo_root/../world/schemas/usb-verification.schema.json"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$repo_root/management/dns-appliance-status-monitor/server.py"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$repo_root/../agent/server.py"
"$repo_root/usb-media/resolve-catalog" >/dev/null
"$repo_root/usb-media/verify-catalog" >/dev/null
"$repo_root/device-os" world plan >/dev/null

grep -q 'runtime-artifact' "$repo_root/README.md"
grep -q 'locked-download' "$repo_root/usb-media/README.md"
grep -q '"kind": "workspace"' "$repo_root/usb-media/composition.json"
grep -q '"path": "catalog"' "$repo_root/usb-media/composition.json"
grep -q 'https://github.com/dalsoop/diy-device-os-bootstrap-for-jeonghan' \
    "$repo_root/usb-media/composition.json"
grep -q '^    burn)$' "$repo_root/device-os"
grep -q '^    burn-image-macos)$' "$repo_root/device-os"
grep -q '^    build-image)$' "$repo_root/device-os"
grep -q '^            burn)$' "$repo_root/device-os"
grep -q '^            burn-image-macos)$' "$repo_root/device-os"
grep -q '^            build-image)$' "$repo_root/device-os"
grep -q './device-os world burn' "$repo_root/../README.md"

ci_workflow=$repo_root/../.github/workflows/ci.yml
release_workflow=$repo_root/../.github/workflows/release.yml
grep -q '^  contracts:$' "$ci_workflow"
grep -q 'python3-jsonschema' "$ci_workflow"
grep -q 'Validate JSON Schema contracts' "$ci_workflow"
for contract in \
    catalog/schemas/media-entry.schema.json \
    catalog/schemas/bootloader.schema.json \
    installer/schemas/component-redistribution-registry.schema.json \
    installer/schemas/component-review-record.schema.json \
    installer/schemas/dns-build-manifest.schema.json \
    installer/schemas/dns-final-review-record.schema.json \
    installer/schemas/license-check.schema.json \
    installer/schemas/raw-image-manifest.schema.json \
    tests/dns-license-simulation.sh \
    tests/license-policy-simulation.sh; do
    grep -q "$contract" "$ci_workflow" || {
        echo "repository-contract: CI does not enforce $contract" >&2
        exit 1
    }
done

grep -q 'license check --mode source-release --json' "$release_workflow"
# GitHub evaluates this expression; the repository check matches it literally.
# shellcheck disable=SC2016
grep -Fq 'path: ${{ runner.temp }}/dns-release-evidence/' "$release_workflow"
grep -q 'prebuilt-distribution' "$release_workflow"
grep -q 'human-only' "$release_workflow"
grep -q 'source-only evidence contains generated media' "$release_workflow"
grep -q 'This workflow does not publish a release' "$release_workflow"
jq -e '
  .source_release.enabled == true and
  .generated_artifacts.enabled == false and
  .prebuilt_release.enabled == false and
  .prebuilt_release.required_github_environment == "prebuilt-distribution"
' "$repo_root/usb-media/distribution-policy.json" >/dev/null
if grep -q -E 'contents:[[:space:]]*write|gh release|create-release|action-gh-release' \
    "$release_workflow"; then
    echo "repository-contract: source-only workflow gained release publication authority" >&2
    exit 1
fi

if grep -q -E 'legacy_dns|--dns-iso|--dns-manifest|burn\|write|burn-image-macos\|write-image-macos' \
    "$repo_root/device-os" "$repo_root/usb-media/write-usb-linux"; then
    echo "repository-contract: removed compatibility alias remains" >&2
    exit 1
fi

if git -C "$repo_root/.." grep -I -n -i -E \
    '(^|[^a-z-])device-os-bootstrap-for-jeonghan|dns-appliance-provisioning|device-install-media|device-os-flasher|device-os-catalog|superusb|homelab-usb|homelab-bootstrap-media|Homelab Bootstrap|homelab-provisioning|Homelab Install & Recovery' \
    -- . ':!installer/tests/repository-contract.sh'; then
    echo "repository-contract: obsolete project name remains" >&2
    exit 1
fi

echo "repository contracts: passed"
