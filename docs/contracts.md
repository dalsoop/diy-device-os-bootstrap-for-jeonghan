# Contracts

## Common conventions

The repository exposes command-line, JSON, filesystem, and MCP interfaces. Usage errors, invalid input, rejected safety checks, failed downloads, and incomplete operations exit nonzero or return a tool error. Human prose is informational; automation consumes versioned JSON or documented files.

Stable IDs use lowercase ASCII letters, digits, and hyphens. Configured repository paths are relative, normalized, non-empty, contain no empty, `.` or `..` segment, and remain inside their declared root. Unknown enum values, duplicate identities, duplicate destinations, and ambiguous target state are errors rather than fallback cases.

## Operator CLI

`./device-os` is the public command entry point.

| Interface | Input | Output | Error cases and side effects |
| --- | --- | --- | --- |
| `world validate` | Optional `DEVICE_OS_WORLD` and `DEVICE_OS_MEDIA` | Human confirmation naming resolved World and media | Nonzero for invalid YAML, references, address topology, language, media, or policy; no network or write |
| `world available` | Selected World and optional media override | Human list of available and selected public/local entries | Nonzero for invalid World or Catalog; no download or write |
| `world plan` | Selected World and optional media override | Human summary; generated versioned World and media plans in the work area | Nonzero for dirty/unresolvable identities, contract mismatch, unsafe path, or unknown entry; no download or write |
| `world capacity` | `--capacity <decimal-or-binary-size>` or read-only target query; optional runtime artifact/manifest pairs and `--offline` | Human or schema-version-1 JSON totals, sources, unknown/unverified IDs, `required_bytes`, and `fits` | Nonzero for malformed arguments; unknown/unverified data yields null final fit, not assumed success; never writes |
| `world simulate` | Selected World and optional media override | Plan plus explicit skipped download/write phases | Same validation errors as plan; no download or write |
| `world prepare` | Selected World; network and cache access | Verified selected public artifacts in ignored cache | Nonzero on HTTPS, digest, path, or promotion failure; never writes a block device |
| `world readiness` | Ignored inventory, public key inputs, locked caches, and generated DNS artifacts | Schema-version-1 JSON with redacted passed checks and blockers | Nonzero while any required DNS build or artifact input is absent; never prints raw hardware identity or secret material |
| `world build-image` | Exact byte size, new output path inside the checkout, verified selected artifacts and manifests | Exact-size MBR raw image, SHA-256 sidecar, and image manifest binding the raw bytes to the resolved Catalog and World media | Linux requires root; macOS requires Podman or Docker and builds only through a loop device inside the Linux VM; never opens a host physical disk |
| `world burn` | Whole Linux device, exact `ERASE <device> <serial>`, selected artifacts and manifests | Assembled and readback-verified removable media plus one World event or generation record | Destructive after live removable/root/serial/capacity/artifact checks; any unresolved or mismatched state fails before write |
| `world burn-image-macos` | Absolute exact-size MBR image with adjacent manifest, whole `/dev/diskN`, exact target phrase | Two-phase raw readback plus one World event or generation record | Rejects a raw-image hash, Catalog digest, revision, tree, World slug, or media ID mismatch before inspecting or writing the target; physical events are serialized |
| `available`, `plan`, `capacity`, `simulate`, `prepare`, `burn` | Installer reference collection rather than the user World | Same shapes as corresponding World commands | Contributor surface; must not be represented as the user's desired state |
| `include <id>`, `exclude <id>` | Public Catalog ID | Updated reference collection and human confirmation | Nonzero for absent/invalid ID; changes contributor reference selection only |
| `burn-image-macos` | Absolute MBR raw-image path with adjacent manifest, resolved reference Catalog, whole `/dev/diskN`, exact target phrase | Two-phase write and readback result | Destructive only when image bytes and provenance match the resolved selection, image and device sizes match, and the target is external, writable, non-root, non-virtual, and MBR-compatible |

`targets` lists only live removable physical media and prints the current exact
confirmation. The macOS phrase is `ERASE <device> <media-name> <USB-serial>
<exact-bytes>`. The writer re-resolves every field, invalidates the first MiB,
writes and verifies the remaining bytes, then writes and verifies the first
MiB. It rejects GPT images and images at or below 1 MiB.

