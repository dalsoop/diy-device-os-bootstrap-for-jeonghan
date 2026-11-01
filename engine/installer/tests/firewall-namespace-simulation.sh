#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# Kernel-level check of the appliance firewall in throwaway network
# namespaces. The ruleset is rendered by the installer step's own functions
# and loaded into an "appliance" namespace whose overlay interfaces are veth
# ends named wt0 and tailscale0; a "peer" namespace sends real packets. The
# NetBird client's behaviour is reproduced by inserting `iifname "wt0" accept`
# at the top of the appliance input and forward chains, and stand-in overlay
# tables prove that loading, reloading and stopping the firewall leaves other
# tables untouched. Nothing outside the two namespaces is changed.
#
# Network namespaces and nftables need CAP_NET_ADMIN: the script re-runs
# itself through passwordless sudo when it is not root. It fails, never skips,
# when namespaces cannot be created.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n -- "$script_dir/firewall-namespace-simulation.sh" "$@"
fi

fail() {
    echo "firewall-namespace-simulation: $*" >&2
    exit 1
}

for tool in nft ip python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

payload=$repo_root/dns-image/payload
finish_script=$repo_root/dns-image/scripts/dns-finish-install
dropin=$payload/nftables-own-table.conf
work=$(mktemp -d "${TMPDIR:-/tmp}/dns-firewall-netns.XXXXXX")
app=dns-fw-app-$$
peer=dns-fw-peer-$$
listener=
cleanup() {
    if [ -n "$listener" ]; then
        kill "$listener" 2>/dev/null || true
        wait "$listener" 2>/dev/null || true
    fi
    ip netns del "$app" 2>/dev/null || true
    ip netns del "$peer" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

# --- Render the three selections with the installer step's functions -------
mkdir -p "$work/cdrom/simple-cdd"
for number in 1 2 3; do
    printf 'role=dns0%s\naddress=10.77.5.%s\nprefix_length=16\n' "$number" "$number" \
        > "$work/cdrom/simple-cdd/dns0$number.conf"
done
python3 - "$finish_script" "$work" <<'PY'
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
for selection in tailscale netbird both; do
    case "$selection" in
        both) printf 'tailscale\nnetbird\n' > "$work/$selection.overlays" ;;
        *) printf '%s\n' "$selection" > "$work/$selection.overlays" ;;
    esac
    LAN_CIDR=10.77.0.0/16 MANAGEMENT_CIDR=10.77.0.0/24 NETBIRD_RANGE=10.78.0.0/16 \
        sh "$work/render.sh" "$payload/nftables.conf" "$work/$selection.overlays" \
        "$work/$selection.nft" || fail "rendering the $selection firewall failed"
done

# --- Namespaces: appliance interfaces wt0, tailscale0 and a LAN port --------
ip netns add "$app" || fail "cannot create network namespaces (CAP_NET_ADMIN is required)"
ip netns add "$peer" || fail "cannot create network namespaces (CAP_NET_ADMIN is required)"
in_app() { ip netns exec "$app" "$@"; }
in_peer() { ip netns exec "$peer" "$@"; }
ip -n "$app" link set lo up
ip -n "$peer" link set lo up
ip link add name wt0 netns "$app" type veth peer name nb-peer netns "$peer"
ip link add name tailscale0 netns "$app" type veth peer name ts-peer netns "$peer"
ip link add name eno1 netns "$app" type veth peer name lan-peer netns "$peer"
ip -n "$app" addr add 10.78.0.1/16 dev wt0
ip -n "$app" addr add 100.64.0.1/10 dev tailscale0
ip -n "$app" addr add 10.77.5.1/16 dev eno1
ip -n "$peer" addr add 10.78.0.2/16 dev nb-peer
ip -n "$peer" addr add 100.64.0.2/10 dev ts-peer
ip -n "$peer" addr add 10.77.0.50/16 dev lan-peer
ip -n "$peer" addr add 10.77.9.9/16 dev lan-peer
for device in wt0 tailscale0 eno1; do
    ip -n "$app" link set "$device" up
done
for device in nb-peer ts-peer lan-peer; do
    ip -n "$peer" link set "$device" up
done

cat > "$work/listen.py" <<'PY'
import pathlib
import socket
import sys
import threading
import time

def serve_tcp(server):
    while True:
        connection, _ = server.accept()
        connection.close()

def serve_udp(server):
    while True:
        data, client = server.recvfrom(512)
        server.sendto(data, client)

workers = []
for port in (int(value) for value in sys.argv[2:]):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", port))
    server.listen(64)
    workers.append(threading.Thread(target=serve_tcp, args=(server,), daemon=True))
dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dns.bind(("0.0.0.0", 53))
workers.append(threading.Thread(target=serve_udp, args=(dns,), daemon=True))
for worker in workers:
    worker.start()
