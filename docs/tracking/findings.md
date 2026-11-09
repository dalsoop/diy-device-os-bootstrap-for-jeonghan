# Findings

## Technitium 15.6.1 stops at startup after a web-console login

Upstream issue #2233: Technitium 15.6.1 does not save the authentication
configuration (`auth.config`) after a web-console login, and at the next start
a zone without permission entries stops startup with a
`NullReferenceException` in `InspectAndFixZonePermissions`. On 2026-11-06 this
stopped `dns01`. The reverse zone `77.10.in-addr.arpa` was removed to bring the
node back, so it is not live: `dig -x` for site addresses gets no answer from
the cluster, although `burn-history/dns-reverse-records.zone` still describes
it.

Technitium 15.6.2 fixes the issue. The lock pins 15.6.2, and since 2026-11-10
all three installed nodes run it (in-place update of decision 0016, see
`status.md`). Closing this still needs the reverse zone created once on the Primary and applied
from the reviewed zone file ("Create the reverse zone once" and "Plan and
apply" in `docs/operations.md`), PTR queries over UDP and TCP on all three
nodes, and a restart of one Secondary that comes back without the exception.

## The image's AppArmor signal rule is not yet observed on a fresh installation

The rule that lets Technitium's stacked container profile signal itself (see
"Technitium aborts under Podman's stacked AppArmor label" in
`docs/engineering-notes.md`) was added by hand to all three installed nodes on
2026-11-06, with the loaded profile removed so that Podman reloaded it. The
image now installs the same file, and `tests/apparmor-signal-simulation.sh`
proves that it compiles into Podman's profile, but no node has been installed
from an image that carries it. Closing this needs one installation (a
disposable VM is enough) whose first container start shows no
`apparmor="DENIED"` signal entry and passes the `kill -TERM` test inside the
container.

## The first-boot static API token is not registered after clustering

Each appliance's first boot writes a token to
`/var/lib/dns-appliance/secrets/technitium-static-token` and passes it to
Technitium as a static session. On 2026-11-06 that token was refused
(`invalid-token`) by its own appliance on all three nodes, and no static
session appeared in any node's session list. The on-device backup and any
other on-device API caller therefore fail; the on-device
`dns-appliance-backup.service` has exited with status 9 on every run since
installation and has produced no backup. Backups are instead taken by the
management host (decision 0015). Closing this needs a token mechanism that
survives cluster initialization and joining, proven on a disposable cluster.

## Cluster authentication changes do not propagate and can revert

On 2026-11-06 (Technitium 15.6.1):

- An admin API token created on the Primary (both through `/api/user/createToken`
  and `/api/admin/sessions/createToken`) worked on the Primary but was never
  accepted by either Secondary, even after the Secondaries reported later
  configuration syncs. The tokens created by cluster bootstrap are present on all
  three nodes.
- Re-saving one section's permissions with unchanged values on the Primary made
  the Primary's sessions return to the state recorded at cluster bootstrap: a
  token created that day disappeared and admin tokens deleted minutes earlier
  reappeared.

Until this is understood, nothing saves the authentication configuration
(users, groups, permissions, tokens). Six unused admin API tokens from repeated
bootstrap runs (`cluster-bootstrap-dns01`) remain on every node for that reason.
Technitium 15.6.2 fixes several cluster configuration-sync problems and the
unsaved authentication configuration of issue #2233 (see above). After all
three nodes run 15.6.2, delete the six tokens on the Primary, then confirm on
all three nodes that they are gone and stay gone after a later configuration
sync. Closing this needs that result, or a reproduction on a disposable cluster
and a supported procedure if the tokens return.

## Agent accounts have no zone-level permission

The reader, planner, and applier accounts created by `cluster-bootstrap` have
section permissions but no permission on the zones themselves: zone listing
returns nothing and zone export is refused. `dnsctl plan` and `apply` were run
on 2026-11-06 with a short admin session instead, through an SSH tunnel to the
Primary. Granting zone permissions would save the authentication configuration
(see above), so it is deferred.

## The cluster writes the PTR records of its own node addresses

