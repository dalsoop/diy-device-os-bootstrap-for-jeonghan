#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/dns-netbird-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

token=nbp_SimulationSecretToken0123456789abcde
key_prefix=0A1B2C3D-0000-4000-8000-00000000000
mkdir -p "$temporary/bin"
printf '%s\n' "$token" > "$temporary/token"
printf '%s\n' not-a-netbird-token > "$temporary/bad-token"

# Fake NetBird management API. The scenario selects one deviation from a
# healthy account; every call is logged with its arguments.
cat > "$temporary/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$MOCK_STATE/argv.log"
config=$(cat)
[ "$config" = "header = \"Authorization: Token $MOCK_TOKEN\"" ] || {
    echo "fake curl: missing or unexpected authorization header" >&2
    exit 90
}
method=GET
payload=
while [ "$#" -gt 1 ]; do
    case "$1" in
        --request) method=$2; shift 2 ;;
        --data-binary) payload=$2; shift 2 ;;
        *) shift ;;
    esac
done
url=$1
case "$url" in
    "$MOCK_URL"/api/*) ;;
    *) echo "fake curl: unexpected URL $url" >&2; exit 91 ;;
esac
endpoint=${url#"$MOCK_URL"/api/}
printf '%s %s\n' "$method" "$endpoint" >> "$MOCK_STATE/api.log"
case "$method $endpoint" in
    'GET groups')
        case "$MOCK_SCENARIO" in
            missing-group) printf '%s\n' '[{"id":"grp-all","name":"All","peers_count":0,"resources_count":0}]' ;;
            ambiguous-group) printf '%s\n' '[{"id":"grp-a","name":"dns-appliances","peers_count":0,"resources_count":0},{"id":"grp-b","name":"dns-appliances","peers_count":0,"resources_count":0}]' ;;
            *) printf '%s\n' '[{"id":"grp-all","name":"All","peers_count":0,"resources_count":0},{"id":"grp-appl","name":"dns-appliances","peers_count":0,"resources_count":0}]' ;;
        esac
        ;;
    'POST setup-keys')
        [ "$MOCK_SCENARIO" != key-create-fail ] || exit 22
        printf '%s' "$payload" | jq -e '
            .type == "one-off" and .usage_limit == 1 and .expires_in == 86400 and
            .ephemeral == false and .auto_groups == ["grp-appl"] and
            (.name | test("^dns0[1-3] DNS appliance bootstrap$"))
        ' >/dev/null || { echo "fake curl: unexpected setup-key request" >&2; exit 92; }
        count=$(( $(wc -l < "$MOCK_STATE/created") + 1 ))
        printf '%s\n' "key-$count" >> "$MOCK_STATE/created"
        jq -cn --arg id "key-$count" --arg key "$MOCK_KEY_PREFIX$count" '{
            id:$id, key:$key, name:"bootstrap", type:"one-off", valid:true,
            revoked:false, used_times:0, state:"valid", auto_groups:["grp-appl"],
            usage_limit:1, ephemeral:false, allow_extra_dns_labels:false
        }'
        ;;
    'DELETE setup-keys/'*)
        [ "$MOCK_SCENARIO" != delete-fail ] || exit 22
        printf '%s\n' "${endpoint#setup-keys/}" >> "$MOCK_STATE/deleted"
        printf '%s\n' '{}'
        ;;
    'GET setup-keys')
        remaining=$(grep -vxF -f "$MOCK_STATE/deleted" "$MOCK_STATE/created" || true)
        printf '%s' "$remaining" |
            jq -Rsc 'split("\n") | map(select(length > 0) | {id:., key:"0A1B****", type:"one-off"})'
        ;;
    'GET peers?ip='*)
        ip=${endpoint#peers?ip=}
        index=${ip##*.}
        groups='[{"id":"grp-all","name":"All"},{"id":"grp-appl","name":"dns-appliances"}]'
        [ "$MOCK_SCENARIO" != not-in-group ] ||
            groups='[{"id":"grp-all","name":"All"}]'
        jq -cn --arg id "peer-$index" --arg ip "$ip" --argjson groups "$groups" \
            '[{id:$id, name:"dns", ip:$ip, groups:$groups}]'
        ;;
    'GET routes')
        case "$MOCK_SCENARIO" in
            routing-peer) printf '%s\n' '[{"id":"route-1","network":"0.0.0.0/0","peer":"peer-1","enabled":false}]' ;;
            *) printf '%s\n' '[{"id":"route-2","network":"192.0.2.0/24","peer":"peer-other","groups":["grp-appl"]}]' ;;
        esac
        ;;
    'GET networks/routers')
        case "$MOCK_SCENARIO" in
            routing-group) printf '%s\n' '[{"id":"router-1","peer_groups":["grp-appl"],"metric":9999,"masquerade":true,"enabled":true}]' ;;
            *) printf '%s\n' '[{"id":"router-2","peer_groups":["grp-other"],"metric":9999,"masquerade":true,"enabled":true}]' ;;
        esac
        ;;
    *)
        echo "fake curl: unexpected request $method $endpoint" >&2
        exit 93
        ;;
esac
EOF

# Fake appliance SSH. Each host keeps its own enrollment state.
cat > "$temporary/bin/ssh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'ssh %s\n' "$*" >> "$MOCK_STATE/argv.log"
destination=
for argument in "$@"; do
    case "$argument" in
        *@10.77.5.[123]) destination=$argument ;;
    esac
done
[ "${destination%@*}" = "$MOCK_SSH_USER" ] || { echo "fake ssh: unexpected destination" >&2; exit 94; }
index=${destination##*.}
role=dns0$index
ip=10.78.1.$index
command=$*
case "$command" in
    *'netbird up '*)
        [ "$MOCK_SCENARIO" != up-fail ] || exit 1
        key=$(cat)
        [ "$key" = "$MOCK_KEY_PREFIX$(wc -l < "$MOCK_STATE/created" | tr -d ' ')" ] ||
            { echo "fake ssh: setup key did not arrive on stdin" >&2; exit 95; }
        for flag in "--setup-key-file \"\$temporary\"" "--management-url $MOCK_URL" \
            "--hostname $role" --disable-dns=true --disable-client-routes=true \
            --disable-server-routes=true --allow-server-ssh=false 'chmod 0600' 'rm -f'; do
            [[ "$command" == *"$flag"* ]] || { echo "fake ssh: missing $flag" >&2; exit 96; }
        done
        : > "$MOCK_STATE/up-$index"
        ;;
    *'netbird status --json'*)
        if [ ! -e "$MOCK_STATE/up-$index" ] && [ "$MOCK_SCENARIO" != already ]; then
            printf '%s\n' '{"daemonStatus":"NeedsLogin","management":{"connected":false},"netbirdIp":"","fqdn":""}'
            exit 0
        fi
        fqdn=$role.netbird.cloud
        address=$ip/16
        [ "$MOCK_SCENARIO" != wrong-hostname ] || fqdn=$role-1.netbird.cloud
        [ "$MOCK_SCENARIO" != outside-range ] || address=100.90.0.$index/16
        jq -cn --arg fqdn "$fqdn" --arg ip "$address" '{
            daemonStatus:"Connected", management:{url:"https://api.netbird.io:443",connected:true},
            netbirdIp:$ip, fqdn:$fqdn, sshServer:{enabled:false,sessions:[]}
        }'
        ;;
    *'netbird debug config'*)
        dns=true client=true server=true ssh=false
        [ "$MOCK_SCENARIO" != dns-preference ] || dns=false
        [ "$MOCK_SCENARIO" != client-route-preference ] || client=false
        [ "$MOCK_SCENARIO" != server-route-preference ] || server=false
        [ "$MOCK_SCENARIO" != ssh-preference ] || ssh=true
        jq -n --argjson dns "$dns" --argjson client "$client" --argjson server "$server" \
            --argjson ssh "$ssh" '{
            managementUrl:"https://api.netbird.io:443", preSharedKey:"",
            disableDns:$dns, disableClientRoutes:$client, disableServerRoutes:$server,
            serverSSHAllowed:$ssh, mDMManagedFields:[]
        }'
        ;;
    *'cat /etc/resolv.conf'*)
        printf '%s\n' '# managed by dns-appliance'
        printf '%s\n' 'nameserver 127.0.0.1'
        [ "$MOCK_SCENARIO" != resolver ] || printf '%s\n' 'nameserver 10.78.0.53'
        ;;
    *)
        echo "fake ssh: unexpected command" >&2
        exit 97
        ;;
esac
EOF
chmod +x "$temporary/bin/curl" "$temporary/bin/ssh"

pass_count=0
pass() {
    pass_count=$((pass_count + 1))
    echo "PASS $1"
}
die() {
    echo "FAIL $*" >&2
    for file in output argv.log api.log; do
        [ ! -s "$state/$file" ] || { echo "--- $file" >&2; cat "$state/$file" >&2; }
    done
    exit 1
}

# run_case NAME SCENARIO EXPECTED_STATUS ARGUMENTS... runs netbird-enroll in a
# fresh state directory. Callers may set CASE_TOKEN_FILE and CASE_URL.
run_case() {
    name=$1
    scenario=$2
    expected=$3
    shift 3
    state=$temporary/state-$name
    mkdir -p "$state"
    : > "$state/created"
    : > "$state/deleted"
    : > "$state/argv.log"
    : > "$state/api.log"
    url=${CASE_URL:-https://api.netbird.io}
    status=0
    env -u NETBIRD_MANAGEMENT_URL -u NETBIRD_APPLIANCE_GROUP -u NETBIRD_SSH_USER \
        PATH="$temporary/bin:$PATH" \
        MOCK_STATE="$state" MOCK_SCENARIO="$scenario" MOCK_TOKEN="$token" \
        MOCK_KEY_PREFIX="$key_prefix" MOCK_URL="$url" MOCK_SSH_USER=dns-operator \
        NETBIRD_API_TOKEN_FILE="${CASE_TOKEN_FILE-$temporary/token}" \
        ${CASE_URL:+NETBIRD_MANAGEMENT_URL="$CASE_URL"} \
        "$repo_root/management/netbird-enroll" "$@" > "$state/output" 2>&1 || status=$?
    [ "$status" -eq "$expected" ] ||
        die "$name: exit $status, expected $expected"
    if grep -Fq -e "$token" -e "$key_prefix" "$state/output" "$state/argv.log"; then
        die "$name: a secret value reached output or command arguments"
    fi
    if [ -s "$state/created" ] && grep -vxqF -f "$state/deleted" "$state/created" &&
        [ "$scenario" != delete-fail ]; then
        die "$name: a setup key was left undeleted"
    fi
}
expect_output() {
    grep -Fq -- "$1" "$state/output" || die "$name: output lacks '$1'"
}
expect_no_key() {
    [ ! -s "$state/created" ] || die "$name: a setup key was created"
}

run_case usage-missing-mode none 2
run_case usage-unknown-option none 2 --everything
run_case usage-bad-role none 2 --role dns04
run_case usage-missing-role none 2 --role
[ ! -s "$state/argv.log" ] || die "usage errors must not reach the API or SSH"
pass usage_errors_exit_2

run_case success success 0 --role dns01
expect_output 'enrolled and verified dns01 at 10.78.1.1'
[ "$(cat "$state/created")" = key-1 ] || die "success: expected exactly one setup key"
[ "$(cat "$state/deleted")" = key-1 ] || die "success: setup key was not deleted"
grep -qx 'GET setup-keys' "$state/api.log" || die "success: deletion was not confirmed"
pass enrolls_one_node_and_deletes_the_key

run_case success-all success 0 --all
for index in 1 2 3; do
    expect_output "enrolled and verified dns0$index at 10.78.1.$index"
done
[ "$(wc -l < "$state/created" | tr -d ' ')" -eq 3 ] || die "success-all: expected three keys"
pass enrolls_all_nodes_with_distinct_keys

CASE_URL=https://netbird.example.test run_case self-hosted success 0 --role dns02
expect_output 'enrolled and verified dns02 at 10.78.1.2'
pass honors_self_hosted_management_url

CASE_URL=http://netbird.example.test run_case insecure-url none 1 --role dns01
[ ! -s "$state/argv.log" ] || die "insecure-url: contacted the API or SSH"
pass rejects_non_https_management_url

run_case already already 0 --role dns03
expect_output 'dns03 already enrolled at 10.78.1.3'
expect_no_key
pass verifies_already_enrolled_node_without_minting

CASE_TOKEN_FILE=$temporary/missing-token run_case missing-token none 1 --role dns01
expect_output 'token file'
[ ! -s "$state/argv.log" ] || die "missing-token: contacted the API or SSH"
CASE_TOKEN_FILE='' run_case unset-token none 1 --role dns01
CASE_TOKEN_FILE=$temporary/bad-token run_case invalid-token none 1 --role dns01
expect_output 'invalid NetBird API token'
[ ! -s "$state/argv.log" ] || die "invalid-token: contacted the API or SSH"
pass rejects_missing_or_invalid_token_file

run_case missing-group missing-group 1 --role dns01
expect_output 'dns-appliances'
expect_no_key
run_case ambiguous-group ambiguous-group 1 --role dns01
expect_no_key
pass rejects_missing_or_ambiguous_group

run_case key-create-fail key-create-fail 1 --role dns01
expect_output 'could not create a one-off setup key for dns01'
if grep -q 'netbird up' "$state/argv.log"; then die "key-create-fail: ran netbird up"; fi
pass stops_when_key_creation_fails

run_case up-fail up-fail 1 --role dns01
expect_output 'remote NetBird enrollment failed for dns01'
[ "$(cat "$state/deleted")" = key-1 ] || die "up-fail: setup key was not deleted"
pass deletes_key_after_remote_up_failure

check_property() {
    run_case "$1" "$1" 1 --role dns01
    expect_output "dns01 failed verification: $2"
    [ "$(cat "$state/deleted")" = key-1 ] || die "$1: setup key was not deleted"
}
check_property wrong-hostname hostname
pass rejects_wrong_hostname
check_property outside-range 'NetBird address'
pass rejects_address_outside_10_78
check_property not-in-group 'appliance group'
pass rejects_peer_outside_appliance_group
check_property dns-preference 'DNS management'
check_property client-route-preference 'client routes'
check_property server-route-preference 'server routes'
check_property ssh-preference 'SSH server'
pass rejects_dns_route_and_ssh_preference_violations
check_property routing-peer 'routing peer'
check_property routing-group 'routing peer'
pass rejects_routing_peer_by_peer_or_group
check_property resolver resolver
pass rejects_changed_resolver

run_case delete-fail delete-fail 1 --role dns01
expect_output 'enrolled and verified dns01 at 10.78.1.1'
expect_output 'setup key key-1'
pass reports_unconfirmed_key_deletion_by_id

# The policy examples carry exactly the Tailscale example's grants, as NetBird
# policy payloads with placeholder group references and no IDs.
policy_grants() {
    jq -cS '[.[] | .enabled as $enabled | .rules[]
        | select($enabled and .enabled and .action == "accept")
        | {protocol, ports: (.ports | sort), sources, destinations, bidirectional}] | sort' "$1"
}
expected_grants() {
    jq -cnS "$1 | sort"
}
[ "$(policy_grants "$repo_root/management/netbird-policy.example.json")" = "$(expected_grants '[
    {protocol:"tcp", ports:["22","53","53443","9090","9100"], sources:["<group-id:admins>"],
     destinations:["<group-id:dns-appliances>"], bidirectional:false},
    {protocol:"udp", ports:["53"], sources:["<group-id:admins>"],
     destinations:["<group-id:dns-appliances>"], bidirectional:false},
    {protocol:"tcp", ports:["53443"], sources:["<group-id:dns-appliances>"],
     destinations:["<group-id:dns-appliances>"], bidirectional:false}
]')" ] || die "appliance NetBird policy example grants differ"
[ "$(policy_grants "$repo_root/../agent/netbird-policy.example.json")" = "$(expected_grants '[
    {protocol:"tcp", ports:["22"], sources:["<group-id:admins>"],
     destinations:["<group-id:device-os-management>"], bidirectional:false}
]')" ] || die "management-host NetBird policy example grants differ"
pass policy_examples_match_the_tailscale_grants

[ "$pass_count" -eq 18 ] || die "expected 18 passing groups, got $pass_count"
echo "RESULT $pass_count/18 NetBird enrollment simulations passed"