## World Playbook

`world/world-playbook.yaml` uses API version `device-os.bootstrap/v1alpha1` and kind `WorldPlaybook`. It declares `Asia/Seoul`, safe draft paths, the completed-generation root, and generation format `{YYYYMMDDHHmmss}-{world-slug}`.

A draft World contains unique assets, networks, nodes, services, media definitions, one valid `defaultMedia`, and fail-closed policies. References resolve exactly once; static addresses are unique and belong to the referenced network; the gateway is directly reachable or has an explicit route. Supported presentation languages are `ko-KR` and `en-US`.

The resolver emits versioned JSON containing source paths, World identity, selected media ID, ordered entry IDs, language, and policy. When the Installer resolves media, the World order must exactly match the final entry order. A caller may choose another declared media ID but may not invent one.

The current `jeonghan-home` contract declares `inventory-capture=[debian-live]` and default `dns-install=[dns-appliance]`. A DNS media definition requires guarded unattended policy; every World requires exact hardware matching, one internal target disk, target-specific erase confirmation, and no automatic boot timeout.

## Catalog interfaces

`catalog/catalog/index.json` uses `schema_version: 1` and is the closed-world registry. Every referenced JSON file exists, every controlled JSON file is registered, and IDs and paths are unique. `catalog/bin/verify-catalog` exits zero only when the complete registry and semantic contract pass; it emits no media and changes no repository state.

A public media entry provides schema version, stable ID, group, release version, optional architecture, safe `images/*.iso` destination, menu alias, non-empty Korean and English descriptions, interactive/live boot behavior, `profile_adapter: none`, and a `locked-download` source. The source contains a basename-only filename, HTTPS URL, and lowercase 64-character SHA-256. A bootloader similarly provides stable identity, implementation, version, safe archive root, and locked source.

Published schemas reject extra properties. The executable jq validator currently does not reject every extra property, so consumers use only documented fields and must not treat schema strictness as runtime-enforced parity.

## Installer composition and resolved media plan

`installer/usb-media/composition.json` uses `schema_version: 1` and names product/repository identity, Catalog path and index, bootloader ID, reference collection, local-entry registry, USB labels and reserves, and safe repository bundles.

The resolved media plan records the repository commit, Catalog tree, product, USB properties, one bootloader, groups, ordered public/local entries, and bundles. A World-driven plan embeds the validated World plan. Public and local registries may not expose the same ID; entry IDs, source filenames, and destinations are unique.

Supported entry behaviors are `interactive-installer`, `live-environment`, and local `guarded-unattended`. Supported source kinds are `locked-download` and caller-supplied `runtime-artifact`; supported adapters are `none` and `dns-appliance`. A runtime artifact uses an absolute caller path and matching manifest whose digest names that exact artifact. Unknown kinds or adapters fail.

Repository bundles use `repository-file` or `repository-tree` with contained source and destination paths. Because current staging can follow symlinks without resolved-target containment, a tracked bundle containing any symlink is outside the accepted contract.

## Capacity JSON

Schema version 1 reports each selected entry's size and source, verified total, estimated total, fixed reserve, layout overhead, unknown IDs, unverified IDs, target capacity, `required_bytes`, and `fits`. Decimal units such as `16GB` and binary units such as `16GiB` are accepted. Remote header or one-byte probes are estimates. Exact final fit exists only when every selected artifact is locally verified.

## USB filesystem result

The data partition label is `DEVICE-OS`. It contains staged images, bundles, Ventoy configuration, resolved media metadata and digest, image checksums, guides, tools, project license, license history, third-party notices, source revision/archive information, and `manifests/LICENSES.SHA256`.

When the DNS adapter is selected, a separate FAT32 `DNS-ENROLL` partition stores public enrollment evidence, encrypted recovery generations, active pointers, and reinstall authorizations. FAT32 is readable by the signed Debian Installer kernel's FAT modules; exFAT is unsupported at this stage. Files must remain below FAT32's 4 GiB per-file limit. It is transport, not the long-lived secret store. The Ventoy `DEVICE-OS` data partition remains exFAT.