After the reverse zone `77.10.in-addr.arpa` was created in the cluster catalog
and imported, the cluster replaced the record for a node address with a PTR to
the node's name in the cluster domain (TTL 3600). The repository reverse zone
now mirrors exactly what the cluster writes for `10.77.5.1` through `10.77.5.3`
so that plans show no difference.

## The management API is reachable only on the LAN

The Technitium web service listens on loopback and the appliance's LAN address
only. The management host reaches it through an SSH tunnel to the appliance's
loopback address over the overlay; the tunnel's local URL is the
`TECHNITIUM_URL` that a saved plan binds to.

## A storage server allows TCP forwarding for one account

To reach the site LAN before overlay enrollment, and as the wired recovery path
for the router, the site's storage server allows SSH TCP forwarding for one
named account (a `Match User` block added on 2026-11-06, with a backup of the
previous configuration). A storage-server software update may reset it; rerun
the management host's rollback dry-run after such an update to confirm the
recovery path still works.

## A stale DHCP reservation remains for a storage server

The router keeps a manual DHCP reservation for one storage server's MAC address
inside the DHCP range, while that server uses a different static address. If
the server ever falls back to DHCP, its DNS name would point at the wrong
address. The reservation is to be removed as part of the router change.

## Installed appliances lack an installation provenance record

The three appliances are installed and serve as one cluster on the
`10.77.0.0/16` LAN (see `status.md`), but the repository does not record which
installation media generation, image build, or source commit installed each
node, nor the per-node enrollment evidence. Without that record, the installed
kernel snapshot, overlay client versions, and installer gate behavior cannot be
tied to a reviewed build. Closing this needs the operator's enrollment records
(kept outside Git) matched to a build manifest and summarized here by role.

## The first physical DNS pilot selected its installer USB

Under the original Ventoy boot path, the installer resolved `/dev/mapper/Ventoy` without following its sysfs slave and partition ancestry. The 30.8 GB SanDisk installer USB later showed the intended DNS target layout and an invalid EFI filesystem, proving that the removable installer became writable. This can destroy installation media and could select the wrong disk.

The source now resolves the physical parent, rejects unresolved ancestry, USB-backed and mounted candidates, and delays signature clearing until all checks pass. The finding remains open because source simulation cannot prove the repaired path on firmware and hardware. Rebuild the ISO and USB, pass VM BIOS/UEFI, and run one disposable physical `dns01` pilot before enabling another role.

## Revised macOS image path still lacks filesystem and firmware qualification

Two earlier physical writes copied selected ISO payloads correctly, but whole-device comparison differed after macOS mounted exFAT and changed filesystem metadata. The MBR-last writer now prevents mounting before body readback and passes isolated simulations.

The repository now builds an exact-size MBR image through a privileged Debian
13 container whose loop device is isolated inside the Linux VM. It rejects
repository-bundle symlinks before assembly, and the macOS writer binds its exact
confirmation to device path, media name, USB serial, and byte size. An earlier
physical write completed full raw readback but its generation was rejected
because the command resolved `dns-install` while the raw image contained
`inventory-capture`; that mismatch exposed a missing provenance binding.

The builder and writer now bind image bytes to Catalog and World media through
an adjacent manifest. On 2026-10-17 the bound path wrote the
15,833,497,600-byte `inventory-capture` image, passed full MBR-last raw readback,
ejected the target, and emitted inspected generation
`20261017093655-jeonghan-home` with the correct media identity and no raw USB
serial. Mount-time filesystem checks, payload checks, and BIOS/UEFI boot remain
required before qualification.

## Inventory capture still requires manual terminal input

The current `inventory-capture` media boots a stock Debian Live image and
stages a capture script plus an English guide on the `DEVICE-OS` partition. The
operator must mount that partition and manually supply the role, address,
interface, and disk. This is non-destructive, but it invites transcription and
wrong-device mistakes and does not match the Korean-first World presentation.

The current USB remains usable as the conservative capture path. Closing the
usability gap requires an offline Korean capture UI that reads the roles and
addresses from the resolved World, detects candidate NICs and internal disks,
asks the operator only to choose the node and resolve genuine ambiguity, then
writes a schema-validated machine record and human-readable summary. The
capture image must remain incapable of erasing an internal disk.

## Destructive approval is exposed as a shell-looking token

