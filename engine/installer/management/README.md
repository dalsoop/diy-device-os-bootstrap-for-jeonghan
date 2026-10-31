# Agent management plane

The management plane is separate from the DNS appliances.
Run command examples from the repository root.

Implemented bootstrap and operating surfaces:

- `import-enrollment` decrypts completed USB records into a caller-selected
  protected directory; it never writes credentials into the repository.
- `cluster-bootstrap` initializes dns01, joins dns02/dns03, imports the reviewed
  `home.arpa` zone from `burn-history/dns-records.zone`, and emits an age-encrypted agent token bundle.
- `dnsctl health` uses the reader token.
- `dnsctl plan <zone> [--out <plan-file>]` emits a schema version 2 plan with
  the target URL, source commit, zone path, and current and desired hashes,
  plus a human diff. `--out` requires a committed, unmodified zone, writes the
  plan once as a read-only file, refuses an existing path, and prints
  `plan_sha256` on stderr.
- `dnsctl apply --plan <plan-file> --plan-sha256 <sha256> --confirm APPLY`
  applies only that reviewed plan. It refuses a hash mismatch, another target
  URL, a different `HEAD`, a modified zone file, a live zone that drifted from
  the plan's current hash, and a plan that the audit log already records as
  applied. It does not prove pull-request approval. Audit output is JSONL,
  carries `plan_sha256`, and contains no token.
- `collect-backups` retrieves only already-encrypted backup files over SSH.
- `restore-node` requires an explicit target URL, local age identity, and exact
  restore confirmation.
- `authorize-reinstall` creates a one-generation erase authorization after an
  explicit role confirmation.
- `network-preflight` verifies that the configured router prefix contains all
  three DNS addresses, reports router and node reachability, and separately
  records the management host's default gateway. It also checks fixed outbound
  IP, DNS-resolution, and HTTPS probes. `--json` provides the versioned agent
  contract; `--offline` makes the skipped Internet check explicit rather than
  treating it as success.
- `tailscale-enroll` uses a management-host OAuth credential to mint a distinct
  one-off key for each selected node, sends the key over existing LAN SSH,
  deletes the remote temporary key file, attempts best-effort API revocation,
  and verifies hostname, `tag:dns-appliance`, address, and peer reachability.
  Failed revocation can leave the non-reusable key valid until its one-hour
  expiry. It never sends the OAuth secret to an appliance.
- `netbird-enroll` uses a management-host NetBird personal access token to
  create one one-off, single-use, non-ephemeral setup key per selected node in
  the appliance group, sends only that key over existing LAN SSH into a
  mode-0600 remote file that is removed afterwards, and runs `netbird up` with
  DNS management, client routes, server routes, and the NetBird SSH server
  disabled. It then verifies the management connection, hostname, an address
  inside `10.78.0.0/16`, appliance-group membership, those client settings, the
  absence of any routing-peer role, and a resolver naming only `127.0.0.1`. The
  key is deleted after use, also on failure; an unconfirmed deletion fails the
  command and names the key ID for manual deletion. A node already connected
  is only verified.
- `dns-appliance-status-monitor/start` launches a dependency-free Korean status
  page on `127.0.0.1:8080` and checks DNS over UDP/TCP plus Cockpit,
  Technitium, and node-exporter connectivity for all three nodes, reached by
  the role names `dns01` through `dns03`. It also shows each node's pending
  reboot and consecutive skipped reboots from its node-exporter metrics, and
  reports a name that does not resolve separately from probe failures. It is
  read-only and is also copied onto the DIY Device OS USB for Jeonghan.

The status monitor and the MCP gateway reach the nodes by role name, so the
management host's resolver decides the path (LAN, Tailscale, or NetBird). The
management host must resolve `dns01` through `dns03` without depending on the
DNS cluster itself, through a hosts file or an overlay's own DNS (Tailscale
MagicDNS or NetBird DNS), so both still reach the nodes when the cluster fails.
Enrollment commands, by contrast, use the fixed LAN addresses below.

Before enrollment, merge the relevant parts of
`tailscale-policy.example.hujson` into the reviewed tailnet policy and create an
OAuth client with the `auth_keys` scope restricted to `tag:dns-appliance`.
Store the ID and secret outside this repository, one line per protected file:

```sh
TAILSCALE_OAUTH_CLIENT_ID_FILE=/secure/tailscale/client-id \
TAILSCALE_OAUTH_CLIENT_SECRET_FILE=/secure/tailscale/client-secret \
  engine/installer/management/tailscale-enroll --all
```

The nodes must already be reachable at `10.77.5.1` through `10.77.5.3` by the
operator SSH key. Enrollment requires Internet access to the Tailscale control
plane but does not change the appliances' local DNS resolver or routing role.

Before the first NetBird enrollment, set the account's network range to
`10.78.0.0/16` (dashboard Settings > Networks), remove or disable the built-in
`Default` all-to-all policy, create the appliance group (`dns-appliances` by
default) and an admin group, and create the policies in
`netbird-policy.example.json` after replacing each `<group-id:NAME>`
placeholder with that group's ID. Create a dedicated service user whose
personal access token can create and delete setup keys and read groups, peers,
routes, and network routers, and store the token outside this repository on
one line of a protected file:

```sh
NETBIRD_API_TOKEN_FILE=/secure/netbird/api-token \
  engine/installer/management/netbird-enroll --all
```

`NETBIRD_MANAGEMENT_URL` (default `https://api.netbird.io`) selects a
self-hosted management server by its HTTPS origin, `NETBIRD_APPLIANCE_GROUP`
(default `dns-appliances`) the group assigned by the setup key, and
`NETBIRD_SSH_USER` (default `dns-operator`) the appliance SSH account.
`network-preflight --json` reports the matching readiness as
`network_gates.post_install_netbird`.

The reviewed MCP gateway lives in [`engine/agent/`](../../agent). It runs
on a management host, reaches this module only through a fixed command
allowlist, and uses stdio through an SSH forced command reachable only over a
reviewed overlay (Tailscale or NetBird).
`dnsctl` remains the delegated apply and audit boundary; the gateway cannot
bypass its commit, clean-tree, confirmation, token, or TLS requirements. Set
`TECHNITIUM_CA_FILE` to make `dnsctl` verify a reviewed CA; the Agent Gateway
requires that mode for apply.