pathlib.Path(sys.argv[1]).write_text("ready\n")
while True:
    time.sleep(3600)
PY
cat > "$work/probe.py" <<'PY'
import socket
import sys

protocol, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
source = sys.argv[4] if len(sys.argv) > 4 else ""
kind = socket.SOCK_STREAM if protocol == "tcp" else socket.SOCK_DGRAM
client = socket.socket(socket.AF_INET, kind)
client.settimeout(0.7)
if source:
    client.bind((source, 0))
try:
    client.connect((host, port))
    if protocol == "udp":
        client.send(b"dns-appliance-probe")
        if client.recv(512) != b"dns-appliance-probe":
            print("garbled")
            sys.exit(0)
    print("open")
except socket.timeout:
    print("dropped")
except ConnectionRefusedError:
    print("refused")
PY

# Every TCP port below has a listener, so a timeout means the firewall dropped
# the packet, not that nothing was listening.
# `ip netns exec` replaces itself with python3, so $! is the listener itself;
# its output is detached so it never holds the caller's stdout open.
ip netns exec "$app" python3 "$work/listen.py" "$work/ready" 22 53 5380 8080 9090 9100 53443 \
    > /dev/null 2>&1 < /dev/null &
listener=$!
for _ in $(seq 1 50); do
    [ -e "$work/ready" ] && break
    sleep 0.1
done
[ -e "$work/ready" ] || fail "the appliance listeners did not start"

checks=0
expect() {
    local label=$1 want=$2 protocol=$3 host=$4 port=$5 source=${6:-} got
    got=$(in_peer python3 "$work/probe.py" "$protocol" "$host" "$port" "$source")
    [ "$got" = "$want" ] ||
        fail "$label: $protocol $host:$port${source:+ from $source} is $got, expected $want"
    checks=$((checks + 1))
}

# Stand-ins for the overlay clients' own tables, each with a marker rule.
cat > "$work/stand-ins.nft" <<'EOF'
table inet netbird {
    chain netbird-rt-fwd {
        type filter hook forward priority 10; policy accept;
        iifname "wt0" accept comment "netbird stand-in"
    }
    chain netbird-acl-input {
        type filter hook input priority 10; policy accept;
        iifname "wt0" accept comment "netbird stand-in"
    }
}
table ip ts-filter {
    chain ts-input {
        type filter hook input priority 10; policy accept;
        iifname "tailscale0" accept comment "tailscale stand-in"
    }
}
EOF
in_app nft -f "$work/stand-ins.nft"
in_app nft list table inet netbird > "$work/netbird.before"
in_app nft list table ip ts-filter > "$work/ts-filter.before"
stand_ins_untouched() {
    in_app nft list table inet netbird > "$work/netbird.after" ||
        fail "$1 removed the netbird stand-in table"
    in_app nft list table ip ts-filter > "$work/ts-filter.after" ||
        fail "$1 removed the Tailscale stand-in table"
    cmp -s "$work/netbird.before" "$work/netbird.after" || fail "$1 changed the netbird stand-in table"
    cmp -s "$work/ts-filter.before" "$work/ts-filter.after" || fail "$1 changed the Tailscale stand-in table"
    grep -q 'comment "netbird stand-in"' "$work/netbird.after" || fail "$1 lost the netbird marker"
    grep -q 'comment "tailscale stand-in"' "$work/ts-filter.after" || fail "$1 lost the Tailscale marker"
}

# What the NetBird client does to every foreign input and forward filter
# chain: its interface accept at position 1. It is applied to tailscale0 as
# well, so the same check is shown to hold for either overlay.
insert_overlay_accept() {
    for chain in input forward; do
        in_app nft insert rule inet dns_appliance "$chain" iifname "\"$1\"" counter accept
    done
    in_app nft list chain inet dns_appliance input > "$work/input.listing"
    awk '/hook input/ { getline; print; exit }' "$work/input.listing" |
        grep -q "iifname \"$1\" counter" || fail "the $1 accept is not the first input rule"
}

expect_selected() {
    local interface=$1 address=$2 port
    expect "$interface DNS over UDP" open udp "$address" 53
    expect "$interface DNS over TCP" open tcp "$address" 53
    for port in 22 9090 9100 53443; do
        expect "$interface management port" open tcp "$address" "$port"
    done
    expect "$interface port outside the allowed set" dropped tcp "$address" 8080
    expect "$interface Technitium HTTP port" dropped tcp "$address" 5380
}
expect_unselected() {
    local interface=$1 address=$2
    expect "unselected $interface DNS" dropped udp "$address" 53
    expect "unselected $interface SSH" dropped tcp "$address" 22
    expect "unselected $interface port outside the allowed set" dropped tcp "$address" 8080
}
expect_lan() {
    expect "LAN DNS over UDP" open udp 10.77.5.1 53 10.77.9.9
    expect "LAN DNS over TCP" open tcp 10.77.5.1 53 10.77.9.9
    expect "LAN SSH outside management" dropped tcp 10.77.5.1 22 10.77.9.9
    expect "management SSH" open tcp 10.77.5.1 22 10.77.0.50
    expect "management port outside the allowed set" dropped tcp 10.77.5.1 8080 10.77.0.50
}