The writer correctly binds authorization to the currently inspected device
path, media name, serial, and exact byte size, but `inspect-targets` displays the
binding as an `ERASE ...` line. An operator can reasonably paste that line into
a shell, where it fails as an unknown command, or mistake the internal token for
the whole burn command.

The exact target binding must remain. The operator-facing coordinator should
instead present a natural-language target summary and request natural-language
approval; after a fresh identity check it should construct and pass the exact
token internally. Direct low-level writer use may retain `--confirm` for tests
and expert recovery, but ordinary documentation and agent interaction should
not instruct the operator to execute the token.

## DNS apply does not prove pull-request approval

`dnsctl apply` consumes one immutable saved plan by SHA-256 and rejects target, commit, zone-file, and live-zone drift and replays. It still cannot prove that a person reviewed that plan or that a pull request was approved, because no approval source is designed, and it does not require unrelated tracked files to be clean. Operators must verify approval before apply.

Replay protection depends on the local audit log; a different management host or a deleted log does not see earlier applies, although live-zone drift detection still rejects a plan whose current hash no longer matches. Plans carry no expiry. Closing this needs a product decision on approval authority plus a signed approval record and expiry rules.

## Catalog schemas and executable validation can drift

CI now validates all tracked Catalog v2 records and explicit accepted and rejected fixtures against the published draft-2020-12 JSON Schemas. This closes the absence of executable schema checks for the exercised records and fixtures.

The finding remains open in narrower form because the schemas, jq verifier, and Installer consumer are independently maintained. An unrepresented document can still expose different semantics. Closing the remaining gap requires generation from one representation or systematic cross-consumer equivalence testing beyond the current fixture set.

## Vendor checksum provenance is not retained consistently

Catalog values are syntax-checked and downloads are verified against them, but the repository does not retain signed or independently captured authoritative checksum provenance for every release. If a URL and digest are changed together maliciously, successful download verification alone cannot establish authenticity.

Reviewers must verify each update through an authoritative vendor channel and preserve that evidence in the pull request. A durable provenance format, retention policy, and repository integration remain undecided.

The redistribution metadata and schema checks do not close this finding. They bind a human review to an exact digest after evidence exists; they do not prove that the digest itself came from an independent authoritative vendor channel.

## Human-only prebuilt Environment is not verified

Repository policy names the protected GitHub Environment
`prebuilt-distribution` and requires a human-only required reviewer in addition
to a successful prebuilt-release check. No publishing job exists, generated
artifact distribution remains disabled, and repository source cannot prove the
external Environment settings or reviewer identity.

Before any prebuilt workflow is proposed, the repository owner must create or
inspect that Environment, confirm that agents cannot approve it, capture the
settings review outside generated media, and retain the independent
prebuilt-release gate. Until then the repository is source-only and must not be
described as ready to publish generated media.

## Management operations lack one complete audit trail

DNS plan/apply records only some completed outcomes, while cluster bootstrap, Tailscale and NetBird enrollment, backup collection, reinstall authorization, restore, and router changes primarily leave console output and resulting state. Failures before command-specific logging may leave no durable event.

This limits incident reconstruction and proof of who authorized a sensitive operation. Operators must capture protected session records for now. Closing it needs a shared redacted event schema, append-only protected sink, failure-path coverage, retention policy, and operator identity source.

## Live agent path remains unverified

The MCP gateway passes isolated tool and policy simulations, but no evidence yet proves the dedicated account, overlay access policy (Tailscale ACL or NetBird policy), forced SSH command, protected credential paths, trusted Technitium CA, and three live DNS nodes operate together. A source pass cannot establish remote identity or network policy. Whether the dedicated gateway account may read the NetBird daemon socket (`/var/run/netbird.sock`) for `netbird status --json` is also unverified; if it cannot, `tunnel_status` fails rather than reporting NetBird state.

Provision the management-host account and overlay policy only after node installation, then test read-only tools first, including `tunnel_status` with each installed overlay CLI, verify forbidden tools are absent, and enable one canary apply only after trusted TLS and rollback are proven.

## NetBird publishes no dependency-license report