A completed personal World generation contains immutable `world.yaml`, `world.lock.json`, `media-manifest.json`, `verification.json`, and `event.json`. The event recorder seals `{YYYYMMDDHHmmss}-{world-slug}` before invoking the target-specific writer, requires schema-version-1 redacted evidence with passed readback, then atomically renames the staged directory into `world/worlds/`. It excludes images, caches, credentials, private keys, raw serials, MAC addresses, UUIDs, and recovery material.

The recorder holds one checkout-local lock across each physical write. Failed, cancelled, and recovered interrupted attempts never create a generation; they publish schema-version-1 records under `world/events/YYYY/{event-id}.json`. A successful event lives inside its generation. Simulations, plans, builds, and capacity checks create no event. Git commits and pushes remain an explicit pull-request workflow rather than a side effect of the root writer.

## DNS enrollment record

Appliance SSH and Cockpit use the `dns-operator` account. The encrypted
`secrets/operator-password` filename remains the recovery credential key.

`public.json` uses schema version 1 and records generation UUID, hostname, role, fixed address, hardware identity, installer build and image digest, public SSH and certificate fingerprints, service health, and completion time. It never contains a password, token, or private key.

A generation is complete only when `public.json`, `recovery.tar.age`, the sanitized install log, and `COMPLETE` exist and the role's `ACTIVE` pointer names that generation. Reinstall authorization names the same active generation and matching system UUID hash; an authorization for an older generation is invalid.

## DNS management commands

`management/network-preflight --json <router-cidr>` returns schema-version-1 topology, LAN reachability, optional outbound IP/DNS/HTTPS probes, phase gates, and blockers. `--offline` reports Internet readiness as unknown. It does not establish DNS health or installation evidence.

`dnsctl health` reads a fixed node. `dnsctl plan` returns current and desired hashes plus a human diff. `dnsctl apply` requires literal `APPLY`, a caller-supplied commit equal to `HEAD`, and a clean tracked zone file; it returns nonzero for authentication, TLS, state, or API failure and appends redacted audit JSONL for completed plan/apply outcomes. It does not consume a saved plan or prove pull-request approval.

Restore requires an explicit target URL and `RESTORE <exact-url>`, decrypts and validates the archive locally, then currently sends the token and backup with TLS certificate verification disabled. That interface is limited to isolated recovery drills and is not a production-qualified restore path. Backup collection accepts only encrypted outputs. Tailscale enrollment accepts protected OAuth credential-file paths, not credential values, and creates one short-lived node key at a time.

## Image and inventory commands

| Interface | Input | Output and side effects | Error cases |
| --- | --- | --- | --- |
| `installer/build/verify-locks` | Reviewed `build/locks/sources.env` | Prints `source locks: valid`; changes nothing | Nonzero for moving or malformed Debian/Tailscale URLs, malformed versions, timestamps, hashes, or OCI digests |
| `installer/installer/fetch-locked-sources` | Network access and optional ignored cache path | Downloads Technitium OCI, Tailscale archive, and dependency-license report to temporary files; atomically promotes only verified content; prints checksums | Nonzero for missing tools, network/TLS failure, remote or cached digest mismatch, or license-report mismatch; partial files are removed |
| `sh installer/installer/refresh-guided-iso <base.iso> <output.iso>` | Existing guided ISO and current checkout's guided preseed/scripts/templates; Linux with xorriso | Disposable iteration ISO with five guided files refreshed; verifies embedded bytes, BIOS/UEFI menus and disabled automatic boot; prints SHA-256; no release manifest | Nonzero for non-guided base, missing tools/files, output collision, failed ISO replay, stale embedded file, or enabled boot timeout; candidate cannot satisfy World runtime-artifact manifest checks |
| `installer/installer/capture-inventory <role> <address> <interface> <whole-disk>` | One fixed DNS role, address, existing NIC, and whole block device on the target HP | Writes a shell-format inventory record to stdout with hashed hardware identities and `destructive_install_enabled=false`; does not modify the disk | Exit 2 for wrong arguments/role; nonzero for absent NIC/disk, a partition instead of whole disk, unreadable/empty identity, or missing SHA-256 tool |
| `installer/installer/build-image` | Clean committed source; amd64 Debian 13; exact Simple-CDD version; verified caches; reviewed mode: three inventories and exactly one enabled role; guided mode: three disabled network profiles; operator public keys; age recipient | Builds ISO under `installer/installer/simple-cdd/images/`; verifies critical embedded files; writes checksums, build manifest, package lists, package hashes, and SPDX SBOM under the configured artifact directory | Nonzero for unsupported host, dirty source, missing/malformed public input, anything other than one enabled role, lock/cache mismatch, build failure, stale embedded content, or missing artifact |

