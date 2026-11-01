#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# Unattended Debian upgrades and the peer-guarded staggered reboot: offline
# package set, apt sources and configuration, per-role install and reboot
# timers rendered by dns-finish-install, the reboot decision, and the reboot
# metrics exported by the health script. Nothing here touches a real system:
# dig, logger, systemctl and in-target are replaced on PATH.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
installer_dir=$repo_root/dns-image
payload=$installer_dir/payload
finish_script=$installer_dir/scripts/dns-finish-install
reboot_script=$payload/dns-appliance-reboot
temporary=$(mktemp -d "${TMPDIR:-/tmp}/dns-appliance-update-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

simulation_fail() {
    echo "appliance-update-simulation: $*" >&2
    exit 1
}

# --- Offline package set and installer notes -------------------------------
grep -qx 'unattended-upgrades' "$installer_dir/simple-cdd/profiles/dns.packages" ||
    simulation_fail "unattended-upgrades is not in dns.packages"
if grep -q -e 'unattended-upgrades$' -e 'unattended-upgrades *(pkgsel' "$installer_dir/installer-target-packages"; then
    simulation_fail "installer-target-packages still says unattended-upgrades is not installed"
fi

# --- Static payload ---------------------------------------------------------
cat > "$temporary/expected.sources" <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
cmp -s "$temporary/expected.sources" "$payload/debian.sources" ||
    simulation_fail "debian.sources is not the reviewed HTTPS deb822 source set"

apt_conf=$payload/apt-unattended-upgrades.conf
for line in 'APT::Periodic::Update-Package-Lists "always";' \
    'APT::Periodic::Unattended-Upgrade "always";' \
    'Unattended-Upgrade::Automatic-Reboot "false";'; do
    grep -qxF "$line" "$apt_conf" || simulation_fail "APT configuration lacks: $line"
done
if grep -q -e 'Origins-Pattern' -e 'Allowed-Origins' -e 'Package-Blacklist' "$apt_conf"; then
    simulation_fail "APT configuration replaces Debian's default origins"
fi

refresh=$payload/apt-daily-upgrade-refresh.conf
grep -qx '\[Service\]' "$refresh" || simulation_fail "upgrade refresh drop-in lacks [Service]"
grep -qx 'ExecStartPre=/usr/lib/apt/apt.systemd.daily update' "$refresh" ||
    simulation_fail "the install run does not refresh package lists first"

service=$payload/dns-appliance-reboot.service
grep -qx 'Type=oneshot' "$service" || simulation_fail "reboot service is not oneshot"
grep -qx 'ExecStart=/usr/local/sbin/dns-appliance-reboot window' "$service" ||
    simulation_fail "reboot service does not run the window decision"
grep -q '^After=.*apt-daily-upgrade.service' "$service" ||
    simulation_fail "reboot service can start while the upgrade run is active"

for listed in ../payload/debian.sources ../payload/apt-unattended-upgrades.conf \
    ../payload/apt-daily-upgrade-refresh.conf ../payload/apt-daily-upgrade.timer.conf \
    ../payload/dns-appliance-reboot ../payload/dns-appliance-reboot.service \
    ../payload/dns-appliance-reboot.timer ../payload/dns-appliance-reboot-required; do
    grep -qx "$listed" "$installer_dir/simple-cdd/profiles/default.extra" ||
        simulation_fail "default.extra does not list $listed"
done

# --- Per-role rendering by dns-finish-install ------------------------------
# The literal shell text is matched; it is not expanded here.
# shellcheck disable=SC2016
grep -qx 'install_unattended_upgrades "$ROLE"' "$finish_script" ||
    simulation_fail "dns-finish-install does not install the update schedule for its role"
python3 - "$finish_script" "$temporary/update-functions.sh" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
blocks = []
for name in ("update_schedule", "peer_address", "install_unattended_upgrades"):
    match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    assert match, name + " is missing from dns-finish-install"
    blocks.append(match.group())
pathlib.Path(sys.argv[2]).write_text("\n".join(blocks) + "\n")
PY

make_root() {
    root=$1
    rm -rf "$root"
    mkdir -p "$root/cdrom/simple-cdd" "$root/bin" "$root/target/etc/apt" \
        "$root/target/etc/dns-appliance" "$root/target/etc/systemd/system" \
        "$root/target/usr/local/sbin"
    cp "$payload"/* "$root/cdrom/simple-cdd/"
    for number in 1 2 3; do
        printf 'role=dns0%s\naddress=10.77.5.%s\nprefix_length=16\n' "$number" "$number" \
            > "$root/cdrom/simple-cdd/dns0$number.conf"
    done
    printf '%s\n' 'deb cdrom:[Debian GNU/Linux 13.7.0 _Trixie_]/ trixie main non-free-firmware' \
        '' > "$root/target/etc/apt/sources.list"
    cat > "$root/bin/in-target" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FINISH_LOG"
EOF
    chmod 0755 "$root/bin/in-target"
    {
        printf 'set -eu\n'
        sed -e "s#/cdrom/#$root/cdrom/#g" -e "s#/target/#$root/target/#g" \
            "$temporary/update-functions.sh"
        # The generated script expands its own argument.
        # shellcheck disable=SC2016
        printf 'install_unattended_upgrades "$1"\n'
    } > "$root/render.sh"
}
render() {
    root=$temporary/render-$1
    make_root "$root"
    PATH="$root/bin:$PATH" FINISH_LOG="$root/in-target.log" sh "$root/render.sh" "$1" \
        > "$root/render.log" 2>&1
}

for case_line in 'dns01 02:00 03:00 dns02 10.77.5.2 dns03 10.77.5.3' \
    'dns02 02:30 03:30 dns01 10.77.5.1 dns03 10.77.5.3' \
    'dns03 03:00 04:00 dns01 10.77.5.1 dns02 10.77.5.2'; do
    read -r role install_time reboot_time peer_a address_a peer_b address_b <<<"$case_line"
    render "$role" || simulation_fail "$role rendering failed: $(cat "$temporary/render-$role/render.log")"
    target=$temporary/render-$role/target
    upgrade_timer=$target/etc/systemd/system/apt-daily-upgrade.timer.d/60-dns-appliance.conf
    reboot_timer=$target/etc/systemd/system/dns-appliance-reboot.timer
    [ -f "$upgrade_timer" ] || simulation_fail "$role has no install timer drop-in"
    [ -f "$reboot_timer" ] || simulation_fail "$role has no reboot timer"
    if grep -q '@@' "$upgrade_timer" "$reboot_timer"; then
        simulation_fail "$role timers contain unrendered placeholders"
    fi
    calendar=$(grep '^OnCalendar=' "$upgrade_timer" | tr '\n' '|')
    [ "$calendar" = "OnCalendar=|OnCalendar=*-*-* $install_time:00 Asia/Seoul|" ] ||
        simulation_fail "$role install schedule is '$calendar'"
    calendar=$(grep '^OnCalendar=' "$reboot_timer" | tr '\n' '|')
    [ "$calendar" = "OnCalendar=*-*-* $reboot_time:00 Asia/Seoul|" ] ||
        simulation_fail "$role reboot schedule is '$calendar'"
    for timer in "$upgrade_timer" "$reboot_timer"; do
        grep -qx 'RandomizedDelaySec=0' "$timer" || simulation_fail "$role ${timer##*/} has a random delay"
        grep -qx 'Persistent=false' "$timer" || simulation_fail "$role ${timer##*/} catches up after downtime"
        [ "$(grep -c '^RandomizedDelaySec=' "$timer")" -eq 1 ] ||
            simulation_fail "$role ${timer##*/} sets the random delay more than once"
    done
    grep -qx 'WantedBy=timers.target' "$reboot_timer" || simulation_fail "$role reboot timer is not installable"
    grep -qx 'systemctl enable dns-appliance-reboot.timer' "$temporary/render-$role/in-target.log" ||
        simulation_fail "$role reboot timer is not enabled"
    printf '%s %s\n%s %s\n' "$peer_a" "$address_a" "$peer_b" "$address_b" > "$temporary/expected-peers"
    cmp -s "$temporary/expected-peers" "$target/etc/dns-appliance/peers" ||
        simulation_fail "$role peers are '$(cat "$target/etc/dns-appliance/peers")'"
    cmp -s "$payload/debian.sources" "$target/etc/apt/sources.list.d/debian.sources" ||
        simulation_fail "$role apt sources are not installed"
    cmp -s "$payload/apt-unattended-upgrades.conf" \
        "$target/etc/apt/apt.conf.d/52dns-appliance-unattended-upgrades" ||
        simulation_fail "$role APT configuration is not installed"
    cmp -s "$refresh" "$target/etc/systemd/system/apt-daily-upgrade.service.d/60-dns-appliance.conf" ||
        simulation_fail "$role install run does not refresh lists"
    cmp -s "$service" "$target/etc/systemd/system/dns-appliance-reboot.service" ||
        simulation_fail "$role reboot service is not installed"
    [ -x "$target/usr/local/sbin/dns-appliance-reboot" ] || simulation_fail "$role reboot script is not installed"
    cmp -s "$payload/dns-appliance-reboot-required" \
        "$target/etc/kernel/postinst.d/zz-dns-appliance-reboot-required" ||
        simulation_fail "$role kernel reboot-required hook is not installed"
    [ -x "$target/etc/kernel/postinst.d/zz-dns-appliance-reboot-required" ] ||
        simulation_fail "$role kernel reboot-required hook is not executable"
    if grep -q '^deb cdrom:' "$target/etc/apt/sources.list"; then
        simulation_fail "$role keeps the installation medium as an apt source"
    fi
    grep -q '^# deb cdrom:' "$target/etc/apt/sources.list" ||
        simulation_fail "$role lost the disabled installation-medium line"
done

if render dns04; then
    simulation_fail "an unknown role received an update schedule"
fi
root=$temporary/render-bad-peer
make_root "$root"
printf 'role=dns02\naddress=10.77.5.256\n' > "$root/cdrom/simple-cdd/dns02.conf"
if PATH="$root/bin:$PATH" FINISH_LOG="$root/in-target.log" sh "$root/render.sh" dns01 \
    > "$root/render.log" 2>&1; then
    simulation_fail "an invalid peer address was accepted"
fi
make_root "$root"
printf 'role=dns02\naddress=10.77.5.2\naddress=10.77.5.9\n' > "$root/cdrom/simple-cdd/dns02.conf"
if PATH="$root/bin:$PATH" FINISH_LOG="$root/in-target.log" sh "$root/render.sh" dns01 \
    > "$root/render.log" 2>&1; then
    simulation_fail "an ambiguous peer address was accepted"
fi

# --- Reboot decision --------------------------------------------------------
sim=$temporary/reboot
mkdir -p "$sim/bin" "$sim/state"
printf 'dns02 10.77.5.2\ndns03 10.77.5.3\n' > "$sim/peers"
# dig answers for addresses listed in SIM_UP; SIM_FLAKY answers only its
# second attempt. Every attempt is recorded with its arguments.
cat > "$sim/bin/dig" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$SIM_DIG_LOG"
server=
for argument in "$@"; do
    case "$argument" in @*) server=${argument#@} ;; esac
done
[ -n "$server" ] || exit 9
if [ -n "${SIM_FLAKY:-}" ] && [ "$server" = "$SIM_FLAKY" ]; then
    count=$(grep -c -F "@$server " "$SIM_DIG_LOG" || true)
    [ "$count" -ge 2 ] || exit 9
    printf '127.0.0.1\n'
    exit 0
fi
case " ${SIM_UP:-} " in
    *" $server "*) printf '127.0.0.1\n' ;;
    *) exit 9 ;;