Tailscale publishes a pinned dependency-license report that the DNS image carries beside its client. NetBird publishes none for the Go modules compiled into its static client binary. The client itself is built from the BSD-3-Clause part of the upstream repository, and `docs/licenses/NetBird-BSD-3-Clause.txt` is the license text at tag `v0.82.0`, but the licenses of the third-party modules among the 739 non-standard Go packages that the client builds from at that tag (`go list -deps ./client`, linux/amd64) are not recorded. The SBOM therefore concludes `NOASSERTION` for `SPDXRef-NetBird`.

This does not limit personal use. It blocks a future redistribution review of any DNS image that selects NetBird, because notice and corresponding-source obligations cannot be dispositioned without that inventory. Closing it requires generating and reviewing a dependency-license report for the exact pinned client source, or an upstream report, bound to the pinned version.

## Overlay clients and Technitium are not updated automatically

Unattended upgrades install only Debian packages. The Tailscale and NetBird clients and the Technitium container are pinned upstream artifacts installed from the image. A fix in an overlay client reaches an appliance only through a reviewed lock update, a rebuilt image, and a reinstall; a fix in Technitium reaches it through a reviewed lock update and the manual in-place update of decision 0016. No vendor apt repository is configured, by decision 0014.

The operator must watch the upstream security announcements of these three components and schedule a lock update, then the one-at-a-time in-place update or reinstall, when a fix matters.

## The reference collection's personal-use check lists every DNS component

`license check --mode personal-use` for the contributor reference collection names no World, so it cannot know which overlays a DNS image would select. Without a valid build manifest it lists all six known DNS components, including both overlays' components. This is conservative: it may warn about a component that a particular image does not contain, but never omits one. World-driven checks use the World's overlays, and checks with a valid build manifest use the manifest's.

## The overlay port limits are not yet checked with the real clients

The NetBird client inserts `iifname "wt0" accept` at the top of the appliance's input and forward chains and re-inserts it after any change, so the appliance limits overlay ports in the prerouting chain `overlay_prerouting` of its own table, which the client does not touch, and keeps the overlay clients' tables through `nftables.service` load, reload, and stop. `tests/firewall-namespace-simulation.sh` shows both in network namespaces, but with veth interfaces named `wt0` and `tailscale0`, an inserted rule that reproduces the client's, and stand-in tables, not the real NetBird and Tailscale clients.

Closing this requires an installed node with both clients enrolled: `nft list table inet dns_appliance` shows `overlay_prerouting` with both interfaces; from an admin-group peer over each overlay, DNS and the management ports answer while a port outside the allowed set does not; and the clients' tables and connectivity remain after `systemctl reload nftables` and `systemctl restart nftables`. Because the client's accept also sits at the top of the forward chain, the same check confirms `net.ipv4.ip_forward` stays `0` with both clients enrolled; that, not the forward chain's policy, is what keeps an appliance from forwarding overlay traffic.

Partly closed on 2026-11-06 for NetBird (`docs/tracking/status.md`, "NetBird enrollment"). All three installed nodes run both clients. The real NetBird 0.82.0 client inserted `iifname "wt0" counter accept` at the top of `inet dns_appliance` `input`. While a temporary NetBird policy allowed all TCP from the management peer, TCP 5053, 5380, and 8080 stayed closed over `wt0`: 5053 is the client's own listener on the `wt0` address, so only `overlay_prerouting` was left to drop it. DNS and TCP 22, 9090, and 9100 answered, and `ip_forward` stayed `0`. Still open: the same check over `tailscale0`, and the tables surviving `systemctl reload nftables` and `restart nftables` on an installed node. Neither was run because the nodes are in service.

Post-outage observations on 2026-11-07 record all three nodes booted again and NetBird connected; direct DNS queries to each node's NetBird address at 03:42 KST returned the canary over UDP and TCP (see `docs/tracking/status.md`). Recovery after the outage is not a controlled `nftables.service` reload/restart or a live Tailscale port-limit equivalence test. Those checks remain unverified.

## The NetBird client keeps a DNS listener and an output DNAT although DNS management is off

