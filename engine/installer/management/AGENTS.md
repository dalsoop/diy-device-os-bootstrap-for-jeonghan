# DNS Management Module

This module runs from a trusted management host after appliance installation.

- Keep credentials in protected caller-selected files and directories outside
  the repository. Never print tokens or place them in URLs.
- A management host outside the LAN reaches the Technitium API only through an
  SSH tunnel to the appliance's `127.0.0.1:53443`; the tunnel's local URL is
  `TECHNITIUM_URL` and therefore the target a saved plan binds.
- Reader and planner operations are the default. Apply consumes one saved,
  read-only plan named by its SHA-256 and rejects any change of target,
  commit, zone file, or live zone since that plan, and any replay. Human
  review of that plan remains required because the command does not prove
  pull-request approval.
- Bootstrap all three nodes only from verified enrollment records. Encrypt the
  resulting access bundle before final placement.
- Tailscale OAuth credentials never leave the management host. Mint one
  non-reusable, pre-authorized, one-hour key per node, send only that key over
  existing SSH, delete its remote file, attempt API revocation, and verify
  restrictive preferences. Revocation is currently best-effort; investigate a
  failed or interrupted enrollment until the one-hour key has expired.
- The NetBird API token never leaves the management host and travels only in
  a curl-config header. `netbird-enroll` creates one one-off, single-use key
  per node in the appliance group, sends only that key over existing SSH,
  deletes it after use and on failure, and fails naming the key ID when the
  deletion is unconfirmed. It verifies DNS management, client and server
  routes, and the NetBird SSH server disabled, no routing-peer role, an
  address in `10.78.0.0/16`, and an unchanged resolver. Verify `netbird up`
  flags and status or configuration field names against the pinned client
  source before changing them.
- Backup collection transfers only already-encrypted files. A collected file is
  not a verified restore.
- Restore requires an exact target URL confirmation. The current command uses
  unverified TLS and is limited to isolated drills until trusted-CA or
  pinned-fingerprint verification is implemented and tested.
- Reinstall authorization must bind the active generation and hardware UUID; an
  old token must not authorize a replacement generation.
- The status monitor is read-only and dependency-free. It must not become an
  apply surface. It reaches nodes by role name; the management host resolves
  those names without the DNS cluster (hosts file or an overlay's own DNS).
- Enroll only the overlays the World selects, and only after their
  preconditions: the reviewed tailnet policy for Tailscale; the network range
  `10.78.0.0/16`, the `Default` policy removed or disabled, and the reviewed
  policies for NetBird. Remove a reinstalled node's stale peer by hand before
  re-enrolling it.
- Router mutation is outside this module until a model-specific authenticated,
  reversible API and console recovery are proven.

## DNS zone

The reviewed zones are `burn-history/dns-records.zone` (`home.arpa`) and
`burn-history/dns-reverse-records.zone` (`77.10.in-addr.arpa`); the YAML
description example of the forward zone is
`engine/installer/docs/examples/home.arpa.example.yml`. `cluster-bootstrap`
reads the forward zone by default, `dnsctl plan` takes either file as its
zone-file argument, and `dnsctl apply` reads it through the saved plan's
`zone_path`.

- The zone files are the source of every record except the SOA and apex NS
  records, which the cluster manages for zones in its catalog and refuses on
  import. `dnsctl` and `cluster-bootstrap` strip those with the same rule, and
  `dnsctl plan` compares record sets without them. Write each apex NS record on
  its own `@` line and the SOA starting on an `@` line, or plan refuses the file.
- Every static-address name in the forward zone has exactly one PTR record in
  the reverse zone; the service names `dns-api` and `canary` have none.
- Keep zone changes declarative and reviewable; do not embed credentials or live
  API responses.
- Preserve a low-risk canary record that can be queried over UDP and TCP after
  each apply or restore.
- Advance SOA serials deliberately when zone content changes. The cluster keeps
  its own live serial, so the file serial records the reviewed revision only.
- Do not combine a broad zone rewrite with unrelated installer or credential
  changes.
- Verify a zone change with the plan hash and diff, then query the canary over
  UDP and TCP after apply before making another change.
