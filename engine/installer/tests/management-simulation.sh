#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
monorepo_root=$(CDPATH='' cd -- "$repo_root/../.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/dns-management-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

pass_count=0
pass() {
    pass_count=$((pass_count + 1))
    echo "PASS $1"
}

mkdir -p "$temporary/bin"
cat > "$temporary/bin/curl" <<'EOF'
#!/bin/sh
case "$*" in
    */api/zones/import*)
        printf '%s\n' "$*" >> "${MOCK_IMPORT_LOG:-/dev/null}"
        for argument in "$@"; do
            case "$argument" in
                file=@*)
                    payload=${argument#file=@}
                    payload=${payload%%;*}
                    [ -z "${MOCK_IMPORT_PAYLOAD:-}" ] || cp "$payload" "$MOCK_IMPORT_PAYLOAD"
                    ;;
            esac
        done
        printf '{"status":"ok","response":{}}\n'
        ;;
    *)
        [ -z "${MOCK_CURL_ARGS:-}" ] || printf '%s\n' "$@" > "$MOCK_CURL_ARGS"
        cat "$MOCK_CURRENT_ZONE"
        ;;
esac
EOF
cat > "$temporary/bin/ping" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$temporary/bin/curl" "$temporary/bin/ping"

printf '%s\n' token > "$temporary/token"
printf '%s\n' test-ca > "$temporary/technitium-ca.pem"
cat > "$temporary/current.zone" <<'EOF'
$ORIGIN home.arpa.
$TTL 300
@ IN SOA dns01.home.arpa. hostmaster.home.arpa. ( 1 3600 600 604800 300 )
@ IN NS dns01.home.arpa.
EOF
cat > "$temporary/desired.zone" <<'EOF'
$ORIGIN home.arpa.
$TTL 300
@ IN SOA dns01.home.arpa. hostmaster.home.arpa. ( 2 3600 600 604800 300 )
@ IN NS dns01.home.arpa.
canary IN A 10.77.9.9
EOF

PATH="$temporary/bin:$PATH" \
MOCK_CURRENT_ZONE="$temporary/current.zone" \
MOCK_CURL_ARGS="$temporary/curl.args" \
TECHNITIUM_TOKEN_FILE="$temporary/token" \
TECHNITIUM_CA_FILE="$temporary/technitium-ca.pem" \
DNSCTL_AUDIT_LOG="$temporary/audit.jsonl" \
    "$repo_root/management/dnsctl" plan "$temporary/desired.zone" \
    > "$temporary/plan.json" 2> "$temporary/plan.diff"
jq -e '.schema_version == 2 and .zone == "home.arpa" and .changed == true and .source_commit == null' \
    "$temporary/plan.json" >/dev/null
grep -q '^+' "$temporary/plan.diff"
jq -e '.action == "plan:home.arpa" and .result == "ok"' \
    "$temporary/audit.jsonl" >/dev/null
pass dnsctl_plan_is_machine_readable_and_audited

grep -Fx -- '--cacert' "$temporary/curl.args" >/dev/null
grep -Fx -- "$temporary/technitium-ca.pem" "$temporary/curl.args" >/dev/null
if grep -Fx -- '--insecure' "$temporary/curl.args" >/dev/null; then
    echo "FAIL dnsctl retained insecure TLS with a configured CA" >&2
    exit 1
fi
pass dnsctl_uses_configured_ca

# plan compares record sets without the SOA and apex NS records, which the
# cluster manages, independent of record order and presentation.
plan_against() {
    PATH="$temporary/bin:$PATH" \
    MOCK_CURRENT_ZONE="$1" \
    TECHNITIUM_TOKEN_FILE="$temporary/token" \
    TECHNITIUM_CA_FILE="$temporary/technitium-ca.pem" \
    DNSCTL_AUDIT_LOG="$temporary/audit.jsonl" \
        "$repo_root/management/dnsctl" plan "$2" \
        > "$temporary/compare.json" 2> "$temporary/compare.diff"
}
expect_plan_rejected() {
    name=$1
    shift
    if plan_against "$@"; then
        echo "FAIL $name: dnsctl plan succeeded" >&2
        exit 1
    fi
    if [ -s "$temporary/compare.json" ]; then
        echo "FAIL $name: dnsctl plan printed a plan before rejecting" >&2
        exit 1
    fi
    pass "$name"
}
cat > "$temporary/rich.zone" <<'EOF'
$ORIGIN home.arpa.
$TTL 300
@ IN SOA dns01.home.arpa. hostmaster.home.arpa. (
    2026110601  ; serial
    3600 600 604800 300 )
@      IN NS dns01.home.arpa.
@      IN NS dns02.home.arpa.
dns01  IN A 10.77.5.1
router IN A 10.77.0.1
mail   IN MX 10 dns01
alias  IN CNAME router
note   IN TXT "a; b"
EOF
cat > "$temporary/export-equivalent.zone" <<'EOF'
; Exported zone file
$ORIGIN home.arpa.

@	3600	IN	SOA	dns01.home.arpa. hostmaster.home.arpa. 9 900 300 604800 900
	3600	IN	NS	dns03.home.arpa.