`DNS_APPLIANCE_INSTALL_MODE=reviewed` is the default and requires exactly one enabled embedded inventory. `guided` uses disabled network profiles from `inventory/nodes/*.conf.example` (or `DNS_APPLIANCE_INVENTORY_DIR/*.conf`). Both modes install Debian OS and the offline DNS payload together. The embedded `install-mode` and manifest `install_mode` name the selected mode; missing mode means legacy `reviewed`, and unknown modes fail.

In guided mode, Debian Installer's debconf frontend asks for role and wired physical NIC, captures local DMI/NIC/disk hashes into `/run/dns-appliance/inventory`, and displays the address, gateway, disk model, serial and exact byte count. It requires `ERASE <role> /dev/<disk> <serial> <bytes>`. Capture never writes the internal disk. The `select-disk` phase rechecks the captured hardware, disk path and exact size, single eligible internal disk, installer ancestry, mounted state, confirmation and active-generation reinstall authorization before signature clearing. An additional internal disk blocks guided installation even when its identity differs. Runtime inventory and confirmation are volatile and are never embedded or committed.

A build does not authorize media or internal-disk writing. Its manifest is paired with the DNS runtime artifact during capacity and burn. `check-readiness` uses the same mode environment and rejects a mismatched ISO manifest. Guided mode removes the separate capture/rebuild round trip; it does not establish VM or physical installation proof.

Capture, the inventory wizard and the install gate use the same read-only `disk-identity` adapter, bundled beside the capture tools and the ISO gate. Kernel model/serial attributes are preferred; SATA serials may come from `ata_id --export` on the exact candidate block device. Failed, empty or ambiguous identity evidence is rejected, and the serial is re-read before disk preparation.

## Post-install management interfaces

| Interface | Input | Output and side effects | Error cases |
| --- | --- | --- | --- |
| `network-preflight [--json] [--offline] [ROUTER_CIDR]` | One IPv4 router interface, default `10.0.0.1/16` | Human text or schema-version-1 JSON for topology, route observation, router/node reachability, optional fixed Internet probes, phase gates, and blockers; no state change | Exit 2 for bad options/multiple CIDRs; nonzero for invalid IPv4 or a prefix that excludes fixed DNS nodes |
| `import-enrollment --enrollment <mount> --identity <age-key> --output <dir>` | Complete `ACTIVE` records for all roles and readable age identity | Validates public health, decrypts each recovery archive into temporary storage, installs role credentials with restrictive permissions, and removes plaintext temporary data | Nonzero for incomplete/malformed records, failed health assertions, decryption/archive failure, or missing secret files |
| `cluster-bootstrap` | Protected credentials directory and output path; optional age recipient, cluster domain, and zone | Creates or joins the three-node cluster, creates least-privilege DNS identities, applies `home.arpa`, proves canary resolution, and atomically emits one encrypted access bundle | Nonzero for missing credentials, existing output, invalid recipient, API/TLS/cluster/permission/zone/canary failure; bootstrap currently uses unverified TLS |
| `tailscale-enroll (--all|--role <role>)` | Protected OAuth files, optional fixed tag and SSH user | Mints one non-reusable one-hour key, transfers it over existing SSH, enrolls one node, deletes the remote file, attempts revocation, and verifies implemented tag/address/DNS/route/exit-node/SSH preferences | Exit 2 for bad role/options; nonzero for credential format, API, SSH, enrollment, preference, or reachability failure; revocation failure is best-effort and Serve/Funnel require separate inspection |
| `collect-backups <protected-dir>` | Destination directory and key-based operator SSH | Copies only `*.zip.age` from all three nodes without overwriting existing files; creates mode-0700 role directories | Exit 2 without destination; nonzero for SSH/rsync failure or any zero-byte encrypted file |
| `restore-node --url <origin> --token-file <file> --backup <age-file> --identity <age-key> --confirm 'RESTORE <origin>'` | Exact endpoint, protected token and identity, encrypted backup, exact confirmation | Decrypts to a mode-protected temporary ZIP, validates it, submits restore, removes plaintext, and reports API acceptance | Exit 2 for missing input; nonzero for confirmation, decryption, ZIP, transport, or API failure; TLS verification is disabled, so this is isolated-drill-only |
| `authorize-reinstall --enrollment <mount> --role <role> --confirm 'ERASE <role>'` | One completed active record and exact role confirmation | Hashes the active system UUID and atomically writes `<role>.allow` bound to the previous generation | Exit 2 for bad input/role; nonzero for missing active/public record, wrong confirmation, or hashing failure |

