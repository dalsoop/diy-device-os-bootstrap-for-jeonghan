# Verification and release gates

No source review or unit simulation guarantees that an installer can safely
erase and rebuild physical hardware. Complete every gate in order and attach
logs, checksums, screenshots, and resulting `public.json` files to the release
evidence.

## Automated source gates

- `tests/install-gate-simulation.sh` passes every reviewed and guided case,
  including direct partition media, Ventoy's `/dev/mapper/Ventoy` ancestry,
  unresolved, ambiguous, multi-slave, cyclic, loop, and MD ancestry, fixed-bit
  USB targets, direct, mapper-backed, and `/dev/disk` alias mounts, active
  swap, sysfs holders, the synchronization step, and zero writes on every
  rejection.
- `tests/management-simulation.sh` passes all 21 cases, including explicit
  offline Internet state, saved immutable DNS plans, plan-bound apply with
  hash, endpoint, commit, zone, drift, and replay rejection, generated
  recursion permissions for the LAN and each selected overlay, public-client
  rejection, the rendered firewall for each overlay selection (own table, no
  ruleset flush, prerouting and input rules, source-range guards, marker and
  input rejection), and per-overlay health output.
- `tests/firewall-namespace-simulation.sh` passes in privileged network
  namespaces: with a NetBird-style `iifname "wt0" accept` at the top of the
  input chain, ports outside the allowed set stay dropped on `wt0` and
  `tailscale0` while DNS and the management ports answer, and loading,
  reloading, and stopping the firewall leave stand-in overlay tables
  unchanged.
- `tests/tailscale-enrollment-simulation.sh` passes without printing either
  OAuth or auth-key material.
- `tests/netbird-enrollment-simulation.sh` passes every success, refusal, and
  verification case, including unconfirmed setup-key deletion, without the
  token or any setup key reaching command arguments or output.
- `tests/appliance-update-simulation.sh` passes the reboot decision cases
  (no reboot required, seen peers up, never-seen peer down, seen peer down,
  both down, persistence, metrics) and the rendered per-role timers.
- `tests/status-monitor-simulation.sh` passes name resolution, reboot metrics,
  GET-only access, highlighting, and configuration rejection cases.
- `tests/image-builder-simulation.sh` passes the Tailscale-only, NetBird-only,
  and dual overlay selections, World/image agreement, and both Linux writers'
  manifest checks.
- `tests/media-catalog-simulation.sh` rejects duplicate identities, unknown
  strategies/adapters, path traversal, and invalid digests, then proves that a
  new standard ISO reaches the Ventoy menu through catalog data alone.
- `tests/repository-contract.sh` passes.
- ShellCheck reports no errors.
- GitHub CI passes on the exact commit to be built.
- `build/verify-locks` passes, including the Simple-CDD mirror timestamps equal
  to `DEBIAN_SNAPSHOT` and the NetBird pin, and the fetched OCI manifest
  matches the amd64 digest.

## Build gates

- Build on an amd64 Debian 13.7 host with Simple-CDD 0.6.9.
- Build twice from clean ignored directories and compare ISO, package closure,
  manifest, and SBOM.
- Confirm that the package closure carries `linux-image-amd64` 6.12.113-1 or
  later and `unattended-upgrades`.
- Confirm that the manifest's `overlays` equal the World's and that the ISO
  carries only the selected overlay clients and license texts.
- Verify the ISO checksum before and after USB writing.
- Inspect BIOS and UEFI boot files; verify signed Secure Boot components.
- Verify the embedded Tailscale and NetBird archive SHA-256 values and the
  installed client versions.

## Virtual-machine gates

- BIOS install with networking disconnected.
- UEFI and Secure Boot install with networking disconnected.
- Wrong DMI, wrong MAC, wrong disk serial, two matching disks, removable disk,
  missing `DNS-ENROLL`, completed role, stale reinstall token, and corrupt exFAT
  all stop before erase.
- Power loss after credential generation, during encrypted output, after final
  record rename, and before local completion converges without changing secrets.
- Reboot with the USB attached does not start another installation.
- Boot the DNS ISO from Ventoy and prove its mapper device and physical USB
  cannot become the selected internal target.
- After a successful install, inspect the removed USB and prove that its Ventoy
  partition map and checksums are unchanged.

## Physical dns01 pilot

- Photograph and record the HP product number, wired NIC, target disk, firmware
  mode, Secure Boot state, and boot order.
- Capture inventory from a trusted live system and enable only `dns01`.
- Confirm the erase target by serial immediately before selecting install.
- Verify internal-disk boot, SSH host fingerprint, SSH key login, sudo, Cockpit
  login, Technitium TLS fingerprint, DNS UDP/TCP, NTP, metrics, and encrypted
  enrollment.
- Decrypt recovery on the management machine and prove the Cockpit password.
- Run one encrypted backup and isolated restore drill.
- Enroll with a one-off tagged Tailscale key, verify `accept-dns=false`, no
  routes/exit-node/Serve/Funnel/SSH, management-port ACLs, `tailscale ping`, and
  keyless reconnection after reboot.
- With the NetBird range `10.78.0.0/16` and the `Default` policy removed,
  enroll with `netbird-enroll`, verify the reported settings, that the setup
  key is gone from the dashboard, that only the admin group reaches the
  management ports over `wt0`, and reconnection after reboot. Inspect
  `nft list ruleset` and record every rule the overlay clients added; confirm
  `overlay_prerouting` in `inet dns_appliance` names every selected overlay
  interface, that a port outside the allowed set is unreachable over `wt0` and
  `tailscale0`, and that the clients' tables and connectivity remain after
  `systemctl reload nftables` and `systemctl restart nftables`.
- Confirm `apt-daily-upgrade.timer` and `dns-appliance-reboot.timer` at the
  role's times, an unattended upgrade run against the Debian archive, a
  guarded reboot with peers answering, and a skipped reboot (journal entry,
  `dns_appliance_reboot_*` metrics, and status-monitor highlight) while a seen
  peer is stopped.

## Selected Device OS USB gates

- Verify Ventoy and every entry selected by the resolved World against the
  recorded SHA-256 before copying. Catalog availability alone does not place an
  entry on the USB.
- Verify `manifests/MEDIA-CATALOG.SHA256` and retain the exact catalog copied to
  the USB with release evidence.
- Verify every copied ISO using the USB's generated `manifests/SHA256SUMS`.
- Test BIOS (non-UEFI) and UEFI menus; treat Secure Boot as failed until the
  exact HP firmware and every selected image boot successfully.
- Prove all menu entries require deliberate selection. The current
  `inventory-capture` pass contains only Debian Live; the current `dns-install`
  pass contains only the guarded DNS image.
- If Proxmox VE, Proxmox Backup Server, TrueNAS SCALE, or Pop!_OS is selected in
  a future generation, qualify that exact release on disposable media and prove
  it remains interactive before production use.
- Run the bundled DNS appliance status monitor and confirm it resolves
  `dns01` through `dns03` without the DNS cluster and reports DNS UDP, DNS TCP,
  Cockpit, Technitium, metrics, and reboot state for all three nodes.
- On `dns-install`, verify `DNS-ENROLL` survives boot and accepts only the DNS
  appliance's encrypted enrollment output. `inventory-capture` reserves no DNS
  enrollment partition.

Only after dns01 passes should dns02 and dns03 be enabled one at a time. Cluster
and router DHCP cutover are separate final gates. Publishing or writing a new
physical USB always requires a fresh target check and explicit erase approval.
