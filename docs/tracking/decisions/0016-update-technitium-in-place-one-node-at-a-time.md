# 0016: Update Technitium In Place From the Locked Archive, One Node at a Time

- Status: Accepted
- Date: 2026-11-06

## Context

The three DNS appliances run Technitium as one cluster from a container image
that the installation embeds. Decision 0014 left Technitium outside unattended
updates, and the repository changed it only through a reviewed lock update, a
new image, and a reinstall.

On 2026-11-06 the cluster ran Technitium 15.6.1. Upstream issue #2233 (the
authentication configuration is not saved after a web-console login, and a zone
without permission entries then stops startup with a `NullReferenceException`
in `InspectAndFixZonePermissions`) stopped `dns01` that day. Technitium 15.6.2,
released on 2026-10-17, fixes it, and also fixes several cluster
configuration-sync problems, a missing zone-boundary check, and resource
exhaustion from a stream of empty UDP packets.

A reinstall replaces a whole node to change one container image: new media, a
person at the machine, an erase, first-boot enrollment, overlay re-enrollment
after removing the stale peer, and a cluster rejoin, one node at a time.

## Decision

An installed node's Technitium version changes in place, by hand, one node at a
time, with the procedure "Update Technitium in place" in `docs/operations.md`:

- The version and digests come only from the reviewed lock on `main`. The build
  host fetches the archive with `fetch-locked-sources`, which checks the
  registry digest and the archive digest against the lock.
- The node receives that archive, not a registry pull. Its SHA-256 is compared
  with the build host's value, `podman load` installs it, and the loaded
  image's digest is compared with the lock. The node's
  `/etc/dns-appliance/sources.env` Technitium lines then name the new version,
  and the service restarts.
- The Secondaries are updated before the Primary. Each node must pass the
  service, log, AppArmor, canary, SOA, and cluster checks and run 30 minutes
  without a restart before the next one starts.
- Each node keeps its previous `sources.env`, a copy of its Technitium
  configuration taken while the service was stopped, and the previous image
  until all three nodes have run the new version for a day; rollback restores
  them.

Images built from the same lock carry the same version for later
installations. Tailscale and NetBird still change only through a new image and
a reinstall.

## Alternatives

- Reinstalling every node was rejected for a container image change because
  it needs physical access and repeats enrollment and cluster joining.
- Pulling the image on each node was rejected because the appliances' only
  Internet dependency is the Debian archive, and the build host already
  verifies the archive against the lock.
- Podman's automatic updates were rejected because they follow a tag, not a
  reviewed digest.
- Updating the Primary first was rejected because the Primary holds the
  cluster's zones and configuration; it moves only after two nodes have run the
  new version.

## Consequences

An installed node can run a newer Technitium than the image it was installed
from; its `sources.env` names the running version, and `status.md` records
each node's update. A configuration written by the new version is not assumed
readable by the old one, so rollback restores the copy taken before the update
and loses any change made after it; no DNS or cluster change is made during the
rollout. The steps are manual and leave only the session record, as other
management operations do.
