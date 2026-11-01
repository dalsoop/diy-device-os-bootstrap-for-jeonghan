# Implementation Status

The current release state is a source-validated prototype, not a publicly distributable prebuilt installer or a physically qualified DNS installer. Built means the source path exists; verified names the highest evidence actually observed. The earlier source-level CI claims remain bound to commit `be2a097c85052e2d68ed81f3bd2e73f5e7621490` and successful GitHub Actions run `38914948092` on 2026-10-16. Redistribution-policy evidence added on 2026-10-17 is limited to local source-level contract, schema, syntax, ShellCheck, and simulation results; the updated GitHub `contracts` run, public prebuilt review, and protected Environment configuration remain unverified.

## Capability status

| Capability | Built | Highest verified state | Remaining work |
| --- | --- | --- | --- |
| One personal `jeonghan-home` World with DNS assets, the `10.77.0.0/16` network, nodes, services, overlay selection, and two media passes | Yes | Source checks and World contract simulation for the current address plan and overlays; completed `inventory-capture` and `dns-install` (`20261022024140-jeonghan-home`) physical generations with full raw readback | The `dns-install` generation `20261022024140-jeonghan-home` is retired (previous addresses, vulnerable kernel snapshot) and must not be used to install a node; write new media from a current build |
| World-driven exact media selection | Yes | Manifest-bound `inventory-capture` and `dns-install` physical writes and generation records | Physical HP boot and install from new `dns-install` media |
| Per-World overlay selection (Tailscale, NetBird, or both) with World/image agreement at readiness, build, and burn | Yes | World contract, image-builder, media-catalog, macOS writer, license-policy, and DNS license simulations | Guided ISO build from merged `main` and its manifest check against the World |
| Debian snapshot carrying the CVE-2026-98432 kernel fix (`20261031T143759Z`) | Yes | `verify-locks` with mirror equality; signed snapshot indexes list `linux` 6.12.113-1 in `trixie-security` | Package-closure evidence of `linux` 6.12.113-1 or later from the built image |
| Appliance firewall in its own table `inet dns_appliance`, overlay port limits in prerouting, per-selection recursion ACL and overlay health | Yes | Firewall namespace simulation (real packets in network namespaces, with a NetBird-style `wt0` accept at the top of the input chain and stand-in overlay tables through load, reload, and stop); management simulation of the rendered rules, `nft -c` of each selection, recursion ACL, and per-overlay health | Live check on installed nodes with the real NetBird and Tailscale clients running |
| Unattended Debian upgrades with peer-guarded staggered reboots | Yes | Appliance update simulation (reboot decision, persistence, metrics, rendered per-role timers); image builder simulation (installed kernel hook run through `run-parts` writes `/run/reboot-required` and the guard reboots) | Live unattended-upgrade run and reboot-skip drill on installed nodes |
| Public Catalog v2 for Proxmox VE, Proxmox Backup Server, TrueNAS SCALE, Pop!_OS, and Debian Live | Yes | Executable contracts, draft-2020-12 schema validation, and accepted/rejected source fixtures | Vendor-provenance archive and physical boot qualification per entry before use |
| Data-driven `locked-download` and `runtime-artifact` resolution | Yes | Isolated success and rejection simulations | A reviewed extension mechanism for any new source kind or profile adapter |
| HTTPS download with SHA-256 cache promotion | Yes | Source simulations | Clean online Linux preparation using the current pins |
| Nominal, offline, runtime-artifact, and read-only-device capacity calculation | Yes | Isolated tests and a prior read-only 16 GB macOS query | Exact result using the final rebuilt DNS ISO and target USB |
| Korean Ventoy presentation with no automatic timeout | Yes | Generated configuration checks | Physical BIOS and UEFI menu verification |
| Linux removable-device USB writer | Yes | Source simulation after target-resolution fix | Rebuilt disposable USB, readback, filesystem, BIOS, and UEFI evidence |
| Cross-platform exact-size raw-image builder and macOS MBR-last writer | Yes | Manifest-bound 15,833,497,600-byte physical write and full MBR-last raw readback | Mount and inspect filesystems and payload, then qualify BIOS and UEFI boot |
| Append-only World event and generation publication after verified write | Yes | Inspected physical macOS generation after full raw readback | Merge the generation through the protected pull-request path and repeat on Linux when needed |
| Offline Korean DNS appliance image with immutable locks | Yes | Source validation and ISO embedded-file readback logic; exactly-one-role build gate | Capture the three real inventories, then complete two clean amd64 Debian 13 builds and artifact comparison |
| Personal-use, source-release, and prebuilt-release policy evaluation | Yes | Local allow/deny, DNS double-gate, obligation, checksum, schema, and writer-preflight simulations | Keep generated-artifact policy disabled; complete human exact-artifact review before any prebuilt proposal |
| Source-only release workflow | Yes | Source inspection and local repository contract prove a fixed non-executable evidence staging list with generated-media rejection | Obtain a successful updated GitHub `contracts` run; verify the workflow on the designated builder without treating its evidence artifact as a public release |
| Protected prebuilt publication boundary | Policy only | Required Environment name and two-gate rule are encoded in policy and contracts | Human owner must create and verify `prebuilt-distribution` with a human-only required reviewer; no publishing job exists |
| Exact HP/NIC/internal-disk install gate with mapper ancestry resolution and swap, holder, and synchronization checks | Yes | Guided VM BIOS and UEFI install from the exact-size raw image (`63cd0f4`, Secure Boot off); isolated source simulation of the current gate | Guided VM BIOS and UEFI reinstall with the current gate, then disposable physical `dns01` rerun |
| Retry-safe encrypted first-boot enrollment | Yes | Source contract | Power-loss and real exFAT fault injection |
| Three-node Technitium cluster bootstrap | Yes | Fixture/source checks | Live three-node cluster and primary-loss drill |
| DNS health, saved immutable plan, and plan-bound apply | Yes | Isolated simulation of plan saving, immutability, hash, endpoint, commit, zone, drift, and replay rejection | Approved live canary apply and rollback; pull-request approval binding remains unbuilt |
| Encrypted backup collection and explicit restore | Yes | Source checks only | Add trusted-CA or pinned-fingerprint restore transport, then run isolated decrypt/import/canary drill; production restore is currently unqualified |
| One-off tagged Tailscale enrollment | Yes | Isolated tag/DNS/route/exit-node/SSH preference simulation | Tailnet policy review, explicit Serve/Funnel verification, three-node enrollment, reboot, and key-expiry/revocation observation |
| One-off NetBird enrollment with setup-key deletion | Yes | NetBird enrollment simulation, including secret non-disclosure and unconfirmed deletion | Network range `10.78.0.0/16` and `Default` policy removal before the first enrollment, then live three-node enrollment and reboot |
| Dependency-free read-only status monitor reaching nodes by name, with reboot state | Yes | Status monitor simulation and Python syntax | Management-host name resolution without the DNS cluster, then a run against all three live nodes |
| Constrained MCP gateway over overlay-carried forced SSH, `tunnel_status` for both overlays | Yes | Isolated tool, input, policy, and overlay-status simulation | Add centralized credential-output filtering; then prove dedicated account, overlay policy, forced command, credential files, trusted CA, NetBird daemon-socket access, and live three-node reads |
| Router move to `10.77.0.1/16` | Procedure only | No live evidence | Manual operator step with a wired recovery client and the old router values |
| Router DHCP DNS cutover and rollback | Procedure only | No live evidence | Manual model-specific change after all node and recovery gates pass |