esac
EOF
cat > "$sim/bin/logger" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SIM_JOURNAL"
EOF
cat > "$sim/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SIM_REBOOTS"
EOF
chmod 0755 "$sim/bin/dig" "$sim/bin/logger" "$sim/bin/systemctl"

window() {
    # window <reboot-required yes|no> <answering addresses> [flaky address]
    : > "$sim/dig.log"
    : > "$sim/journal"
    : > "$sim/reboots"
    if [ "$1" = yes ]; then
        printf '*** System restart required ***\n' > "$sim/reboot-required"
    else
        rm -f "$sim/reboot-required"
    fi
    PATH="$sim/bin:$PATH" SIM_DIG_LOG="$sim/dig.log" SIM_JOURNAL="$sim/journal" \
        SIM_REBOOTS="$sim/reboots" SIM_UP="$2" SIM_FLAKY="${3:-}" \
        DNS_APPLIANCE_REBOOT_STATE_DIR="$sim/state" \
        DNS_APPLIANCE_REBOOT_REQUIRED_FILE="$sim/reboot-required" \
        DNS_APPLIANCE_PEERS_FILE="$sim/peers" \
        "$reboot_script" window > "$sim/window.log" 2>&1 ||
        simulation_fail "reboot window failed: $(cat "$sim/window.log")"
}
metrics() {
    PATH="$sim/bin:$PATH" \
        DNS_APPLIANCE_REBOOT_STATE_DIR="$sim/state" \
        DNS_APPLIANCE_REBOOT_REQUIRED_FILE="$sim/reboot-required" \
        DNS_APPLIANCE_PEERS_FILE="$sim/peers" \
        "$reboot_script" metrics > "$sim/metrics.prom" ||
        simulation_fail "reboot metrics failed"
}
metric() {
    awk -v name="$1" '$1 == name { print $2 }' "$sim/metrics.prom"
}
seen() {
    tr '\n' ' ' < "$sim/state/reboot-seen-peers"
}
skips() {
    cat "$sim/state/reboot-skips-consecutive"
}
assert_rebooted() {
    [ "$(cat "$sim/reboots")" = reboot ] || simulation_fail "$1: no reboot was issued"
}
assert_no_reboot() {
    [ ! -s "$sim/reboots" ] || simulation_fail "$1: a reboot was issued"
}

