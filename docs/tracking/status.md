# Implementation Status

The current release state is a source-validated prototype, not a physically qualified installer or USB release. Built means the source path exists; verified names the highest evidence actually observed. Source-level CI claims below are bound to commit `be2a097c85052e2d68ed81f3bd2e73f5e7621490` and successful GitHub Actions run `38914948092` on 2026-10-16; later uncommitted documentation does not extend that evidence.

## Capability status

| Capability | Built | Highest verified state | Remaining work |
| --- | --- | --- | --- |
| One personal `jeonghan-home` World with DNS assets, network, nodes, services, and two media passes | Yes | Completed `inventory-capture` physical generation with full raw readback | Mount and inspect the payload, then qualify BIOS and UEFI boot |
| World-driven exact media selection | Yes | Manifest-bound `inventory-capture` physical write and generation inspection | Repeat the qualification path for the rebuilt `dns-install` image |
| Public Catalog for Proxmox VE, Proxmox Backup Server, TrueNAS SCALE, Pop!_OS, and Debian Live | Yes | Metadata contracts and isolated fixtures | Vendor-provenance archive and physical boot qualification per entry before use |
| Data-driven `locked-download` and `runtime-artifact` resolution | Yes | Isolated success and rejection simulations | A reviewed extension mechanism for any new source kind or profile adapter |
| HTTPS download with SHA-256 cache promotion | Yes | Source simulations | Clean online Linux preparation using the current pins |
| Nominal, offline, runtime-artifact, and read-only-device capacity calculation | Yes | Isolated tests and a prior read-only 16 GB macOS query | Exact result using the final rebuilt DNS ISO and target USB |
| Korean Ventoy presentation with no automatic timeout | Yes | Generated configuration checks | Physical BIOS and UEFI menu verification |
| Linux removable-device USB writer | Yes | Source simulation after target-resolution fix | Rebuilt disposable USB, readback, filesystem, BIOS, and UEFI evidence |
| Cross-platform exact-size raw-image builder and macOS MBR-last writer | Yes | Manifest-bound 15,833,497,600-byte physical write and full MBR-last raw readback | Mount and inspect filesystems and payload, then qualify BIOS and UEFI boot |
| Append-only World event and generation publication after verified write | Yes | Inspected physical macOS generation after full raw readback | Merge the generation through the protected pull-request path and repeat on Linux when needed |
| Offline Korean DNS appliance image with immutable locks | Yes | Source validation and ISO embedded-file readback logic; exactly-one-role build gate | Capture the three real inventories, then complete two clean amd64 Debian 13 builds and artifact comparison |
| Exact HP/NIC/internal-disk install gate with mapper ancestry resolution | Yes | Isolated rejection and disk-preparation simulation | VM BIOS/UEFI install and disposable physical `dns01` rerun |
| Retry-safe encrypted first-boot enrollment | Yes | Source contract | Power-loss and real exFAT fault injection |
| Three-node Technitium cluster bootstrap | Yes | Fixture/source checks | Live three-node cluster and primary-loss drill |
| DNS health, plan, and gated apply | Yes | Isolated simulation | Approved live canary apply and rollback; immutable reviewed-plan binding remains unbuilt |
| Encrypted backup collection and explicit restore | Yes | Source checks only | Add trusted-CA or pinned-fingerprint restore transport, then run isolated decrypt/import/canary drill; production restore is currently unqualified |
| One-off tagged Tailscale enrollment | Yes | Isolated tag/DNS/route/exit-node/SSH preference simulation | Tailnet policy review, explicit Serve/Funnel verification, three-node enrollment, reboot, and key-expiry/revocation observation |
| Dependency-free read-only status monitor | Yes | Python syntax and source inspection | Run from assembled USB against all three live nodes |
| Constrained MCP gateway over Tailscale-carried forced SSH | Yes | Isolated tool, input, and policy simulation | Add centralized credential-output filtering; then prove dedicated account, ACL, forced command, credential files, trusted CA, and live three-node reads |
| Router DHCP DNS cutover and rollback | Procedure only | No live evidence | Manual model-specific change after all node and recovery gates pass |

## Next dependency order

1. Build the fixed DNS ISO twice on amd64 Debian 13 and compare manifests and artifacts.
2. Pass disposable VM BIOS and UEFI installation with the mapper-backed installer-media fixtures represented.
3. Mount and inspect the completed `inventory-capture` USB filesystems and payload, then prove both firmware paths.
4. Enable only `dns01`, complete its physical install and enrollment, then repeat one at a time for `dns02` and `dns03`.
5. Prove cluster formation, trusted TLS, Tailscale restrictions, backup restore, and agent read access.
6. Perform router DHCP DNS cutover with a wired rollback client.
7. Publish each inspected physical USB event or generation through the protected pull-request path after the corresponding disposable write.

There is no source-code blocker to the first three steps. They require the supported Linux builder, disposable media, and physical HP access; source or documentation work cannot supply that evidence.

## Guided OS + DNS candidate (2026-10-21)

The guided path now captures identities and exact target-specific consent inside Debian Installer, then uses the existing guarded Debian OS + offline DNS installation path. On M5, 33 reviewed/guided source simulations passed, including cancellation, incorrect consent, changed hardware/size, multiple disks, USB/removable/mounted targets and active-role rejection. Image build, real debconf presentation, BIOS/UEFI full installation and physical HP qualification remain unproven. The previously completed physical USB generation remains inventory-only and does not install the OS.