note.home.arpa.	300	IN	TXT	"a; b"
alias.home.arpa.	300	IN	CNAME	router.home.arpa.
ROUTER.home.arpa.	300	in	a	10.77.0.1
dns01	300	IN	A	10.77.5.1
mail.home.arpa.	300	IN	MX	10 dns01.home.arpa.
EOF
plan_against "$temporary/export-equivalent.zone" "$temporary/rich.zone"
jq -e '.changed == false and .zone == "home.arpa"' "$temporary/compare.json" >/dev/null || {
    echo "FAIL plan reported a change for an export that differs only in SOA, apex NS, order, and presentation" >&2
    cat "$temporary/compare.diff" >&2
    exit 1
}
if grep -q '^[-+][^-+]' "$temporary/compare.diff"; then
    echo "FAIL plan printed a record difference for an equivalent export" >&2
    exit 1
fi
pass dnsctl_plan_ignores_soa_apex_ns_order_and_presentation

sed 's/^ROUTER\.home\.arpa\.	300	/ROUTER.home.arpa.	600	/' \
    "$temporary/export-equivalent.zone" > "$temporary/export-ttl.zone"
plan_against "$temporary/export-ttl.zone" "$temporary/rich.zone"
jq -e '.changed == true' "$temporary/compare.json" >/dev/null
grep -qx -- '-router.home.arpa. 600 IN A 10.77.0.1' "$temporary/compare.diff"
grep -qx -- '+router.home.arpa. 300 IN A 10.77.0.1' "$temporary/compare.diff"
sed 's/10\.77\.0\.1$/10.77.0.2/' "$temporary/export-equivalent.zone" > "$temporary/export-address.zone"
plan_against "$temporary/export-address.zone" "$temporary/rich.zone"
jq -e '.changed == true' "$temporary/compare.json" >/dev/null
grep -qx -- '-router.home.arpa. 300 IN A 10.77.0.2' "$temporary/compare.diff"
cp "$temporary/export-equivalent.zone" "$temporary/export-delegation.zone"
printf 'sub.home.arpa.\t300\tIN\tNS\tns.example.\n' >> "$temporary/export-delegation.zone"
plan_against "$temporary/export-delegation.zone" "$temporary/rich.zone"
jq -e '.changed == true' "$temporary/compare.json" >/dev/null
grep -qx -- '-sub.home.arpa. 300 IN NS ns.example.' "$temporary/compare.diff"
pass dnsctl_plan_detects_real_record_differences

printf '%s\n' '{"status":"error","errorMessage":"No such zone was found"}' > "$temporary/export-error.json"
expect_plan_rejected dnsctl_plan_rejects_an_api_error_as_live_zone \
    "$temporary/export-error.json" "$temporary/rich.zone"
grep -q 'No such zone was found' "$temporary/compare.diff"
cp "$temporary/rich.zone" "$temporary/absolute-apex-ns.zone"
printf '%s\n' 'home.arpa. IN NS dns03.home.arpa.' >> "$temporary/absolute-apex-ns.zone"
expect_plan_rejected dnsctl_plan_rejects_apex_ns_the_import_cannot_strip \
    "$temporary/export-equivalent.zone" "$temporary/absolute-apex-ns.zone"
grep -q 'apex NS records the import cannot strip' "$temporary/compare.diff"
cp "$temporary/rich.zone" "$temporary/include.zone"
printf '%s\n' "\$INCLUDE other.zone" >> "$temporary/include.zone"
expect_plan_rejected dnsctl_plan_rejects_unsupported_zone_directives \
    "$temporary/export-equivalent.zone" "$temporary/include.zone"
grep -qF "unsupported directive \$INCLUDE" "$temporary/compare.diff"

# The repository zones: every static name has exactly one PTR record, and the
# API and canary names have none.
reverse_zone=$monorepo_root/burn-history/dns-reverse-records.zone
printf '%s\n' "\$ORIGIN home.arpa." \
    '@ 3600 IN SOA dns01.home.arpa. hostmaster.home.arpa. 9 900 300 604800 900' \
    > "$temporary/export-empty-forward.zone"
printf '%s\n' "\$ORIGIN 77.10.in-addr.arpa." \
    '@ 3600 IN SOA dns01.home.arpa. hostmaster.home.arpa. 1 900 300 604800 900' \
    '  3600 IN NS dns01.home.arpa.' > "$temporary/export-empty-reverse.zone"
plan_against "$temporary/export-empty-forward.zone" "$monorepo_root/burn-history/dns-records.zone"
jq -e '.zone == "home.arpa" and .changed == true' "$temporary/compare.json" >/dev/null
grep '^+[^+]' "$temporary/compare.diff" > "$temporary/forward.records"
plan_against "$temporary/export-empty-reverse.zone" "$reverse_zone"
jq -e '.zone == "77.10.in-addr.arpa" and .changed == true' "$temporary/compare.json" >/dev/null
grep '^+[^+]' "$temporary/compare.diff" > "$temporary/reverse.records"
python3 - "$temporary/forward.records" "$temporary/reverse.records" <<'PY'
import sys

def records(path):
    return [line[1:].split() for line in open(path, encoding="utf-8")]

forward = records(sys.argv[1])
reverse = records(sys.argv[2])
assert all(record[2] == "IN" and record[3] in ("A", "NS") for record in forward), forward
assert not any(record[3] == "NS" for record in forward), "apex NS left in the forward diff"
addresses = {record[0]: record[4] for record in forward if record[3] == "A"}
expected = {
    "router.home.arpa.": "10.77.0.1", "pve1.home.arpa.": "10.77.0.11",
    "nas-synology1.home.arpa.": "10.77.0.21", "nas-truenas1.home.arpa.": "10.77.0.23",
    "pbs1.home.arpa.": "10.77.0.25", "dns01.home.arpa.": "10.77.5.1",
    "dns02.home.arpa.": "10.77.5.2", "dns03.home.arpa.": "10.77.5.3",
    "dns-api.home.arpa.": "10.77.5.1", "canary.home.arpa.": "10.77.9.9",
}
assert addresses == expected, addresses
assert all(record[3] == "PTR" and record[1] == "300" for record in reverse), reverse
pointers = {}
for owner, _, _, _, target in reverse:
    assert owner.endswith(".77.10.in-addr.arpa."), owner
    assert owner not in pointers, f"duplicate PTR for {owner}"
    pointers[owner] = target