# A state directory without any run exports zeros.
metrics
[ "$(metric dns_appliance_reboot_pending)" = 0 ] || simulation_fail "fresh pending metric is not 0"
[ "$(metric dns_appliance_reboot_skipped_consecutive)" = 0 ] || simulation_fail "fresh skip metric is not 0"
[ "$(metric dns_appliance_reboot_last_skip_timestamp_seconds)" = 0 ] ||
    simulation_fail "fresh last-skip metric is not 0"
for name in dns_appliance_reboot_pending dns_appliance_reboot_skipped_consecutive \
    dns_appliance_reboot_last_skip_timestamp_seconds; do
    grep -qx "# TYPE $name gauge" "$sim/metrics.prom" || simulation_fail "$name has no gauge type"
done

# Reboot required, dns02 answers, dns03 has never answered: the never-seen
# peer does not block.
window yes '10.77.5.2'
assert_rebooted "never-seen peer down"
[ "$(seen)" = 'dns02 ' ] || simulation_fail "seen set after the first window is '$(seen)'"
[ "$(skips)" = 0 ] || simulation_fail "counter after a reboot is not 0"
grep -q 'rebooting' "$sim/journal" || simulation_fail "the reboot was not logged"
# Every probe is a UDP query with a short timeout; a silent peer is retried once.
grep -qx '+notcp +time=2 +tries=1 +short @10.77.5.2 localhost A' "$sim/dig.log" ||
    simulation_fail "peer probe arguments are '$(head -n 1 "$sim/dig.log")'"
