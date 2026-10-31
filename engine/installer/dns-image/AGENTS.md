# DNS Installer Module

This module builds the guarded, offline DNS-appliance image and performs
first-boot enrollment.

- Build only from reviewed immutable locks on the build host (amd64 Debian 13).
- Never embed an SSH private key, age identity, OAuth secret, plaintext password,
  real inventory outside ignored paths, or cluster join credential.
- Partitioning must be unreachable until exactly one enabled role and one
  non-removable internal disk match all expected identities.
- Never select installer media, a Ventoy mapper, a removable device, zero
  candidates, or multiple candidates.
- A completed role requires a reinstall token bound to its active generation and
  system UUID hash.
- Keep the boot menu free of automatic destructive timeouts.
- First boot generates credentials once and reuses them across retries until
  enrollment commits. Do not rotate or regenerate on every retry.
- Write secrets to USB only inside an age-encrypted archive. Validate public
  output, write temporary files, atomically rename, synchronize, and only then
  mark completion.
- Only the overlay clients that the resolved World selects (Tailscale, NetBird,
  or both) are fetched, embedded, installed, and enabled. Obtain the selection
  through `overlay-selection`; the embedded `overlays` file and the build
  manifest record it, and `render-build-records` emits the conditional
  registry, manifest, and SBOM. An installed client remains unenrolled until
  the management host supplies a one-off key.
- The NetBird unit mirrors what `netbird service install` writes for the pinned
  client (socket `/var/run/netbird.sock`, profile under `/var/lib/netbird/`,
  logs under `/var/log/netbird/`). Re-read the pinned client source before
  changing it or the pin.
- Installed nodes take Debian point-release and security updates unattended at
  fixed per-role times and reboot only through `dns-appliance-reboot`, which
  skips the window while any seen peer fails to answer DNS. Keep install one
  hour before reboot, no random delay, and no catch-up after downtime. Overlay
  clients and Technitium are not updated this way.
- A build is not installation proof. Keep VM, physical hardware, power-loss, and
  firmware verification as separate evidence.

## Role profiles and hardware captures

Each role has a folder `burn-history/os-installs/<role>/`. Guided builds read
its tracked `os.conf`; reviewed builds read its ignored `hardware.conf`, the
real capture. `DNS_APPLIANCE_INVENTORY_DIR` names the directory that holds
these per-role folders. The node inventory example is
`engine/installer/docs/examples/nodes.example.yml`.

- Never commit raw serials, UUIDs, MAC addresses, disk serials, or enabled
  destructive inventory for real machines. `hardware.conf` stays ignored.
- Capture inventory from a trusted live environment on the exact target device.
- Review product, NIC, disk, role, address, and minimum size before changing
  `destructive_install_enabled` to true.
- Enable only the current pilot role; expand one machine at a time after physical
  verification.
- Do not edit hashes merely to satisfy the installer. Recapture only after an
  intentional hardware change.
- Fixed addresses are `dns01=10.77.5.1`, `dns02=10.77.5.2`, and
  `dns03=10.77.5.3` unless a coordinated contract decision changes the design.
- Verify guided profiles with isolated install-gate fixtures; verify real
  captures only on the matching machine before enabling its one-at-a-time
  physical pilot.