named = {name: address for name, address in expected.items()
         if name not in ("dns-api.home.arpa.", "canary.home.arpa.")}
wanted = {".".join(reversed(address.split("."))) + ".in-addr.arpa.": name
          for name, address in named.items()}
assert pointers == wanted, pointers
PY
pass repository_zones_name_each_static_address_once_in_forward_and_reverse

zone_repo=$temporary/zone-repo
mkdir -p "$zone_repo/zones"
cp "$temporary/desired.zone" "$zone_repo/zones/home.arpa.zone"
git -C "$zone_repo" init -q
git -C "$zone_repo" add zones/home.arpa.zone
git -C "$zone_repo" -c user.name=test -c user.email=test@example.invalid \
    commit -q -m zone
dnsctl_in_repo() {
    (
        cd "$zone_repo"
        PATH="$temporary/bin:$PATH" \
        MOCK_CURRENT_ZONE="${DNSCTL_TEST_EXPORT:-$temporary/current.zone}" \
        MOCK_IMPORT_LOG="$temporary/import.log" \
        MOCK_IMPORT_PAYLOAD="$temporary/import.payload" \
        TECHNITIUM_URL="${DNSCTL_TEST_URL:-https://dns01:53443}" \
        TECHNITIUM_TOKEN_FILE="$temporary/token" \
        TECHNITIUM_CA_FILE="$temporary/technitium-ca.pem" \
        DNSCTL_AUDIT_LOG="$temporary/apply-audit.jsonl" \
            "$repo_root/management/dnsctl" "$@"
    )
}
expect_apply_rejected() {
    name=$1
    shift
    : > "$temporary/import.log"
    if dnsctl_in_repo apply "$@" > "$temporary/reject.out" 2> "$temporary/reject.err"; then
        echo "FAIL $name: dnsctl apply succeeded" >&2
        exit 1
    fi
    if [ -s "$temporary/import.log" ]; then
        echo "FAIL $name: dnsctl apply imported before rejecting" >&2
        exit 1
    fi
    pass "$name"
}
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

dnsctl_in_repo plan zones/home.arpa.zone --out "$temporary/reviewed.plan" \
    > /dev/null 2> "$temporary/reviewed.err"
plan_sha=$(sha256_of "$temporary/reviewed.plan")
grep -q "^dnsctl: plan_sha256=$plan_sha$" "$temporary/reviewed.err"
jq -e --arg commit "$(git -C "$zone_repo" rev-parse HEAD)" \
    '.schema_version == 2 and .source_commit == $commit
     and .zone_path == "zones/home.arpa.zone"
     and .target_url == "https://dns01:53443" and .changed == true' \
    "$temporary/reviewed.plan" >/dev/null
[ ! -w "$temporary/reviewed.plan" ] || [ "$(id -u)" -eq 0 ]
pass dnsctl_plan_saves_a_read_only_bound_plan

if dnsctl_in_repo plan zones/home.arpa.zone --out "$temporary/reviewed.plan" \
    >/dev/null 2>&1; then
    echo "FAIL dnsctl plan overwrote a saved plan" >&2
    exit 1
fi
[ "$(sha256_of "$temporary/reviewed.plan")" = "$plan_sha" ]
pass dnsctl_saved_plans_are_immutable

printf '%s\n' '; uncommitted' >> "$zone_repo/zones/home.arpa.zone"
if dnsctl_in_repo plan zones/home.arpa.zone --out "$temporary/dirty.plan" \
    >/dev/null 2>&1; then
    echo "FAIL dnsctl saved a plan for an uncommitted zone" >&2
    exit 1
fi
git -C "$zone_repo" checkout -q -- zones/home.arpa.zone
pass dnsctl_saved_plan_requires_committed_zone

expect_apply_rejected dnsctl_apply_requires_literal_confirmation \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm NOT_APPLY
expect_apply_rejected dnsctl_apply_rejects_unreviewed_plan_hash \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$(printf '%064d' 0)" --confirm APPLY
DNSCTL_TEST_URL=https://dns02:53443 expect_apply_rejected \
    dnsctl_apply_rejects_other_endpoint \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm APPLY

printf '%s\n' '; uncommitted' >> "$zone_repo/zones/home.arpa.zone"
expect_apply_rejected dnsctl_apply_rejects_uncommitted_zone \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm APPLY
git -C "$zone_repo" checkout -q -- zones/home.arpa.zone

cp "$temporary/current.zone" "$temporary/current.zone.reviewed"
printf '%s\n' 'drift IN A 10.77.9.8' >> "$temporary/current.zone"
expect_apply_rejected dnsctl_apply_rejects_live_zone_drift \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm APPLY
jq -s -e 'map(select(.result == "drifted")) | length == 1' \
    "$temporary/apply-audit.jsonl" >/dev/null
cp "$temporary/current.zone.reviewed" "$temporary/current.zone"