[ "$(grep -c -F '@10.77.5.3 ' "$sim/dig.log")" -eq 2 ] ||
    simulation_fail "a silent peer was not probed exactly twice"
[ "$(grep -c -F '@10.77.5.2 ' "$sim/dig.log")" -eq 1 ] ||
    simulation_fail "an answering peer was probed again"

# No reboot required: peers are still learned and nothing reboots.
window no '10.77.5.2 10.77.5.3'
assert_no_reboot "no reboot required"
[ "$(seen)" = 'dns02 dns03 ' ] || simulation_fail "peers were not learned without a pending reboot"
[ "$(skips)" = 0 ] || simulation_fail "the counter changed without a pending reboot"

# Required with both seen peers up: reboot, counter reset.
window yes '10.77.5.2 10.77.5.3'
assert_rebooted "both seen peers up"
[ "$(skips)" = 0 ] || simulation_fail "the counter was not reset by a reboot"

# A seen peer down: skip, counter +1, journal names the peer, no reboot.
before=$(date +%s)
window yes '10.77.5.2'
after=$(date +%s)
assert_no_reboot "seen peer down"
[ "$(skips)" = 1 ] || simulation_fail "the counter after one skip is '$(skips)'"
last_skip=$(cat "$sim/state/reboot-last-skip")
if [ "$last_skip" -lt "$before" ] || [ "$last_skip" -gt "$after" ]; then
    simulation_fail "the skip time $last_skip is outside the run"
fi
grep -q 'skipped.*dns03 (10.77.5.3)' "$sim/journal" || simulation_fail "the skip does not name dns03"
if grep -q 'dns02 (10.77.5.2)' "$sim/journal"; then
    simulation_fail "the skip names an answering peer"
fi
[ "$(seen)" = 'dns02 dns03 ' ] || simulation_fail "a failing peer left the seen set"

# Both seen peers down: skip again, both named.
window yes ''
assert_no_reboot "both peers down"
[ "$(skips)" = 2 ] || simulation_fail "the counter after two skips is '$(skips)'"
grep -q 'dns02 (10.77.5.2)' "$sim/journal" || simulation_fail "the double skip does not name dns02"
grep -q 'dns03 (10.77.5.3)' "$sim/journal" || simulation_fail "the double skip does not name dns03"
last_skip=$(cat "$sim/state/reboot-last-skip")

