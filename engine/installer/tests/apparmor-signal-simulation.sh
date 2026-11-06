#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# Parser-level check of the appliance's AppArmor signal rule. Technitium runs
# under the containers-default profile that Podman generates, stacked with
# crun's because the container sets no-new-privileges. The base abstraction's
# `signal peer=@{profile_name},` does not match the stacked label, so the .NET
# runtime's signals to itself are denied and it aborts. The image installs
# payload/dns-appliance-podman-signal into abstractions/base.d, which the base
# abstraction includes.
#
# A copy of the host's AppArmor policy tree (abi, tunables, abstractions) is
# taken into a temporary directory. The profile Podman generates (containers-
# common 0.62.2, the version Debian 13's Podman 5.4.2 uses) and the probe
# profile the live nodes were checked with are compiled with `apparmor_parser
# -Q -K` against that copy: without the rule, with it, and with a broken copy
# of it. Nothing is loaded into the kernel and no host file is changed.
# The kernel's decision on a real stacked label is not exercised here.
#
# Needs apparmor_parser and the host's /etc/apparmor.d policy; fails, never
# skips, without them.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
rule_file=$repo_root/dns-image/payload/dns-appliance-podman-signal
finish_script=$repo_root/dns-image/scripts/dns-finish-install
rule='signal peer=@{profile_name}//&{crun,podman},'
installed=/etc/apparmor.d/abstractions/base.d/dns-appliance-podman-signal
host_policy=${APPARMOR_SIMULATION_POLICY:-/etc/apparmor.d}

fail() {
    echo "apparmor-signal-simulation: $*" >&2
    exit 1
}

parser=$(PATH="$PATH:/usr/sbin:/sbin" command -v apparmor_parser) ||
    fail "apparmor_parser is required"
for required in tunables/global abstractions/base; do
    [ -r "$host_policy/$required" ] || fail "$host_policy/$required is required"
done
# The rule only takes effect through the base abstraction's include.
grep -Eq '^[[:space:]]*#?include if exists <abstractions/base\.d>' "$host_policy/abstractions/base" ||
    fail "the host's base abstraction does not include abstractions/base.d"
grep -Eq '^[[:space:]]*signal peer=@\{profile_name\},' "$host_policy/abstractions/base" ||
    fail "the host's base abstraction no longer lets a profile signal itself"

work=$(mktemp -d "${TMPDIR:-/tmp}/dns-apparmor-signal.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# --- The payload is exactly the reviewed rule and one comment ---------------
[ "$(wc -l < "$rule_file")" -eq 2 ] || fail "the payload is not two lines"
[ "$(grep -Ev '^[[:space:]]*(#|$)' "$rule_file")" = "$rule" ] ||
    fail "the payload's only rule is not '$rule'"
grep -q -F "$installed" "$finish_script" ||
    fail "dns-finish-install does not install the rule as $installed"

# --- A private copy of the host policy without any base.d rule --------------
policy=$work/policy
mkdir -p "$policy"
for directory in abi tunables abstractions; do
    if [ -d "$host_policy/$directory" ]; then
        cp -R "$host_policy/$directory" "$policy/$directory"
    fi
done
rm -rf "$policy/abstractions/base.d"

# The profile Podman renders from containers-common 0.62.2's template when
# tunables/global and abstractions/base exist and the parser is 2.8.96 or newer.
cat > "$work/containers-default" <<'EOF'
#include <tunables/global>

profile containers-default-0.62.2 flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  network,
  capability,
  file,
  umount,

  # Allow signals from privileged profiles and from within the same profile
  signal (receive) peer=unconfined,
  signal (send,receive) peer=containers-default-0.62.2,
  # Allow certain signals from OCI runtimes (podman, runc and crun)
  signal (receive) peer={/usr/bin/,/usr/sbin/,}runc,
  signal (receive) peer={/usr/bin/,/usr/sbin/,}crun*,
  signal (receive) set=(int, quit, kill, term) peer={/usr/bin/,/usr/sbin/,}podman,

  deny @{PROC}/* w,   # deny write for all files directly in /proc (not in a subdir)
  # deny write to files not in /proc/<number>/** or /proc/sys/**
  deny @{PROC}/{[^1-9],[^1-9][^0-9],[^1-9s][^0-9y][^0-9s],[^1-9][^0-9][^0-9][^0-9]*}/** w,
  deny @{PROC}/sys/[^k]** w,  # deny /proc/sys except /proc/sys/k* (effectively /proc/sys/kernel)
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]**} w,  # deny everything except shm* in /proc/sys/kernel/
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/kcore rwklx,

  deny mount,

  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/kernel/security/** rwklx,

  # suppress ptrace denials when using 'ps' inside a container
  ptrace (trace,read) peer=containers-default-0.62.2,
}
EOF
# The probe the live nodes were checked with.
printf 'include <tunables/global>\nprofile dns-appliance-probe {\n  include <abstractions/base>\n}\n' \
    > "$work/probe"

compile() {
    "$parser" --base "$policy" -Q -K "$1" > "$work/compile.log" 2>&1
}
# Prints how many lines of the expanded profile carry the rule.
rule_count() {
    "$parser" --base "$policy" -Q -K -p "$1" 2> "$work/preprocess.log" |
        awk -v rule="$rule" '{ sub(/^[[:space:]]+/, "") } $0 == rule { n++ } END { print n + 0 }'
}

# --- Without the rule: both profiles compile and neither carries it ---------
for profile in containers-default probe; do
    compile "$work/$profile" ||
        fail "the $profile profile does not compile without the rule: $(cat "$work/compile.log")"
    count=$(rule_count "$work/$profile") ||
        fail "the $profile profile cannot be expanded: $(cat "$work/preprocess.log")"
    [ "$count" -eq 0 ] || fail "the $profile profile carries the rule before it is installed"
done

# --- With the rule installed where the image puts it ------------------------
mkdir -p "$policy/abstractions/base.d"
cp "$rule_file" "$policy/abstractions/base.d/dns-appliance-podman-signal"
for profile in containers-default probe; do
    compile "$work/$profile" ||
        fail "the $profile profile does not compile with the rule: $(cat "$work/compile.log")"
    count=$(rule_count "$work/$profile") ||
        fail "the $profile profile cannot be expanded: $(cat "$work/preprocess.log")"
    [ "$count" -eq 1 ] || fail "the $profile profile carries the rule $count times, not once"
done

# --- A broken rule in the same place stops compilation ---------------------
# This proves the compile step reads the base.d file at all.
sed 's/,$//' "$rule_file" > "$policy/abstractions/base.d/dns-appliance-podman-signal"
for profile in containers-default probe; do
    if compile "$work/$profile"; then
        fail "the $profile profile compiled with a broken rule in base.d"
    fi
done

echo "apparmor signal simulation: passed ($("$parser" --version | head -n 1))"