# The comparison ignores the SOA, but the drift check still binds the exact
# live export the plan saw.
sed 's/( 1 3600/( 5 3600/' "$temporary/current.zone.reviewed" > "$temporary/current.zone"
expect_apply_rejected dnsctl_apply_rejects_live_soa_drift \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm APPLY
cp "$temporary/current.zone.reviewed" "$temporary/current.zone"

: > "$temporary/import.log"
rm -f "$temporary/import.payload"
dnsctl_in_repo apply --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" \
    --confirm APPLY > "$temporary/apply.json"
jq -e --arg plan "$plan_sha" '.status == "ok" and .plan_sha256 == $plan' \
    "$temporary/apply.json" >/dev/null
grep -q 'zone=home.arpa&overwrite=true' "$temporary/import.log"
jq -s -e --arg plan "$plan_sha" \
    'map(select(.action == "apply:home.arpa" and .result == "ok" and .plan_sha256 == $plan)) | length == 1' \
    "$temporary/apply-audit.jsonl" >/dev/null
pass dnsctl_apply_consumes_the_reviewed_plan

# The import carries every record except the SOA and apex NS records, exactly
# as cluster-bootstrap strips them.
python3 - "$repo_root/management/cluster-bootstrap" "$temporary/bootstrap-strip.awk" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
program = re.search(r"^awk '\n(.*?)\n' \"\$zone_file\" > \"\$zone_import\"$", source, re.M | re.S)
assert program, "cluster-bootstrap zone import filter is missing"
pathlib.Path(sys.argv[2]).write_text(program.group(1) + "\n")
PY
[ -s "$temporary/import.payload" ] || {
    echo "FAIL dnsctl apply did not upload a zone file" >&2
    exit 1
}
if grep -Eq '[[:space:]]SOA[[:space:]]' "$temporary/import.payload" ||
    grep -Eq '^@[[:space:]].*[[:space:]]NS[[:space:]]' "$temporary/import.payload"; then
    echo "FAIL dnsctl apply imported an SOA or apex NS record" >&2
    exit 1
fi
grep -q '^canary IN A 10.77.9.9$' "$temporary/import.payload"
awk -f "$temporary/bootstrap-strip.awk" "$zone_repo/zones/home.arpa.zone" > "$temporary/bootstrap.payload"
cmp -s "$temporary/bootstrap.payload" "$temporary/import.payload" || {
    echo "FAIL dnsctl apply and cluster-bootstrap strip managed records differently" >&2
    exit 1
}
pass dnsctl_apply_imports_without_soa_and_apex_ns

expect_apply_rejected dnsctl_apply_rejects_replayed_plan \
    --plan "$temporary/reviewed.plan" --plan-sha256 "$plan_sha" --confirm APPLY

printf '%s\n' 'next IN A 10.77.9.10' >> "$zone_repo/zones/home.arpa.zone"
git -C "$zone_repo" -c user.name=test -c user.email=test@example.invalid \
    commit -q -am next
dnsctl_in_repo plan zones/home.arpa.zone --out "$temporary/stale.plan" \
    > /dev/null 2>&1
stale_sha=$(sha256_of "$temporary/stale.plan")
printf '%s\n' 'later IN A 10.77.9.11' >> "$zone_repo/zones/home.arpa.zone"
git -C "$zone_repo" -c user.name=test -c user.email=test@example.invalid \
    commit -q -am later
expect_apply_rejected dnsctl_apply_rejects_other_source_commit \
    --plan "$temporary/stale.plan" --plan-sha256 "$stale_sha" --confirm APPLY

# The reverse zone goes through the same hash-bound plan and apply.
cp "$reverse_zone" "$zone_repo/zones/77.10.in-addr.arpa.zone"
git -C "$zone_repo" add zones/77.10.in-addr.arpa.zone
git -C "$zone_repo" -c user.name=test -c user.email=test@example.invalid \
    commit -q -m reverse
DNSCTL_TEST_EXPORT=$temporary/export-empty-reverse.zone \
    dnsctl_in_repo plan zones/77.10.in-addr.arpa.zone --out "$temporary/reverse.plan" \
    > /dev/null 2>&1
reverse_sha=$(sha256_of "$temporary/reverse.plan")
jq -e --arg commit "$(git -C "$zone_repo" rev-parse HEAD)" \
    '.zone == "77.10.in-addr.arpa" and .changed == true and .source_commit == $commit
     and .zone_path == "zones/77.10.in-addr.arpa.zone"' \
    "$temporary/reverse.plan" >/dev/null
DNSCTL_TEST_URL=https://dns02:53443 DNSCTL_TEST_EXPORT=$temporary/export-empty-reverse.zone \
    expect_apply_rejected dnsctl_apply_rejects_reverse_plan_for_other_endpoint \
    --plan "$temporary/reverse.plan" --plan-sha256 "$reverse_sha" --confirm APPLY
: > "$temporary/import.log"
rm -f "$temporary/import.payload"
DNSCTL_TEST_EXPORT=$temporary/export-empty-reverse.zone \
    dnsctl_in_repo apply --plan "$temporary/reverse.plan" --plan-sha256 "$reverse_sha" \
    --confirm APPLY > "$temporary/reverse-apply.json"
jq -e --arg plan "$reverse_sha" '.status == "ok" and .plan_sha256 == $plan' \
    "$temporary/reverse-apply.json" >/dev/null
grep -q 'zone=77.10.in-addr.arpa&overwrite=true' "$temporary/import.log"
[ "$(grep -c '[[:space:]]PTR[[:space:]]' "$temporary/import.payload")" -eq 8 ]
if grep -Eq '[[:space:]](SOA|NS)[[:space:]]' "$temporary/import.payload"; then
    echo "FAIL dnsctl apply imported the reverse zone's SOA or apex NS" >&2
    exit 1