With `--disable-dns=true`, the NetBird 0.82.0 client on each appliance still listens on TCP 5053 at its own `wt0` address, and its table `ip netbird` contains an `output` NAT chain. That chain redirects locally generated UDP and TCP 53 traffic for the node's own NetBird address to that listener. Queries from peers enter through prerouting and still reach Technitium, as the live checks show. The appliance's resolver names only `127.0.0.1`, so it is unaffected. Only a process on the appliance that queries its own NetBird address gets the client's resolver instead of Technitium. `overlay_prerouting` keeps port 5053 closed to peers. No change is needed. Keep this in mind when a check runs on an appliance against that appliance's own NetBird address.

## A NetBird service-user token needs the Admin role

The design asks for the narrowest role that can create and delete setup keys. On NetBird Cloud that role is Admin: a Network Admin token is refused with 403 on `POST /api/setup-keys`, although it can read the account and manage groups and policies. An Admin token can also change account settings and users. Keeping it in the principal secret store, writing it to a temporary mode-0600 file only for a run, and deleting that file afterwards limit its exposure.

## Tailscale enrollment does not inspect Serve or Funnel state

The enrollment command verifies running state, hostname, tag, address, accepted DNS, routes, exit-node settings, and Tailscale SSH preferences. It does not query the separate Serve/Funnel configuration, so a node can pass the implemented preference gate without source evidence that those listeners are absent.

Current deployment acceptance therefore requires a separate operator check for empty Serve and Funnel status. Closing the gap requires a stable machine-readable Tailscale status interface, failure fixtures, and a compatibility decision across pinned Tailscale versions.

## Agent results are clipped but not content-redacted

The gateway limits stdout and stderr to 64 KiB but returns delegated text without scanning for tokens, passwords, or other credential patterns. A delegated command regression could therefore expose a secret through MCP even though current commands are designed to keep credentials out of output.

The current mitigation is the fixed command allowlist, protected credential-file paths, explicit environment allowlist, and command-level output discipline. Closing the gap requires central content filtering with false-positive rules plus fixtures proving that complete and truncated credential-like output is blocked without echoing the value.

## Restore disables TLS certificate verification

`restore-node` always invokes the selected Technitium HTTPS origin with certificate verification disabled while sending a bearer token and decrypted backup. Exact URL confirmation prevents accidental target substitution by the operator but does not authenticate that endpoint.

The command is restricted to isolated restore drills and is not production-qualified. Closing this requires a trusted-CA or pinned-fingerprint input, endpoint validation, failure tests for an untrusted certificate, and a successful isolated restore with verification enabled.

## VM qualification tooling lives outside the repository

On 2026-10-22, a rebuild from a fresh GitHub clone of `ab46d04` succeeded using
only `docs/operations.md`. It ran in a new amd64 Debian 13 container with only
the operator SSH public key and age recipient supplied from outside Git. The
ISO, the exact-size raw image and the BIOS and UEFI VM installs all passed
(internal boot, DNS over UDP and TCP, encrypted enrollment). The one
documentation gap found, the missing `world prepare` before the macOS
`dns-install` build, is fixed.

The disposable QEMU launch, key-input and screenshot tools used for the VM
installs, and the read-only enrollment inspection, exist only on the VM host,
outside the repository. The repository can build every artifact but
cannot reproduce the VM qualification by itself. Closing this requires moving
those tools into the repository with path rejection for real devices, as
designed in the 2026-10-21 qualification plan.

## Hosted CI conflicts with the build-host-only validation policy

On 2026-10-21, `.github/workflows/ci.yml` still selects GitHub-hosted
`ubuntu-24.04` for the required `contracts` job on pull requests and pushes to
`main`. The operator requires builds, tests, and lint gates to run only on the
designated build hosts. Opening a pull request would therefore start validation
on a disallowed host, even though source validation has passed separately on the
build host.

The pending Tailscale DNS correction and newly verified USB generation remain
on branches without a pull request. The workflow does not yet connect the
required GitHub check to the designated build-host validation infrastructure. Closing
this requires a reviewed runner/workflow integration; the required check and
branch protection have not been changed or bypassed.

**Operator decision (2026-10-22):** this repository is exempt. Its required
`contracts` check may keep running on GitHub-hosted `ubuntu-24.04` for pull
requests and `main`. Image builds, VM qualification, and physical media work
stay on the designated build hosts. Moving the check to a build-host runner
remains optional.