# No reboot required with both down keeps the counter and the seen set.
window no ''
assert_no_reboot "no reboot required, both down"
[ "$(skips)" = 2 ] || simulation_fail "the counter was not kept without a pending reboot"
[ "$(seen)" = 'dns02 dns03 ' ] || simulation_fail "seen peers are not permanent"

metrics
[ "$(metric dns_appliance_reboot_pending)" = 0 ] || simulation_fail "pending metric without a pending reboot"
[ "$(metric dns_appliance_reboot_skipped_consecutive)" = 2 ] || simulation_fail "skip metric is not 2"
[ "$(metric dns_appliance_reboot_last_skip_timestamp_seconds)" = "$last_skip" ] ||
    simulation_fail "last-skip metric does not match the recorded skip"

# A peer that answers only the retry counts as answering; the reboot resets
# the counter and keeps the last skip time.
window yes '10.77.5.3' 10.77.5.2
assert_rebooted "retried peer answers"
[ "$(grep -c -F '@10.77.5.2 ' "$sim/dig.log")" -eq 2 ] || simulation_fail "the flaky peer was not retried"
[ "$(skips)" = 0 ] || simulation_fail "the counter was not reset after the retried probe"
metrics
[ "$(metric dns_appliance_reboot_pending)" = 1 ] || simulation_fail "pending metric with a pending reboot"
[ "$(metric dns_appliance_reboot_skipped_consecutive)" = 0 ] || simulation_fail "skip metric after reset"
[ "$(metric dns_appliance_reboot_last_skip_timestamp_seconds)" = "$last_skip" ] ||
    simulation_fail "the last skip time was not kept"

# No temporary state files are left behind.
leftovers=$(find "$sim/state" -name '*.tmp*' | wc -l)
[ "$leftovers" -eq 0 ] || simulation_fail "temporary state files remain"

# A malformed peer list or state stops without rebooting.
printf 'dns04 10.77.5.4\n' > "$sim/peers.bad"
rm -f "$sim/reboots"
if PATH="$sim/bin:$PATH" SIM_DIG_LOG="$sim/dig.log" SIM_JOURNAL="$sim/journal" \
    SIM_REBOOTS="$sim/reboots" SIM_UP='10.77.5.4' \
    DNS_APPLIANCE_REBOOT_STATE_DIR="$sim/state" \
    DNS_APPLIANCE_REBOOT_REQUIRED_FILE="$sim/reboot-required" \
    DNS_APPLIANCE_PEERS_FILE="$sim/peers.bad" \
    "$reboot_script" window > "$sim/window.log" 2>&1; then
    simulation_fail "a malformed peer list was accepted"
fi
[ ! -s "$sim/reboots" ] || simulation_fail "a malformed peer list rebooted"
printf 'many\n' > "$sim/state/reboot-skips-consecutive"
if PATH="$sim/bin:$PATH" SIM_DIG_LOG="$sim/dig.log" SIM_JOURNAL="$sim/journal" \
    SIM_REBOOTS="$sim/reboots" SIM_UP='10.77.5.2 10.77.5.3' \
    DNS_APPLIANCE_REBOOT_STATE_DIR="$sim/state" \
    DNS_APPLIANCE_REBOOT_REQUIRED_FILE="$sim/reboot-required" \
    DNS_APPLIANCE_PEERS_FILE="$sim/peers" \
    "$reboot_script" window > "$sim/window.log" 2>&1; then
    simulation_fail "a malformed skip counter was accepted"
fi
[ ! -s "$sim/reboots" ] || simulation_fail "a malformed skip counter rebooted"
if "$reboot_script" > /dev/null 2>&1; then
    simulation_fail "the reboot script ran without a subcommand"
fi

# --- Health script exports the reboot metrics -------------------------------
health=$payload/dns-appliance-health
grep -q -F '/usr/local/sbin/dns-appliance-reboot metrics' "$health" ||
    simulation_fail "the health script does not export the reboot metrics"
# The literal shell text is matched; it is not expanded here.
# shellcheck disable=SC2016
grep -q -F 'reboot_metrics=$metrics_dir/dns-appliance-reboot.prom' "$health" ||
    simulation_fail "the health script does not write the reboot metrics to the textfile directory"
# shellcheck disable=SC2016
grep -q -F 'mv "$reboot_metrics.tmp" "$reboot_metrics"' "$health" ||
    simulation_fail "the health script does not write the reboot metrics atomically"

echo "RESULT appliance update simulation passed: package set, apt sources and configuration, per-role install and reboot timers, seen-peer reboot guard, skip persistence and reboot metrics"