fi
DNSCTL_TEST_EXPORT=$temporary/export-empty-reverse.zone \
    expect_apply_rejected dnsctl_apply_rejects_replayed_reverse_plan \
    --plan "$temporary/reverse.plan" --plan-sha256 "$reverse_sha" --confirm APPLY
pass dnsctl_reverse_zone_plan_and_bound_apply

enrollment=$temporary/DNS-ENROLL
generation=11111111-2222-3333-4444-555555555555
mkdir -p "$enrollment/records/dns01/$generation"
printf '%s\n' "$generation" > "$enrollment/records/dns01/ACTIVE"
cat > "$enrollment/records/dns01/$generation/public.json" <<'EOF'
{"hardware":{"system_uuid":"550E8400-E29B-41D4-A716-446655440000"}}
EOF
"$repo_root/management/authorize-reinstall" \
    --enrollment "$enrollment" --role dns01 --confirm 'ERASE dns01' >/dev/null
grep -q '^role=dns01$' "$enrollment/reinstall/dns01.allow"
grep -q "^previous_generation=$generation$" "$enrollment/reinstall/dns01.allow"
grep -q '^authorize_erase=true$' "$enrollment/reinstall/dns01.allow"
pass reinstall_authorization_is_generation_bound

if PATH="$temporary/bin:$PATH" \
    "$repo_root/management/network-preflight" 10.77.0.1/24 >/dev/null 2>&1; then
    echo "FAIL /24 unexpectedly contains the DNS node addresses" >&2
    exit 1
fi
PATH="$temporary/bin:$PATH" \
    "$repo_root/management/network-preflight" --offline 10.77.0.1/16 \
    > "$temporary/network.txt"
grep -q '10.77.0.0/16 contains router and all DNS nodes' "$temporary/network.txt"
pass network_preflight_rejects_24_and_accepts_16

PATH="$temporary/bin:$PATH" \
    "$repo_root/management/network-preflight" --json --offline 10.77.0.1/16 \
    > "$temporary/network.json"
jq -e '
  .schema_version == 1 and
  .operation == "network.preflight" and
  .topology.valid == true and
  (.topology.management_host_default_route.observed | type == "boolean") and
  .internet.checked == false and
  .internet.ready == null and
  .network_gates.offline_dns_install.ready == true and
  .network_gates.media_download.ready == null and
  .network_gates.post_install_netbird.internet_required == true and
  .network_gates.post_install_netbird.ready == null and
  .network_gates.post_install_netbird == .network_gates.post_install_tailscale
' "$temporary/network.json" >/dev/null
pass network_preflight_offline_json_is_explicit

# Exercise the actual first-boot renderer without running appliance setup.
python3 - "$repo_root/dns-image/payload/dns-appliance-firstboot" "$temporary" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
blocks = []
for name in ("recursion_acl", "write_technitium_env"):
    function = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    assert function, f"first-boot {name} is missing"
    blocks.append(function.group().replace("/etc/dns-appliance", "${fixture_dir}"))
pathlib.Path(sys.argv[2], "render-env").write_text(
    'set -eu\n' + "\n".join(blocks) + '\nwrite_technitium_env "$1"\n'
)
PY
# The recursion ACL follows the overlay selection: loopback and the LAN, plus
# each selected overlay's address range.
for case_line in 'tailscale|127.0.0.0/8,10.77.0.0/16,100.64.0.0/10' \
    'netbird|127.0.0.0/8,10.77.0.0/16,10.78.0.0/16' \
    'tailscale netbird|127.0.0.0/8,10.77.0.0/16,100.64.0.0/10,10.78.0.0/16'; do
    selection=${case_line%%|*}
    # shellcheck disable=SC2086 # one selected overlay per line
    printf '%s\n' $selection > "$temporary/overlays"
    for include_password in true false; do
        fixture_dir="$temporary" ROLE=dns01 CLUSTER_DOMAIN=home.arpa NETBIRD_RANGE=10.78.0.0/16 \
            ADDRESS=10.77.5.1 LAN_CIDR=10.77.0.0/16 technitium_token="$temporary/token" \
            overlay_selection="$temporary/overlays" \
            sh "$temporary/render-env" "$include_password"
        python3 - "$temporary/technitium.env" "$include_password" "$selection" "${case_line#*|}" <<'PY'
import ipaddress
import pathlib
import stat
import sys

path = pathlib.Path(sys.argv[1])
selection = sys.argv[3].split()
config = dict(line.split("=", 1) for line in path.read_text().splitlines())
assert stat.S_IMODE(path.stat().st_mode) == 0o600
assert config["DNS_SERVER_RECURSION"] == "UseSpecifiedNetworkACL"
assert config["DNS_SERVER_RECURSION_NETWORK_ACL"] == sys.argv[4], config["DNS_SERVER_RECURSION_NETWORK_ACL"]
networks = [ipaddress.ip_network(value) for value in config["DNS_SERVER_RECURSION_NETWORK_ACL"].split(",")]
allowed = lambda address: any(ipaddress.ip_address(address) in network for network in networks)
tailscale = ("100.64.0.0", "100.100.1.2", "100.127.255.255")
netbird = ("10.78.0.1", "10.78.255.254")
for address in ("127.0.0.1", "10.77.5.1", "10.77.0.0", "10.77.255.254"):
    assert allowed(address), f"expected recursion for {address}"
for address in tailscale:
    assert allowed(address) == ("tailscale" in selection), f"recursion for {address} with {selection}"