for selection in tailscale netbird both; do
    in_app nft -c -f "$work/$selection.nft" || fail "nft rejects the rendered $selection firewall"
    in_app nft -f "$work/$selection.nft" || fail "loading the $selection firewall failed"
    stand_ins_untouched "loading the $selection firewall"
    case "$selection" in
        tailscale)
            insert_overlay_accept tailscale0
            expect_selected tailscale0 100.64.0.1
            expect_unselected wt0 10.78.0.1
            ;;
        netbird)
            insert_overlay_accept wt0
            expect_selected wt0 10.78.0.1
            expect_unselected tailscale0 100.64.0.1
            ;;
        both)
            insert_overlay_accept wt0
            insert_overlay_accept tailscale0
            expect_selected wt0 10.78.0.1
            expect_selected tailscale0 100.64.0.1
            ;;
    esac
    expect_lan
done
echo "PASS overlay port limits hold with an interface accept at the top of the input chain"

# Loading is idempotent: a second load recreates exactly one copy of the table
# (dropping the inserted rules) and leaves the stand-ins alone.
in_app nft -f "$work/both.nft"
in_app nft list table inet dns_appliance > "$work/appliance.fresh"
in_app nft -f "$work/both.nft"
in_app nft list table inet dns_appliance > "$work/appliance.again"
cmp -s "$work/appliance.fresh" "$work/appliance.again" || fail "a second load changed the appliance table"
[ "$(grep -c 'hook input' "$work/appliance.again")" -eq 1 ] || fail "a second load duplicated the input chain"
stand_ins_untouched "reloading the firewall file"
echo "PASS loading the firewall twice is idempotent and leaves other tables untouched"

# Control: without the prerouting chain, the inserted accept would open every
# local port on wt0. This proves the checks above can see a bypass.
insert_overlay_accept wt0
in_app nft flush chain inet dns_appliance overlay_prerouting
in_app nft delete chain inet dns_appliance overlay_prerouting
expect "control without the prerouting chain" open tcp 10.78.0.1 8080
echo "PASS the interface accept bypasses the input chain alone (control)"

# --- nftables.service drop-in: stop and reload ------------------------------
grep -qx 'ExecStop=' "$dropin" || fail "the drop-in does not reset Debian's flush-ruleset stop"
grep -qx 'ExecReload=' "$dropin" || fail "the drop-in does not reset the reload command"
[ "$(grep -c '^ExecStop=.' "$dropin")" -eq 1 ] || fail "the drop-in needs exactly one stop command"
[ "$(grep -c '^ExecReload=.' "$dropin")" -eq 1 ] || fail "the drop-in needs exactly one reload command"
if grep -q -E '^[^#].*(flush|ruleset)' "$dropin"; then
    fail "the drop-in flushes"
fi
stop_line=$(grep '^ExecStop=.' "$dropin")
reload_line=$(grep '^ExecReload=.' "$dropin")
read -r -a stop_command <<<"${stop_line#ExecStop=}"
read -r -a reload_command <<<"${reload_line#ExecReload=}"
[ "${reload_command[*]}" = "/usr/sbin/nft -f /etc/nftables.conf" ] ||
    fail "reload does not re-apply /etc/nftables.conf"
reload_command[2]=$work/both.nft
[ -x "${stop_command[0]}" ] || fail "${stop_command[0]} is not installed here"

in_app "${stop_command[@]}" || fail "the stop command failed"
if in_app nft list table inet dns_appliance >/dev/null 2>&1; then
    fail "stop left the appliance table in place"
fi
stand_ins_untouched "stopping the firewall"
in_app "${stop_command[@]}" || fail "the stop command fails when the appliance table is absent"
stand_ins_untouched "stopping the firewall twice"
echo "PASS stop deletes only the appliance table and tolerates its absence"

in_app "${reload_command[@]}" || fail "the reload command failed"
in_app nft list table inet dns_appliance > "$work/appliance.reloaded"
cmp -s "$work/appliance.fresh" "$work/appliance.reloaded" || fail "reload did not restore the appliance table"
stand_ins_untouched "reloading the firewall"
insert_overlay_accept wt0
expect "wt0 port outside the allowed set after reload" dropped tcp 10.78.0.1 8080
expect "wt0 SSH after reload" open tcp 10.78.0.1 22
in_app "${reload_command[@]}" || fail "reloading over a running firewall failed"
stand_ins_untouched "reloading the running firewall"
echo "PASS reload re-applies the file and leaves other tables untouched"

echo "firewall namespace simulation: passed ($checks packet checks)"