## Read-only status monitor

`installer/management/dns-appliance-status-monitor/start` accepts server arguments after requiring Python 3. `--config <json>` is required by the Python entry point; the wrapper supplies its bundled config. `--listen` defaults to `127.0.0.1`, `--port` to `8080`, and `--check-once` prints a JSON array instead of listening.

The configuration contains at least one node with `name`, IPv4 `address`, and DNS `query`. Invalid JSON, an empty node set, a missing field, invalid address, invalid DNS label, unavailable bind address, or occupied port terminates nonzero. Probe failures are returned as `ok:false` status data and do not trigger mutation.

In server mode, `GET /` and `GET /index.html` return UTF-8 HTML with `Cache-Control: no-store`; every other path returns 404. Each refresh probes DNS UDP/TCP 53 and TCP reachability for Cockpit 9090, Technitium 53443, and metrics 9100. There is no authentication or write endpoint, so a non-loopback `--listen` requires separately managed access control.

## Agent Gateway

The gateway is accessed through MCP stdio locally or a management-host forced SSH command over Tailscale. Every tool returns structured output or a tool error. Output is clipped at 64 KiB but is not content-redacted, so delegated commands must keep credentials out of stdout and stderr.

| Tool | Input | Output | Error and authority boundary |
| --- | --- | --- | --- |
| `repository_status` | None | Revision, branch, dirty-file list | Local read only |
| `world_validate` | Optional `dns-install` or `inventory-capture` | Delegated validation result | Rejects other media; no download/write |
| `world_plan` | Optional media | Delegated selected plan | No download/write |
| `world_simulate` | Optional media | Delegated skipped-phase simulation | No download/write |
| `world_capacity` | Capacity string, network-probe boolean, optional media | Delegated capacity JSON | Network probes default off; no write |
| `network_preflight` | Router CIDR and Internet-check boolean | Topology/reachability JSON | Fixed probes only; no repair |
| `tunnel_status` | None | Management host and `dns01`–`dns03` Tailscale state | Uses only administrator-fixed executable path |
| `dns_health` | `dns01`, `dns02`, or `dns03` | Delegated health JSON | Reader credential only; fixed node URLs |
| `dns_plan` | One fixed role | Delegated desired-state plan | Planner credential only; no apply |
| `dns_apply` | Fixed role, full lowercase 40-character approved commit, exact `APPLY home.arpa TO <role> AT <commit>` | Delegated apply result | Always discoverable but rejects calls unless host policy is enabled; requires applier token and trusted CA plus all `dnsctl` gates |

There is no gateway interface for USB burn, OS installation, restore, reinstall authorization, enrollment, router mutation, arbitrary shell, arbitrary path, arbitrary URL, or raw credential input.

`install-gate validate-profile <file> <role>` validates unique fields, required values, IPv4 ranges, prefix/netmask agreement, LAN membership, gateway reachability, management subnet containment and safe domain fields without reading hardware or writing disks. Image build, readiness and guided capture share this validator.

`fetch-debian-installer` fetches the locked Debian snapshot Release/signature and installer checksums, verifies Debian archive signatures and the entire digest chain, then atomically promotes the six required amd64 text/graphical installer files into the ignored cache. Existing mismatched components fail rather than being silently replaced. Temporary verification/download files are removed after success or failure. This is an input preparation operation, never disk-write authority.