for address in netbird:
    assert allowed(address) == ("netbird" in selection), f"recursion for {address} with {selection}"
for address in ("1.1.1.1", "10.1.0.1", "10.76.255.255", "10.79.0.0", "100.63.255.255",
                "100.128.0.0", "192.168.0.1", "::1"):
    assert not allowed(address), f"unexpected recursion for {address}"
assert ("DNS_SERVER_ADMIN_PASSWORD_FILE" in config) == (sys.argv[2] == "true")
assert config["DNS_SERVER_AUTH_STATIC_SESSIONS"] == "admin:token"
PY
    done
done
pass firstboot_recursion_allows_lan_and_selected_overlays_but_not_public_clients

printf 'netbird\n' > "$temporary/overlays"
fixture_dir="$temporary" ROLE=dns01 CLUSTER_DOMAIN=home.arpa NETBIRD_RANGE=10.66.0.0/16 \
    ADDRESS=10.77.5.1 LAN_CIDR=10.77.0.0/16 technitium_token="$temporary/token" \
    overlay_selection="$temporary/overlays" \
    sh "$temporary/render-env" false
grep -qx 'DNS_SERVER_RECURSION_NETWORK_ACL=127.0.0.0/8,10.77.0.0/16,10.66.0.0/16' "$temporary/technitium.env" || {
    echo "FAIL first boot did not take the NetBird range from the install state" >&2
    exit 1
}
pass firstboot_recursion_takes_the_netbird_range_from_the_install_state

# The appliance firewall is rendered by the installer step itself: its
# functions are extracted from dns-finish-install and run against a fixture
# medium carrying the three embedded role profiles.
finish_script=$repo_root/dns-image/scripts/dns-finish-install
firewall=$temporary/firewall
mkdir -p "$firewall/cdrom/simple-cdd"
python3 - "$finish_script" "$firewall" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
blocks = []
for name in ("canonical_overlays", "ipv4_cidr", "peer_address", "render_firewall"):
    function = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    assert function, f"{name} is missing from dns-finish-install"
    blocks.append(function.group().replace("/cdrom/", sys.argv[2] + "/cdrom/"))
pathlib.Path(sys.argv[2], "render.sh").write_text(
    "set -eu\n" + "\n".join(blocks) + '\nrender_firewall "$1" "$2" "$3"\n'
)
PY
grep -qx 'render_firewall /cdrom/simple-cdd/nftables.conf /target/etc/dns-appliance/overlays /target/etc/nftables.conf' \
    "$finish_script" || {
    echo "FAIL dns-finish-install does not render the firewall from the installed overlay selection" >&2
    exit 1
}
reset_firewall_fixture() {
    rm -f "$firewall/nftables.conf" "$firewall/nftables.conf.tmp"
    for number in 1 2 3; do
        printf 'role=dns0%s\naddress=10.77.5.%s\nprefix_length=16\n' "$number" "$number" \
            > "$firewall/cdrom/simple-cdd/dns0$number.conf"
    done
}
render_firewall_fixture() {
    LAN_CIDR=${FIREWALL_LAN_CIDR-10.77.0.0/16} \
    MANAGEMENT_CIDR=${FIREWALL_MANAGEMENT_CIDR-10.77.0.0/24} \
    NETBIRD_RANGE=${FIREWALL_NETBIRD_RANGE-10.78.0.0/16} \
        sh "$firewall/render.sh" "${FIREWALL_TEMPLATE:-$repo_root/dns-image/payload/nftables.conf}" \
        "$firewall/overlays" "$firewall/nftables.conf"
}
for selection in tailscale netbird 'tailscale netbird'; do
    reset_firewall_fixture
    # shellcheck disable=SC2086 # one selected overlay per line
    printf '%s\n' $selection > "$firewall/overlays"
    render_firewall_fixture > "$firewall/render.log" 2>&1 || {
        echo "FAIL firewall rendering for '$selection': $(cat "$firewall/render.log")" >&2
        exit 1
    }
    python3 - "$firewall/nftables.conf" "$selection" <<'PY'
import pathlib
import re
import stat
import sys

path = pathlib.Path(sys.argv[1])
selection = sys.argv[2].split()
assert stat.S_IMODE(path.stat().st_mode) == 0o644
text = path.read_text()
assert "@@" not in text, "unrendered marker"
lines = [line.strip() for line in text.splitlines()
         if line.strip() and not line.strip().startswith("#")]
assert not any(line.startswith("flush") for line in lines), "the firewall flushes"
assert "ruleset" not in " ".join(lines), "the firewall names the whole ruleset"
# Idempotent load: create-if-absent, delete, recreate, all in one transaction.
assert lines[:3] == ["table inet dns_appliance", "delete table inet dns_appliance",
                     "table inet dns_appliance {"], lines[:3]
assert [line for line in lines if line.startswith(("table", "delete", "add", "destroy"))] == lines[:3]

chains = {}
for match in re.finditer(r"^\s*chain (\S+) \{\n(.*?)^\s*\}", text, re.M | re.S):
    chains[match.group(1)] = [line.strip() for line in match.group(2).splitlines()
                              if line.strip() and not line.strip().startswith("#")]
assert sorted(chains) == ["forward", "input", "output", "overlay_prerouting"], sorted(chains)

interfaces = [name for overlay, name in (("tailscale", "tailscale0"), ("netbird", "wt0"))
              if overlay in selection]
quoted = ", ".join(f'"{name}"' for name in interfaces)
management = "{ 22, 53, 9090, 9100, 53443 }"