## Next dependency order

1. Obtain a successful updated GitHub `contracts` run and keep the release workflow evidence-only.
2. Build the guided personal-use DNS ISO from merged `main` on amd64 Debian 13, confirm `linux` 6.12.113-1 or later in its package closure, and write new USB media; then build twice and compare manifests and artifacts when reproducibility is claimed.
3. Pass disposable VM BIOS and UEFI installation with the mapper-backed installer-media fixtures represented.
4. Move the router to `10.77.0.1/16` by hand with a wired recovery client.
5. Enable only `dns01`, complete its physical install and enrollment, then repeat one at a time for `dns02` and `dns03`.
6. Set the NetBird range and remove the `Default` policy, enroll the selected overlays, and prove cluster formation, trusted TLS, overlay restrictions, unattended upgrades and reboot skips, backup restore, and agent read access.
7. Perform router DHCP DNS cutover with a wired rollback client.
8. Publish each inspected physical USB event or generation through the protected pull-request path after the corresponding disposable write.

The GitHub check and protected Environment require repository-owner action. ISO, USB, firmware, installation, and network qualification require the supported Linux builder, disposable media, and physical HP access; source or documentation work cannot supply that evidence. None of those states grants public prebuilt redistribution approval.

## Guided OS + DNS candidate (2026-10-21)

The guided path now captures identities and exact target-specific consent inside Debian Installer, then uses the existing guarded Debian OS + offline DNS installation path. On the build host, 41 reviewed/guided source simulations passed, including cancellation, incorrect consent, changed hardware/size, multiple disks, USB/removable/mounted targets and active-role rejection. Image build, real debconf presentation, BIOS/UEFI full installation and physical HP qualification remain unproven. The `inventory-capture` physical USB generation that precedes this candidate is inventory-only and does not install the OS.

