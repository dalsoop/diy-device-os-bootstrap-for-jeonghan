# 0014: Install Debian Updates Unattended and Reboot One Node at a Time Behind a Seen-Peer Guard

- Status: Accepted
- Date: 2026-11-01

## Context

The DNS appliances are installed offline from a dated Debian snapshot. Kernel
and other security fixes published after that snapshot reach a node only
through the Debian archive. The three nodes serve the home's DNS together, so
an update that requires a reboot must never take more than one node down at a
time, and a reboot must not happen while the other nodes are already failing.
During the one-at-a-time rollout, the peers of the first node do not exist
yet, and that must not block its patching.

## Decision

`unattended-upgrades` is part of the offline package set. The installed system
uses HTTPS deb822 sources for `trixie`, `trixie-updates`, and `trixie-security`
signed by `debian-archive-keyring`, with the installer's cdrom source
commented out. Debian's default origins apply (stable point release and
security); the package's own automatic reboot is disabled.

Install and reboot times are fixed per role in `Asia/Seoul` with no random
delay: install at dns01 02:00, dns02 02:30, dns03 03:00, each one hour before
the role's reboot window at dns01 03:00, dns02 03:30, dns03 04:00. The package
lists are refreshed immediately before each install run. Neither timer runs a
missed time at boot.

At each reboot window, `dns-appliance-reboot` probes both peer roles with a
DNS query (UDP, 2-second timeout, retried once) and adds every peer that
answers to a persistent seen set. A reboot happens only when
`/run/reboot-required` exists and no seen peer fails to answer; a peer that
has never answered does not block. A blocked window does not reboot: it logs
the failing peers to the journal, increments a persistent consecutive-skip
counter, and records the skip time. The health timer exports
`dns_appliance_reboot_pending`, `dns_appliance_reboot_skipped_consecutive`,
and `dns_appliance_reboot_last_skip_timestamp_seconds`, and the status monitor
shows them.

Overlay clients and Technitium are not Debian packages and are not updated
this way. They change only through a reviewed lock update and image rebuild.

## Alternatives

- Debian's default randomized timers were rejected because random install and
  reboot times can overlap across nodes and delay a fix by a day.
- unattended-upgrades' own automatic reboot was rejected because it cannot
  check that the peers still answer DNS.
- Blocking on every peer, including never-seen ones, was rejected because the
  first installed node would never reboot during the rollout.
- Running a missed window at boot was rejected because a reboot or a service
  restart at boot time breaks the stagger.
- Adding vendor apt repositories for the overlay clients or Technitium was
  rejected because it adds unreviewed external trust roots to every node.

## Consequences

The appliances reach the Debian archive over the Internet for updates.
Patches published during the day are installed and rebooted into the same
night, one node at a time. A node whose seen peer is down keeps skipping its
reboot, which is visible in the journal, the metrics, and the status monitor,
and an operator must resolve it. A night missed because a node was off waits
for the next day's window. A permanently removed peer stays in the seen set
and keeps blocking until its state is cleared on the remaining nodes.