expected_prerouting = [
    "type filter hook prerouting priority filter; policy accept;",
    f"iifname != {{ {quoted} }} accept",
    "fib daddr type != { local, broadcast, multicast } accept",
    "ct state established,related accept",
    "ct state invalid drop",
    "meta l4proto { icmp, ipv6-icmp } accept",
    "udp dport 53 accept",
    f"tcp dport {management} accept",
    "drop",
]
assert chains["overlay_prerouting"] == expected_prerouting, chains["overlay_prerouting"]

expected_input = ["type filter hook input priority filter; policy drop;", 'iifname "lo" accept']
if "tailscale" in selection:
    expected_input.append('iifname != "tailscale0" ip saddr 100.64.0.0/10 drop')
if "netbird" in selection:
    expected_input.append('iifname != "wt0" ip saddr 10.78.0.0/16 drop')
expected_input += [
    "ct state established,related accept",
    "ct state invalid drop",
    "ip protocol icmp accept",
    "ip6 nexthdr ipv6-icmp accept",
    "ip saddr 10.77.0.0/16 udp dport 53 accept",
    "ip saddr 10.77.0.0/16 tcp dport 53 accept",
    "ip saddr { 10.77.5.1, 10.77.5.2, 10.77.5.3 } tcp dport 53443 accept",
    "ip saddr 10.77.0.0/24 tcp dport { 22, 9090, 9100, 53443 } accept",
]
for name in interfaces:
    expected_input += [f'iifname "{name}" udp dport 53 accept',
                       f'iifname "{name}" tcp dport {management} accept']
assert chains["input"] == expected_input, chains["input"]
assert chains["forward"] == ["type filter hook forward priority filter; policy drop;"]
assert chains["output"] == ["type filter hook output priority filter; policy accept;"]
for unselected in {"tailscale0", "wt0"} - set(interfaces):
    assert not any(unselected in line for line in lines), f"{unselected} is rendered without its overlay"
PY
done
pass firewall_renders_only_its_own_table_for_each_overlay_selection
pass firewall_limits_selected_overlay_interfaces_in_prerouting_and_guards_their_ranges

expect_firewall_rejected() {
    name=$1
    if render_firewall_fixture > "$firewall/render.log" 2>&1; then
        echo "FAIL firewall rendering accepted $name" >&2
        exit 1
    fi
    if [ -e "$firewall/nftables.conf" ] || [ -e "$firewall/nftables.conf.tmp" ]; then
        echo "FAIL firewall rendering left output after rejecting $name" >&2
        exit 1
    fi
}
reset_firewall_fixture
printf 'tailscale\nnetbird\n' > "$firewall/overlays"
sed 's/^\( *\)ct state invalid drop$/\1ct state invalid drop @@UNKNOWN@@/' \
    "$repo_root/dns-image/payload/nftables.conf" > "$firewall/stray-marker.conf"
FIREWALL_TEMPLATE=$firewall/stray-marker.conf expect_firewall_rejected "an unrendered marker"
FIREWALL_LAN_CIDR='10.77.0.0/16 accept' expect_firewall_rejected "a LAN value that is not a CIDR"
FIREWALL_LAN_CIDR='10.77.0.0/33' expect_firewall_rejected "a LAN prefix above 32"
FIREWALL_MANAGEMENT_CIDR='' expect_firewall_rejected "an empty management CIDR"
FIREWALL_MANAGEMENT_CIDR='10.77.0.256/24' expect_firewall_rejected "an invalid management address"
printf 'role=dns03\n' > "$firewall/cdrom/simple-cdd/dns03.conf"
expect_firewall_rejected "a role profile without an address"
reset_firewall_fixture
: > "$firewall/overlays"
expect_firewall_rejected "an empty overlay selection"
printf 'wireguard\n' > "$firewall/overlays"
expect_firewall_rejected "an unknown overlay selection"
printf 'netbird\n' > "$firewall/overlays"
FIREWALL_NETBIRD_RANGE='' expect_firewall_rejected "NetBird without a NetBird range"
FIREWALL_NETBIRD_RANGE='10.78.0.0/16 accept' expect_firewall_rejected "a NetBird range that is not a CIDR"
pass firewall_rendering_rejects_unrendered_markers_and_invalid_inputs

# The NetBird range comes from the World's network plan, not from the template.
reset_firewall_fixture
printf 'netbird\n' > "$firewall/overlays"
FIREWALL_NETBIRD_RANGE=10.66.0.0/16 render_firewall_fixture > "$firewall/render.log" 2>&1 || {
    echo "FAIL firewall rendering with another NetBird range: $(cat "$firewall/render.log")" >&2
    exit 1
}
if ! grep -q 'iifname != "wt0" ip saddr 10.66.0.0/16 drop' "$firewall/nftables.conf" ||
    grep -q '10\.78\.' "$firewall/nftables.conf"; then
    echo "FAIL the firewall did not take the NetBird range from the network plan" >&2
    exit 1
fi
reset_firewall_fixture
printf 'tailscale\n' > "$firewall/overlays"
FIREWALL_NETBIRD_RANGE='' render_firewall_fixture > "$firewall/render.log" 2>&1 || {
    echo "FAIL a Tailscale-only firewall needed a NetBird range: $(cat "$firewall/render.log")" >&2
    exit 1
}
pass firewall_takes_the_netbird_range_from_the_network_plan

