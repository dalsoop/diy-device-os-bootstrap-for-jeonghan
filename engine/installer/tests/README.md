# Tests

`install-gate-simulation.sh` runs the destructive-selection gate against an
isolated fake sysfs tree. It never opens a real block device.

The reviewed-mode cases cover:

- one exact HP/NIC/disk match selecting `/dev/sda`;
- wrong DMI identity stopping before selection;
- an erase-disabled role stopping before selection;
- two matching internal disks stopping as ambiguous;
- an additional non-matching disk being ignored;
- an undersized, removable, or USB-transport target being rejected;
- direct and Ventoy-mapped installer media resolving to their physical parent;
- the Ventoy backing disk never being selected as the target;
- unresolved, ambiguous, multi-slave, cyclic, loop, and MD installer ancestry
  failing closed;
- direct, mapper-backed, and `/dev/disk/by-uuid` mounted targets being rejected;
- active swap and unmounted sysfs holders on the target being rejected;
- leading and trailing signature clearing, synchronization, and partition-table
  refresh occurring only after acceptance;
- two interfaces with the expected MAC stopping as ambiguous;
- a completed role being blocked without a reinstall token;
- a matching generation-bound reinstall token being accepted;
- a stale reinstall token being rejected.

`repository-contract.sh` validates immutable source lock shapes (including
`verify-locks` rejecting a Simple-CDD mirror that differs from
`DEBIAN_SNAPSHOT`), required artifacts, executable modes, the enrollment
schema, the presence of the first-boot safety contracts, and that CI runs every
simulation listed here. GitHub Actions runs every simulation in this directory
plus ShellCheck and Python syntax validation.

`tailscale-enrollment-simulation.sh` and `netbird-enrollment-simulation.sh`
drive the enrollment commands with fake `curl` and `ssh`. The NetBird
simulation covers usage errors, one and all nodes, a self-hosted management
URL, a non-HTTPS URL, an already enrolled node, missing, unset, and invalid
token files, missing and ambiguous groups, key creation failure, remote `up`
failure, wrong hostname, an address outside `10.78.0.0/16`, missing group
membership, DNS, route, and SSH settings, routing peers by peer and by group, a
changed resolver, and unconfirmed key deletion, and proves that neither the
token nor any setup key reaches command arguments or output.

`appliance-update-simulation.sh` checks the offline package set, apt sources,
and configuration, renders the per-role timers through `dns-finish-install`,
and runs `dns-appliance-reboot` with `dig`, `logger`, `systemctl`, and
`in-target` replaced on `PATH` and a temporary state directory. It covers no reboot required (peers still learned), a reboot with both seen peers
answering (counter reset), a never-seen peer down (no block), a seen peer down
(skip, counter increment, journal line, no reboot), both peers down, persistence
of the seen set and counter across runs, a peer answering only the retry,
malformed state, and metrics rendering, and checks the rendered per-role
install and reboot timers (`Asia/Seoul`, no random delay, no catch-up) and
each role's executable kernel reboot-required hook.

`image-builder-simulation.sh` also covers World overlay resolution, the
conditional build records for Tailscale-only, NetBird-only, and dual
selections, the per-selection appliance install step, World/image agreement in
every direction, readiness blockers, and both Linux writers' manifest checks
with no target command reached. Every selection's install carries the AppArmor
signal rule (mode 0644) under `/etc/apparmor.d/abstractions/base.d/`. It runs the kernel hook that the install step
put in the fake target's `/etc/kernel/postinst.d` through `run-parts` with a
kernel version and image path, as a kernel package's postinst does, as root in
a private mount namespace (`sudo -n unshare --mount`) over a fresh tmpfs
`/run`. It asserts the marker text, a package list without duplicates, the
package-name fallback, no leftover temporary files, that the installed
`dns-appliance-reboot` at its default marker path does not reboot before and
does reboot after, and that a read-only `/run` is reported without failing the
kernel installation. It fails, never skips, when the namespace or mount cannot
be created.

`repository-contract.sh` also runs the documentation check over every tracked
text file; `repository-contract.sh --documentation-only <checkout>` runs only
that check. `documentation-check-simulation.sh` builds temporary Git fixtures
with one failing and one passing case per documentation pattern and proves that
a directory outside Git is rejected.