Update: commit `0f0664e` passed one disposable VM install per firmware from the exact-size Ventoy raw image (`burn-history/logs/checks/2026-10-21-guided-vm-qualification.md`): guided answers typed into the real dialogs, internal-disk boot, DNS over UDP and TCP, and encrypted enrollment with no plaintext secrets. Secure Boot was off. This is not physical, firmware or Secure Boot evidence.

Update (2026-10-22): after the license and redistribution policy merged, commit `63cd0f4` passed the same qualification (`burn-history/logs/checks/2026-10-22-guided-vm-qualification.md`), with the raw image license decision `personal-use`/`allow` and the license, notice and source files installed on the target. Its raw image is the current burn candidate.

Physical media (2026-10-22): the `63cd0f4` raw image (SHA-256 `53c6bff1…69d`) was written to the 30,784,094,208-byte SanDisk 3.2Gen1 with `world burn-image-macos` on the operator workstation, as a one-time operator exception to the build-host-only rule. Two-phase raw readback passed, and generation `20261022024140-jeonghan-home` records it. The write took 18 minutes and the `cmp` readback 33 minutes. This is a physical write and readback, not HP firmware boot or install evidence. That generation is retired: it carries the previous LAN addresses and a Debian snapshot with the vulnerable kernel, and no node is installed from it. Its record under `burn-history/logs/usb/` stays unchanged.

Physical media (2026-11-01 and 2026-11-02), same SanDisk 3.2Gen1, operator workstation, `world burn-image-macos` full write:

- 14:11 KST: the `3a2dea1` guided image (raw SHA-256 `3223f1be…1bb2`); two-phase readback passed and generation `20261101132210-jeonghan-home` records it. Superseded by the next write, not installed from.
- 00:22 KST: the `faff60b` guided image (ISO SHA-256 `23918c62…68c6` before the glyph fix build; raw SHA-256 `4ff901fb…8b17`), built in an amd64 Debian 13 container on m5m1 from merged `main`, with `linux-image-amd64` 6.12.113-1, Tailscale 1.104.1, NetBird 0.82.0 and the `home-10-77` network plan. The body (53 minutes at 9.7 MB/s) and the first MiB were written and both readbacks passed, then the final `diskutil unmountDisk` was refused by Spotlight's `mdsync` holding the newly mounted volume, the writer exited non-zero, and the recorder published only the failed event `burn-history/logs/usb/failed/2026/20261101231141-jeonghan-home-0288a50c.json` (readback `pending`, because the writer's evidence was never set to passed). The stick was then force-unmounted and ejected by hand. This stick is the one the operator installs from; no generation exists for it. The writer now retries the final unmount and forces it (#21), so the next write publishes a generation.

Neither write is HP firmware boot or install evidence.

The source contract suite passed on the build host, including World, Catalog, media, inventory wizard, management, Tailscale and Agent Gateway simulations. Signed Debian installer fetch rejection fixtures also pass. The first real image build exposed Simple-CDD 0.6.9 requesting a removed i386 installer; the candidate now uses signed/checksummed amd64-only custom-installer inputs and still needs a successful image build.

## 10.77 LAN, kernel fix snapshot, overlays per World, and unattended upgrades (2026-11-01)

The source moves the home LAN to `10.77.0.0/16` (router `10.77.0.1`, nodes `10.77.5.1` through `10.77.5.3`), pins Debian snapshot `20261031T143759Z` for the CVE-2026-98432 kernel fix, lets the World select Tailscale, NetBird, or both and bundles only the selected clients, and adds unattended Debian upgrades with peer-guarded staggered reboots. This change is source-only: no ISO was built, no USB written, and no router, overlay account, or appliance touched.

Verified on the build host:

- Source checks of the `contracts` job, run in an `ubuntu:24.04` container that mirrors CI: SPDX headers, the documentation check, shell syntax, ShellCheck, Python and Ruby syntax, draft-2020-12 JSON Schema validation of the Catalog, World USB records, DNS component registry, component review, build manifest (Tailscale-only, NetBird-only, and dual fixtures plus rejection fixtures), final review, license decision, and raw-image manifest, Catalog verification, the embedded Catalog resolution, and `engine/installer/build/verify-locks`.
- Simulations: World contract (including missing, empty, duplicate, unknown, and non-list overlays), USB event, install gate, management (including `post_install_netbird`, the rendered firewall for Tailscale-only, NetBird-only, and both, the recursion ACL per selection, and per-overlay health), firewall namespace (in privileged network namespaces: each rendered selection passes `nft -c` and loads; with `iifname "wt0" accept` and `iifname "tailscale0" accept` inserted at the top of the input and forward chains, a listening TCP 8080 and 5380 stay unreachable over the selected overlay interfaces while DNS 53 and TCP 22, 9090, 9100, 53443 answer; a control without the prerouting chain shows the inserted rule would open TCP 8080; loading twice, the drop-in's stop (twice) and reload leave stand-in `inet netbird` and `ip ts-filter` tables unchanged), Tailscale enrollment, NetBird enrollment, status monitor, appliance update, DNS license, license policy, media catalog (World build and burn refusals on overlay mismatch), image builder (conditional build records, per-selection install step, World/image agreement, both Linux writers, and the installed kernel hook: in a private mount namespace with a fresh tmpfs `/run`, `run-parts --report --exit-on-error --arg=6.12.113+deb13-amd64 --arg=/boot/vmlinuz-6.12.113+deb13-amd64` over the installed `/etc/kernel/postinst.d` writes `*** System restart required ***` to `/run/reboot-required` and the package once to `/run/reboot-required.pkgs`, the installed `dns-appliance-reboot` at its default marker path issues no reboot before and a reboot after, and a read-only `/run` is reported without failing the kernel installation; the check fails when namespaces cannot be created), macOS writer (post-build overlay change refused through the Catalog digest), inventory wizard, documentation check, repository contract, and Agent Gateway (both, one, or neither overlay, invalid output, non-role peer filtering).
- Pre-build consistency checks, run in an amd64 Debian 13 container:
  - `verify-locks` requires the three Simple-CDD mirror timestamps to equal `DEBIAN_SNAPSHOT`, and the repository contract proves that a mismatched or missing mirror line is rejected.
  - `fetch-debian-installer` at `20261031T143759Z` verified the Release signatures, the installer checksum list, and all six amd64 text and graphical installer files; the `trixie` Release still reads version 13.7, so the netinst and installer pins stay valid.
  - `fetch-locked-sources` for the real World (`tailscale`, `netbird`) verified the Technitium OCI archive, the Tailscale archive and dependency-license report, and the NetBird 0.82.0 archive against its locked SHA-256, and again from cache; the NetBird archive carries the `netbird` binary at its root, where the appliance install step expects it.
  - Every package named in `dns.packages`, `dns-build.packages`, `dns.downloads`, and `installer-target-packages`, including `unattended-upgrades`, exists for amd64 in the snapshot's `trixie`, `trixie-updates`, or `trixie-security` indexes, and the `trixie-security` index carries `linux-image-amd64` 6.12.113-1 depending on `linux-image-6.12.113+deb13-amd64` 6.12.113-1.

What follows, outside this change: the operator's own assistant builds the guided ISO from merged `main` in an amd64 Debian 13 container on the build host and writes the USB after merge. Package-closure evidence of `linux` 6.12.113-1 or later comes from that build; the installer's own kernel is not the installed kernel.

Remaining:

- VM BIOS and UEFI qualification of the new image.
- Physical `dns01` pilot, then `dns02` and `dns03` one at a time.
- Router move to `10.77.0.1/16`, a manual operator step.
- NetBird network range `10.78.0.0/16` and removal or disabling of the `Default` policy before the first NetBird enrollment.
- Live Tailscale and NetBird enrollment of all three nodes.
- Live firewall check on installed nodes with the real NetBird and Tailscale clients running: the overlay port limits hold over `wt0` and `tailscale0`, and the clients' tables survive `nftables.service` reload and stop (see `docs/tracking/findings.md`).
- Live unattended-upgrade run and reboot-skip drill on installed nodes.
- Operator recapture or edit of private `hardware.conf` files that still carry the previous addresses.
- Re-enrolling a reinstalled node while a peer with the same role name still exists in Tailscale or NetBird yields a renamed peer (for example `dns01-1`) and breaks access by name; the stale peer must be removed by hand first. This is not automated.
- Whether the Agent Gateway account may read the NetBird daemon socket for `tunnel_status` is unverified.
- The appliances reach the Debian archive over the Internet for updates; this outbound dependency is part of the deployed state.
- USB generation `20261022024140-jeonghan-home` is retired and must not be used to install a node.
- A World that selects only one overlay has not been built: `build-image` relies on Simple-CDD skipping the unselected client's absent extras, read from its source but not observed. `jeonghan-home` selects both overlays.
- The post-build embedded-file check covers the kernel reboot-required hook but not the other unattended-upgrade and reboot payload files; a missing one of those would fail at installation instead of at build time.
- No real kernel package has run the hook yet: the first live security-kernel update on an installed node must show `/run/reboot-required.pkgs` naming the package and the guarded reboot following.
- The Ventoy USB's `licenses/` folder carries the full third-party notices, which name both overlays even for a single-overlay image; the ISO and the copied license texts follow the selection.
