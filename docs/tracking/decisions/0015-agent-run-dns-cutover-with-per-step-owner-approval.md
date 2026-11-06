# 0015: Run the DNS Cutover by Agent With Per-Step Owner Approval, Tailscale First

- Status: Accepted
- Date: 2026-11-06

## Context

The three DNS appliances are installed and run as one Technitium cluster on
the `10.77.0.0/16` home LAN. The router LAN moved to `10.77.0.1/16` on
2026-11-06. The management host is at another site and reaches the home only
through an overlay network. The repository describes router mutation as a
manual operator step, requires a wired recovery client during the cutover, and
rolls back router DHCP DNS when any canary fails.

The owner wants the whole home LAN on the cluster and wants to manage the
appliances from the remote management host. The owner also wants to approve
every change that affects the whole home or the owner's own devices, and does
not want a household-wide outage to wait for a reply when no appliance answers.

## Decision

- **Execution.** An agent performs checks, records, appliance settings, secret
  store maintenance, and management-host setup itself. Immediately before any
  change to the router, to tailnet-wide overlay settings (policy file, DNS
  settings), or to a workstation's Wi-Fi order or network location, the agent
  shows the exact change to the owner and proceeds only on approval for that
  request. The approval request names everything it covers, such as a rollback
  during the same change.
- **Emergency rollback.** After the router hands out the appliances as DHCP
  DNS, the management host restores the previous router DHCP DNS values without
  asking only when no appliance answers: the management host sees all three
  down, then re-checks from a wired host inside the LAN, and that host also
  sees all three down in two checks at least five minutes apart. When the
  wired host cannot be reached, or when only some appliances fail, the
  management host alerts and does not roll back. This replaces the
  repository's rollback-on-any-canary-failure rule for this deployment.
- **Recovery client.** A wired host inside the LAN that the management host
  reaches over the overlay serves as the recovery client and as the path to the
  router's administration page. No separate wired workstation is kept.
- **Overlay.** Tailscale is enrolled first. NetBird stays installed on the
  appliances and unenrolled; the World keeps selecting both overlays. The
  tailnet policy only adds the reviewed `tag:dns-appliance` entries: management
  ports for administrators, DNS for the owner's devices, and cluster traffic
  between appliances. Existing rules for other devices stay unchanged. A
  Tailscale split-DNS entry sends only `home.arpa` to the appliances.
- **Management API path.** The Technitium API stays bound to loopback and the
  LAN address. The management host reaches it through an SSH tunnel to the
  appliance's loopback address. The API is not exposed on the overlay.
- **Zone authority.** The repository zone files are the source for every record
  except the SOA and apex NS records, which the cluster manages. `dnsctl`
  imports and compares the zone without those two record types.
- **Backups.** The management host collects the encrypted appliance backups
  daily and keeps them as attachments of a dedicated item in the principal
  secret store, separate from the item that holds the recovery identity. It
  keeps the latest seven per appliance. A restore drill is a later step.
- **Names.** Static-address hosts get names in `home.arpa` following the fleet
  naming rule (role or product plus a number without zero padding), with one
  PTR record per address in `77.10.in-addr.arpa`. DHCP-roaming devices get no
  names. `dns01` through `dns03` keep their zero-padded names as an exception,
  because the names are part of the cluster node identities, the installation
  profiles, and the stored credentials.
- **Excluded hosts.** Hypervisors, storage servers, and the server that runs
  the CI runner and the tailnet identity provider keep their own resolver
  settings, so a cluster outage does not take them down.

## Alternatives

- A human performing every router step by hand was rejected by the owner in
  favor of agent execution with per-step approval.
- Rolling back on any canary failure was rejected because one or two failed
  appliances leave the cluster able to answer, and a rollback is itself a
  household-wide change.
- Exposing the API on the overlay was rejected because it changes the appliance
  image and firewall and widens exposure; tunnels need neither.
- Enrolling NetBird at the same time was deferred because its account, network
  range, and default-policy preconditions are not in place.
- Keeping backups only on the management host or only on home storage was
  rejected by the owner in favor of the principal secret store.
- Renaming the appliances to the unpadded form was rejected because it requires
  rebuilding the cluster.

## Consequences

The cutover can proceed without a person at the router, but every
household-wide change still waits for the owner. A total appliance outage is
undone automatically within roughly two check intervals plus the DHCP lease
time, while partial outages and overlay or Internet failures only alert. The
management host depends on the overlay and on SSH tunnels for every management
call. Backups are collected but remain unverified until a restore drill passes.