`management-simulation.sh` covers machine-readable and audited DNS planning,
saving a read-only plan only from a committed zone and never over an existing
file, plan-bound apply that rejects a wrong confirmation, plan hash, endpoint,
source commit, modified zone, live-zone drift, or replay without importing,
generation-bound reinstall authorization, and
the `/16` network prerequisite, generated first-boot recursion permissions for
the LAN and each selected overlay, the firewall rendered by
`dns-finish-install` for Tailscale-only, NetBird-only, and both (own table, no
`flush ruleset`, exact prerouting and input rules in order, source-range
guards), its rejection of unrendered markers and invalid inputs, and the
health report's per-overlay `health.json` entries and metrics with the reboot
metrics unchanged. It also verifies root-only environment-file permissions and
bootstrap-password omission after enrollment. It stubs network calls and never
contacts a DNS server.

`firewall-namespace-simulation.sh` loads the rendered firewall into a
throwaway network namespace whose veth interfaces are named `wt0`,
`tailscale0`, and `eno1`, and sends real packets from a second namespace to
listeners on every tested port. Each selection passes `nft -c`. With
`iifname "wt0" accept` (and `iifname "tailscale0" accept`) inserted at the top
of the input and forward chains, as the NetBird client does, TCP 8080 and 5380
stay dropped on the selected overlay interfaces while DNS 53 and TCP 22, 9090,
9100, 53443 answer; an unselected overlay interface reaches nothing, and the
LAN rules hold (DNS from the LAN, SSH only from the management network, TCP
8080 from neither). A control without the prerouting chain
shows the inserted rule would open TCP 8080. Loading twice, the `nftables.service`
drop-in's stop (also with the table absent), and its reload leave stand-in
`inet netbird` and `ip ts-filter` tables unchanged. It needs CAP_NET_ADMIN,
re-runs itself through passwordless `sudo`, fails rather than skips when
namespaces cannot be created, and changes nothing outside its namespaces.

`apparmor-signal-simulation.sh` compiles the image's AppArmor rule
`payload/dns-appliance-podman-signal` with the host's `apparmor_parser -Q -K`
against a temporary copy of the host's `abi`, `tunables`, and `abstractions`.
It checks that the payload is the one reviewed rule, that the host's base
abstraction includes `abstractions/base.d` and lets a profile signal itself,
and that `dns-finish-install` installs the rule at
`/etc/apparmor.d/abstractions/base.d/dns-appliance-podman-signal`. The profile
Podman generates from containers-common 0.62.2 and a probe profile that
includes only the base abstraction compile without the rule and with it, carry
the rule exactly once when it is installed, and fail to compile with a broken
copy of it. It loads nothing into the kernel, so the kernel's decision on a
real `…//&crun` label is not covered; it fails, never skips, without
`apparmor_parser`.

`media-catalog-simulation.sh` also checks capacity planning with
checksum-matched sparse cache files, a runtime artifact with a matching
manifest, an unknown runtime artifact, and a target smaller than the configured
reserve plus overhead. It also proves that an oversized unverified estimate
cannot produce a final too-small verdict when the verified subtotal still fits.
It never opens a block device.

`macos-writer-simulation.sh` replaces every macOS and block-device command with
an isolated fixture. It proves that the writer verifies the image body before
exposing the partition map, verifies the first MiB last, and does not commit or
eject after a failed body readback. It never opens a real device.

`inventory-wizard-simulation.sh` runs the guided capture against a fixture
sysfs and mount table. It proves that only wired interfaces and internal,
non-removable, non-USB disks other than the inventory medium are offered; that
the one saved file holds hashes and `destructive_install_enabled=false`; and
that a wrong confirmation, ended input, repeated invalid numbers, a non-root
user, an unmounted or read-only medium, or a missing internal disk saves
nothing. An existing file is replaced only after `overwrite`. It does not prove
that Debian Live renders Hangul or that real HP sysfs values match the fixture.

`status-monitor-simulation.sh` runs the status monitor's `--check-once`
against a fake node exporter on `127.0.0.1:9100`, a name resolved through the
hosts file, an unused loopback address, and an unresolvable `.invalid` name. It
proves that the reboot metrics are parsed (including a zero last-skip time read
as never skipped), that unknown values are `null`, that name-resolution failure
is reported per node, that the monitor only sends `GET /metrics`, that the HTML
page highlights only a node with skipped reboots, and that an `address` field or
an invalid host is rejected. It contacts no real node.

This simulation is necessary but not sufficient. It does not replace building
the ISO, booting Debian Installer under BIOS and UEFI, or the physical `dns01`
pilot.