# The health script reports each selected overlay and only those. Every
# command it runs is a fixture on PATH; the reboot metrics come from a fake
# reboot script and are written unchanged.
health=$temporary/health
mkdir -p "$health/bin" "$health/etc" "$health/state/secrets" "$health/metrics"
printf 'ROLE=dns01\nADDRESS=10.77.5.1\n' > "$health/etc/install.env"
printf '%s\n' health-token > "$health/state/secrets/technitium-static-token"
sed -e "s#/etc/dns-appliance#$health/etc#g" \
    -e "s#/var/lib/dns-appliance#$health/state#g" \
    -e "s#/var/lib/prometheus/node-exporter#$health/metrics#g" \
    -e "s#/usr/local/sbin/dns-appliance-reboot#$health/bin/dns-appliance-reboot#g" \
    "$repo_root/dns-image/payload/dns-appliance-health" > "$health/dns-appliance-health"
cat > "$health/bin/dig" <<'EOF'
#!/bin/sh
printf '127.0.0.1\n'
EOF
cat > "$health/bin/curl" <<'EOF'
#!/bin/sh
printf '{"status":"ok"}\n'
EOF
cat > "$health/bin/timedatectl" <<'EOF'
#!/bin/sh
printf 'yes\n'
EOF
cat > "$health/bin/tailscale" <<'EOF'
#!/bin/sh
[ "$*" = "status --json" ] || exit 64
printf '%s\n' '{"BackendState":"Running","Self":{"HostName":"dns01","TailscaleIPs":["100.101.1.1","fd7a:115c:a1e0::1"],"Tags":["tag:dns-appliance"]}}'
EOF
cat > "$health/bin/netbird" <<'EOF'
#!/bin/sh
[ "$*" = "status --json" ] || exit 64
[ "${HEALTH_NETBIRD_FAIL:-false}" = false ] || exit 1
printf '%s\n' '{"management":{"url":"https://api.netbird.io:443","connected":true},"netbirdIp":"10.78.0.5/16","fqdn":"dns01.netbird.cloud"}'
EOF
cat > "$health/bin/dns-appliance-reboot" <<'EOF'
#!/bin/sh
[ "$1" = metrics ] || exit 64
printf 'dns_appliance_reboot_pending 0\ndns_appliance_reboot_skipped_consecutive 0\ndns_appliance_reboot_last_skip_timestamp_seconds 0\n'
EOF
chmod 0755 "$health/bin"/*
run_health() {
    rm -f "$health/state/health.json" "$health/metrics"/*.prom
    PATH="$health/bin:$PATH" bash "$health/dns-appliance-health" > "$health/run.log" 2>&1
}
for selection in tailscale netbird 'tailscale netbird'; do
    # shellcheck disable=SC2086 # one selected overlay per line
    printf '%s\n' $selection > "$health/etc/overlays"
    run_health || {
        echo "FAIL health for '$selection': $(cat "$health/run.log")" >&2
        exit 1
    }
    jq -e --arg selection "$selection" '
      ($selection | split(" ")) as $selected |
      (has("tailscale") | not) and
      (.overlays | keys | sort) == ($selected | sort) and
      (if ($selected | index("tailscale")) then
         .overlays.tailscale == {up: 1, state: "Running", ip: "100.101.1.1", hostname: "dns01", tags: ["tag:dns-appliance"]}
       else true end) and
      (if ($selected | index("netbird")) then
         .overlays.netbird == {up: 1, state: "Connected", ip: "10.78.0.5", hostname: "dns01"}
       else true end) and
      .hostname == "dns01" and .dns_udp == 1 and .technitium == 1
    ' "$health/state/health.json" >/dev/null || {
        echo "FAIL health.json for '$selection': $(cat "$health/state/health.json")" >&2
        exit 1
    }
    for overlay in tailscale netbird; do
        case " $selection " in
            *" $overlay "*) want=1 ;;
            *) want=0 ;;
        esac
        have=$(grep -c "^dns_appliance_service_up{service=\"$overlay\"} 1\$" "$health/metrics/dns-appliance.prom" || true)
        [ "$have" = "$want" ] || {
            echo "FAIL health metric for $overlay with '$selection': $(cat "$health/metrics/dns-appliance.prom")" >&2
            exit 1
        }
    done
    "$health/bin/dns-appliance-reboot" metrics > "$health/expected-reboot.prom"
    cmp -s "$health/expected-reboot.prom" "$health/metrics/dns-appliance-reboot.prom" || {
        echo "FAIL health no longer writes the reboot metrics unchanged" >&2
        exit 1
    }
done
printf 'netbird\n' > "$health/etc/overlays"
HEALTH_NETBIRD_FAIL=true run_health || {
    echo "FAIL health failed when only the NetBird daemon is down: $(cat "$health/run.log")" >&2
    exit 1
}
jq -e '.overlays == {netbird: {up: 0, state: "Unavailable", ip: "", hostname: ""}}' \
    "$health/state/health.json" >/dev/null || {
    echo "FAIL unavailable NetBird is not reported: $(cat "$health/state/health.json")" >&2
    exit 1
}
grep -qx 'dns_appliance_service_up{service="netbird"} 0' "$health/metrics/dns-appliance.prom" || {
    echo "FAIL unavailable NetBird metric is not 0" >&2
    exit 1
}
for content in '' 'wireguard\n' 'netbird\ntailscale\n'; do
    printf '%b' "$content" > "$health/etc/overlays"
    if run_health; then
        echo "FAIL health accepted overlay selection '$content'" >&2
        exit 1
    fi
done
pass health_reports_each_selected_overlay_and_only_those

echo "RESULT $pass_count/34 management simulations passed"
