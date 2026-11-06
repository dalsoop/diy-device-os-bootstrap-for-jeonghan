# Operations

Run repository commands from the checkout root unless a procedure explicitly changes directories. Do not run a destructive example until its placeholder device, serial, artifact, and credential paths have been replaced from current live inspection.

## Prerequisites and checkout

Planning and simulation require Git, `jq`, and Ruby. Capacity probes and downloads also require `curl` and a SHA-256 implementation. Clone the personal repository and keep the generic source as a review-only upstream:

```sh
git clone https://github.com/dalsoop/diy-device-os-bootstrap-for-jeonghan.git
cd diy-device-os-bootstrap-for-jeonghan
git remote add upstream https://github.com/dalsoop/diy-device-os-bootstrap.git
```

On Debian or Ubuntu, install the read-only tool set:

```sh
sudo apt-get update
sudo apt-get install -y git jq ruby curl coreutils age
```

On macOS, install the command tools and one supported Linux container runtime:

```sh
brew install git jq ruby age podman
podman machine init --cpus 4 --memory 4096 --disk-size 100
```

The first `build-image` starts the Podman machine and builds the pinned Debian
13 media-builder container. Docker may be selected with
`--runtime docker`. Ventoy assembly runs against a loop device inside the Linux
VM; only `burn-image-macos` opens the separately confirmed macOS USB. The DNS
installer ISO itself still requires an amd64 Debian 13 build. Windows is
intentionally unsupported and is not a planned preparation or write platform.

## Validate the source checkout

Install the CI tools on Ubuntu, create an isolated Python environment, and run the same non-destructive surfaces used by the required `contracts` job:

```sh
sudo apt-get update
sudo apt-get install -y apparmor jq python3-jsonschema ruby shellcheck python3-venv
python3 -m venv /tmp/device-os-agent-check
/tmp/device-os-agent-check/bin/python -m pip install --requirement engine/agent/requirements.lock

engine/catalog/bin/verify-catalog
engine/catalog/tests/catalog-contract.sh
for record in engine/catalog/data/entries/*.json; do
  /usr/bin/python3 -m jsonschema \
    -i "$record" engine/catalog/schemas/media-entry.schema.json
done
for record in engine/catalog/data/bootloaders/*.json; do
  /usr/bin/python3 -m jsonschema \
    -i "$record" engine/catalog/schemas/bootloader.schema.json
done
engine/world/tests/world-contract-simulation.rb
engine/world/tests/usb-event-simulation.rb
(cd engine/installer && tests/install-gate-simulation.sh)
(cd engine/installer && tests/management-simulation.sh)
(cd engine/installer && tests/apparmor-signal-simulation.sh)
(cd engine/installer && tests/tailscale-enrollment-simulation.sh)
(cd engine/installer && tests/netbird-enrollment-simulation.sh)
(cd engine/installer && tests/status-monitor-simulation.sh)
(cd engine/installer && tests/appliance-update-simulation.sh)
(cd engine/installer && tests/dns-license-simulation.sh)
(cd engine/installer && tests/license-policy-simulation.sh)
(cd engine/installer && tests/media-catalog-simulation.sh)
(cd engine/installer && tests/image-builder-simulation.sh)
(cd engine/installer && tests/macos-writer-simulation.sh)
(cd engine/installer && tests/inventory-wizard-simulation.sh)
(cd engine/installer && tests/documentation-check-simulation.sh)
(cd engine/installer && tests/repository-contract.sh)
/tmp/device-os-agent-check/bin/python engine/agent/tests/gateway_simulation.py
```

The required CI job additionally validates every published USB record under `burn-history/logs/usb/` and `burn-history/logs/usb/failed/` against the v2 World schemas, and the DNS component registry, component review, build manifest, final review, license decision, and raw-image manifest schemas with both accepted and rejected fixtures. ShellCheck, shell syntax, Python syntax, Ruby syntax, and SPDX checks remain part of CI even when an operator runs only the focused simulations above. A source pass proves no physical media or appliance state.

## Check distribution mode

Personal self-build is allowed for the operator's own devices, but it is not
redistribution approval. Inspect the current decisions without downloading,
building, writing, or uploading anything:

```sh
./device-os license check --mode personal-use --json | jq
./device-os license check --mode source-release --json | jq
```

The first command currently allows the selected media with
`artifact-unreviewed` warnings. The second allows only the clean tracked source
snapshot. The release workflow may retain non-executable checksums, manifests,
package closure, component status, SBOM, and decision evidence for review, but
it never uploads an ISO, RAW, IMG, disk image, or complete USB content and does
not publish a GitHub Release.

Do not attempt prebuilt publication under the current policy. A future public
prebuilt procedure must complete these independent gates:

1. Review each selected bootloader and OS image against its exact version, URL,
   and SHA-256, including license, notices, corresponding source, trademark,
   and all required fulfillment files.
2. Review every DNS component, eliminate `NOASSERTION`, and separately review
   the final DNS ISO against the exact component registry, build manifest,
   SBOM, and obligation-file digests.
3. Enable generated-artifact distribution through a separately reviewed policy
   change and obtain a successful `prebuilt-release` CLI decision.
4. Run publication only behind the protected GitHub Environment
   `prebuilt-distribution`, configured with a human-only required reviewer.

No build, source release, CI result, physical write, or installation promotes
an artifact into the next state automatically. The protected Environment and
its human reviewer remain external configuration and must be verified by the
repository owner before any prebuilt workflow is added.

## Inspect the current World

```sh
./device-os world validate
./device-os world available
./device-os world plan
./device-os world capacity --capacity 16GB
./device-os world simulate
```

These commands do not download an image or write a device. Select the non-default inventory pass by setting the media ID for one invocation:

```sh
DEVICE_OS_MEDIA=inventory-capture ./device-os world plan
DEVICE_OS_MEDIA=inventory-capture ./device-os world simulate
```

Inspect redacted DNS-build blockers and live removable targets separately:

```sh
./device-os world readiness | jq
./device-os targets
```

Edit `burn-history/home.yaml` to change desired devices or media. Keep real hardware captures in the ignored `burn-history/os-installs/<role>/hardware.conf` and keys in the ignored `burn-history/keys/` (private files never committed), never in `home.yaml`.

## Check network readiness

From the management host, inspect the expected `/16` topology, node reachability, and Internet readiness separately:

```sh
engine/installer/management/network-preflight --json 10.77.0.1/16 | jq
engine/installer/management/network-preflight --offline --json 10.77.0.1/16 | jq
```

The offline form marks outbound DNS and HTTPS readiness unknown. Internet is required to fetch public artifacts and enroll Tailscale or NetBird (`network_gates.post_install_tailscale` and `post_install_netbird`), but the already-built DNS installer boots and installs offline. Installed appliances also reach the Debian archive over HTTPS for their unattended updates. A passing Internet probe does not establish LAN routing, node health, or DNS readiness.

Moving the router to `10.77.0.1/16` is a manual operator step; follow the address prerequisite in [`engine/installer/docs/network-cutover.md`](../engine/installer/docs/network-cutover.md), keep a wired recovery client and the old router values, and prove node reachability before any DHCP DNS change.

## Retired USB generation

USB generation `20261022024140-jeonghan-home` carries the previous LAN addresses and a Debian snapshot with the vulnerable kernel. It is retired: do not install or reinstall a node from it. Its record under `burn-history/logs/usb/` stays unchanged. Build a new DNS image from the current source and write new media.

## One USB: guided Debian OS and DNS installation

The guided image is a candidate until BIOS and UEFI installation and a disposable `dns01` pilot pass. Build and validate on the build host (amd64 Debian 13):

```sh
DNS_APPLIANCE_INSTALL_MODE=guided engine/installer/dns-image/build-image
DNS_APPLIANCE_INSTALL_MODE=guided engine/installer/dns-image/check-readiness
```

Only operator SSH public keys and the public age recipient enter the image. Keep the corresponding private keys outside the checkout on the management host. The default network profiles retain the planned `10.77.0.0/16` LAN and `10.77.5.1` through `.3`; do not deploy them on a `192.168.0.0/24` LAN without a coordinated network/profile change.

For changes limited to the guided Debian Installer flow (`install-gate`,
`prepare-installer`, `disk-identity`, guided templates, or the shared preseed),
reuse a previously built guided ISO as a disposable VM base. On the build host,
refresh only those files and boot the result directly in the disposable VM:

```sh
sh engine/installer/dns-image/refresh-guided-iso \
  engine/installer/dns-image/simple-cdd/images/BASE_GUIDED.iso \
  engine/installer/artifacts/guided-iteration.iso
```

This replays the base ISO's BIOS/UEFI boot metadata, replaces the five installer
files, checks the embedded bytes and boot-menu timeouts, and prints the new
candidate hash. It skips Simple-CDD package resolution, image assembly, and the
30 GB USB image build. The result deliberately has no production build manifest
and cannot be used for a World USB burn; it is only for disposable VM checks.
Changes to Debian packages, generated payload, network profiles, credentials,
or any other ISO content still require `build-image` to create a release
candidate. After the guided flow passes, run the full build and its manifest
checks once for the exact committed source before preparing production media.

Use the resulting ISO and matching build manifest with the existing `dns-install` World media assembly. Boot the USB deliberately, select the role and connected wired NIC, review the network and internal disk, and type the exact erase phrase shown. Debian and DNS install in that pass; the USB need not return to the management host for an inventory rebuild. An ambiguous, mounted, removable, USB-backed or unreadable internal target blocks installation. Never bypass a rejection by editing a hardware hash.

Keep the USB connected through first boot until encrypted enrollment completes. Qualify and recover `dns01` before repeating for `dns02` and `dns03`. Overlay enrollment (Tailscale, NetBird, or both, as the World selects) and cluster bootstrap still run from the management host after OS installation. An active role needs its existing generation-bound reinstall token plus a fresh on-target erase confirmation.

The reviewed-inventory path below uses the default `reviewed` mode.

## First pass: capture hardware inventory

Prepare only the `inventory-capture` selection. On Linux, burn it directly:

```sh
DEVICE_OS_MEDIA=inventory-capture ./device-os world prepare
lsblk -d -o NAME,MODEL,SERIAL,SIZE,TRAN,RM
sudo DEVICE_OS_MEDIA=inventory-capture ./device-os world burn \
  --device /dev/sdX \
  --confirm 'ERASE /dev/sdX USB_SERIAL'
```

On macOS, use the exact byte count printed by `targets` to build first and then
perform a separately confirmed write:

```sh
./device-os targets
DEVICE_OS_MEDIA=inventory-capture ./device-os world prepare
DEVICE_OS_MEDIA=inventory-capture ./device-os world build-image \
  --output "$PWD/engine/installer/artifacts/inventory-capture.raw" \
  --size EXACT_TARGET_BYTES
sudo DEVICE_OS_MEDIA=inventory-capture ./device-os world burn-image-macos \
  --image "$PWD/engine/installer/artifacts/inventory-capture.raw" \
  --device /dev/diskN \
  --confirm 'ERASE /dev/diskN MEDIA_NAME USB_SERIAL EXACT_TARGET_BYTES'
```

Keep the generated `.raw`, `.raw.sha256`, and `.raw.manifest.json` together.
The manifest binds the image hash to the exact Catalog revision, tree, World
slug, and media ID. The writer rehashes and compares that binding before it
inspects or writes the live target.

The resulting media contains Debian Live only. Boot each HP computer deliberately and follow the inventory guide on the USB. Capture one role at a time from the trusted live environment:

```sh
sudo engine/installer/dns-image/capture-inventory \
  dns01 10.77.5.1 enp1s0 /dev/sda \
  > burn-history/os-installs/dns01/hardware.conf
```

Repeat for `dns02` and `dns03` with their actual interface and disk. Review product, UUID, NIC MAC, disk model, disk serial, size, role, and address. Keep `destructive_install_enabled=false` except for the single current physical pilot.

## Build the offline DNS image

Use an amd64 Debian 13 builder. Copy only the operator's public SSH key and public age recipient into ignored input files:

```sh
cp /path/to/id_ed25519.pub \
  burn-history/keys/operator-authorized-keys
age-keygen -o /secure/dns-recovery-age-key.txt
age-keygen -y /secure/dns-recovery-age-key.txt \
  > burn-history/keys/age-recipient
```

Install build dependencies, verify locked external inputs, fetch the digest-pinned Technitium source and the World's selected overlay clients, and build:

```sh
sudo apt-get install -y simple-cdd debian-cd debian-archive-keyring \
  reprepro rsync xorriso isolinux syslinux-common skopeo jq curl ruby
engine/installer/build/verify-locks
engine/installer/dns-image/fetch-locked-sources
engine/installer/dns-image/build-image
```

`fetch-locked-sources` and `build-image` resolve the World (`DEVICE_OS_WORLD` when set) with Ruby and use its `overlays`: only the selected Tailscale and NetBird clients and their license material are fetched and embedded, and the build manifest records the selection. Changing the World's overlays requires a new build; `world readiness`, `world build-image`, and `world burn` refuse an image built for a different selection.

For the guided one-USB path, prefix the build with
`DNS_APPLIANCE_INSTALL_MODE=guided`; the default `reviewed` mode needs the
captured inventories. The first build on an empty cache downloads the whole
offline package set (about 2,100 packages, 1.8 GB) from `snapshot.debian.org`
and takes about 70 minutes on the build host; later builds reuse the mirror and take
minutes.

`build-image` refuses zero or multiple erase-enabled roles. Run
`./device-os world readiness` before the build and keep only the current pilot
set to `destructive_install_enabled=true`.

The ISO appears under `engine/installer/dns-image/simple-cdd/images/`; its matching manifest is `engine/installer/artifacts/build-manifest.json`. Retain the package closure, checksums, SBOM, and build manifest outside Git. A successful build does not authorize a USB write.

## Calculate exact fit and burn production media

Use the exact runtime artifact and matching manifest. A `PENDING` result is not a fit decision:

```sh
./device-os world capacity --capacity 16GB \
  --runtime-artifact dns-appliance=/absolute/path/dns-appliance.iso \
  --runtime-manifest dns-appliance=/absolute/path/build-manifest.json
```

On Linux, install `python3`, block-device tools, and exFAT support. Reconnect one disposable USB, resolve its current whole-disk path and serial, then burn:

```sh
sudo apt-get install -y python3 util-linux exfatprogs
lsblk -d -o NAME,MODEL,SERIAL,SIZE,TRAN,RM
sudo ./device-os world burn \
  --device /dev/sdX \
  --runtime-artifact dns-appliance=/absolute/path/dns-appliance.iso \
  --runtime-manifest dns-appliance=/absolute/path/build-manifest.json \
  --confirm 'ERASE /dev/sdX USB_SERIAL'
```

The command destroys the selected USB. Never reuse a previous device path, serial, or confirmation after a reconnect. The production `dns-install` selection contains only the DNS appliance image.

On macOS, build a raw image from the exact DNS artifact and manifest, then write
it. All paths passed into the container must stay inside this checkout:

An ISO built on the build host goes into
`engine/installer/dns-image/simple-cdd/images/`. Its `build-manifest.json`,
`component-redistribution-registry.json` and `sbom.spdx.json` go together into
`engine/installer/artifacts/`. `world prepare` fetches and verifies the locked Ventoy
release that every World image needs:

```sh
./device-os targets
./device-os world prepare
./device-os world build-image \
  --output "$PWD/engine/installer/artifacts/dns-install.raw" \
  --size EXACT_TARGET_BYTES \
  --runtime-artifact dns-appliance="$PWD/engine/installer/dns-image/simple-cdd/images/DNS_ISO" \
  --runtime-manifest dns-appliance="$PWD/engine/installer/artifacts/build-manifest.json"
sudo ./device-os world burn-image-macos \
  --image "$PWD/engine/installer/artifacts/dns-install.raw" \
  --device /dev/diskN \
  --confirm 'ERASE /dev/diskN MEDIA_NAME USB_SERIAL EXACT_TARGET_BYTES'
```

The image byte size must equal the target and the target must be removable, writable, MBR-compatible, and non-root. World burn commands process one device at a time. Passed readback creates a new tracked generation directory under `burn-history/logs/usb/`; failed or cancelled physical attempts create a tracked redacted event file under `burn-history/logs/usb/failed/`. Review those new files and publish them through the normal pull-request path—the root writer never commits or pushes.

## Verify and install one appliance at a time

From the mounted `DEVICE-OS` partition, verify the resolved input and staged files before boot:

```sh
sha256sum -c manifests/MEDIA-CATALOG.SHA256
sha256sum -c manifests/SHA256SUMS
sha256sum -c manifests/LICENSES.SHA256
```

Boot both BIOS and UEFI paths on disposable media before a production pilot. At the HP machine, choose the DNS entry deliberately and confirm that the reported internal disk serial matches the reviewed inventory. If the USB itself becomes a target or the physical parent is unresolved, stop rather than retry.

After the internal-disk boot, verify host-key fingerprint and key-only SSH, DNS over UDP and TCP, Cockpit, Technitium certificate fingerprint, NTP, metrics, encrypted enrollment output, and the active generation. Keep `dns02` and `dns03` disabled until the preceding role passes every gate.

## Unattended updates and guarded reboots

Each installed node updates itself from the Debian archive (point release and security) and reboots into updates one role at a time, in `Asia/Seoul`:

| Role | Install time | Reboot window |
| --- | --- | --- |
| `dns01` | 02:00 | 03:00 |
| `dns02` | 02:30 | 03:30 |
| `dns03` | 03:00 | 04:00 |

The package lists are refreshed immediately before each install. At its window a node reboots only when a reboot is required and every peer that has ever answered DNS still answers; a peer that has never answered, such as a node not installed yet, does not block. A missed time is not run at boot; the next attempt is the next night. Check the state on a node and from the management host:

```sh
systemctl list-timers apt-daily-upgrade.timer dns-appliance-reboot.timer
journalctl -t dns-appliance-reboot
curl -s http://dns01:9100/metrics | grep dns_appliance_reboot_
```

A node with consecutive skips is highlighted by the status monitor. Restore the failing peer before anything else; see "A guarded reboot can be skipped night after night" in `docs/engineering-notes.md`. Tailscale, NetBird, and Technitium are not updated this way. Tailscale and NetBird change only through a reviewed lock update, a new image, and a reinstall; Technitium changes through a reviewed lock update and the in-place update below (decision 0016).

## Update Technitium in place

A reviewed lock update on `main` names the new Technitium version and digests. A new image carries it for every later installation; installed nodes take it one at a time with this procedure. Make no DNS or cluster configuration change while it runs.

On the build host, from a clean checkout of the merged commit, verify the lock and fetch the archive; `fetch-locked-sources` checks the registry and archive digests against the lock and prints the archive's SHA-256:

```sh
engine/installer/build/verify-locks
engine/installer/dns-image/fetch-locked-sources
grep '^TECHNITIUM_' engine/installer/build/locks/sources.env
```

Before the first node, from the management host: all three nodes answer `dig @10.77.5.N canary.home.arpa A` and the same with `+tcp`, return the same `home.arpa` SOA serial, and the Primary's web console (Administration, Cluster) shows both Secondaries connected; a fresh encrypted settings backup of each node exists (the management host's daily backup job, run once more); and each node has `/etc/apparmor.d/abstractions/base.d/dns-appliance-podman-signal` and no `apparmor="DENIED"` signal entry in `journalctl -k` since its last container start.

Update the Secondaries first (`dns03`, then `dns02`) and the Primary `dns01` last. Start the next node only after the previous one has passed every check and run 30 minutes without a restart. For each node, copy `technitium-dns-<version>-amd64.oci.tar` from the build host's cache to the node's `/var/tmp/`, then on the node as `dns-operator`, with `NEW` set to the new `TECHNITIUM_VERSION`:

```sh
NEW=<version>
sha256sum /var/tmp/technitium-dns-$NEW-amd64.oci.tar          # the value fetch-locked-sources printed
sudo podman load -i /var/tmp/technitium-dns-$NEW-amd64.oci.tar
sudo podman image inspect --format '{{.Digest}}' docker.io/technitium/dns-server:$NEW
                                                              # the lock's TECHNITIUM_AMD64_DIGEST
sudo systemctl stop technitium-dns
sudo cp -p /etc/dns-appliance/sources.env /etc/dns-appliance/sources.env.previous
sudo tar -C /var/lib -cpf /var/lib/dns-appliance/technitium-previous.tar technitium
sudo chmod 0600 /var/lib/dns-appliance/technitium-previous.tar
sudo sed -i \
  -e "s/^TECHNITIUM_VERSION=.*/TECHNITIUM_VERSION=$NEW/" \
  -e "s/^TECHNITIUM_INDEX_DIGEST=.*/TECHNITIUM_INDEX_DIGEST=<lock value>/" \
  -e "s/^TECHNITIUM_AMD64_DIGEST=.*/TECHNITIUM_AMD64_DIGEST=<lock value>/" \
  /etc/dns-appliance/sources.env
sudo systemctl start technitium-dns
```

Within three minutes, check on the node and from the management host:

```sh
systemctl is-active technitium-dns                                # active
sudo podman inspect --format '{{.ImageName}}' technitium-dns      # docker.io/technitium/dns-server:<version>
systemctl show -p NRestarts technitium-dns                        # unchanged afterwards
sudo journalctl -u technitium-dns --since -10min | \
  grep -e 'Unhandled exception' -e NullReferenceException -e 'status=134'   # nothing
sudo journalctl -k --since -10min | grep 'apparmor="DENIED"'      # nothing
dig @10.77.5.N canary.home.arpa A +short                          # 10.77.9.9, also with +tcp
dig @10.77.5.N home.arpa SOA +short                               # the other nodes' serial
```

The Primary's web console must show the node connected with a configuration sync after the restart. When the node has passed and stayed up for 30 minutes, replace its first-boot archive and remove the copy:

```sh
sudo install -m 0644 /var/tmp/technitium-dns-$NEW-amd64.oci.tar /usr/lib/dns-appliance/technitium.oci.tar
rm /var/tmp/technitium-dns-$NEW-amd64.oci.tar
```

Roll a node back when it does not become active, restarts, logs an exception or an AppArmor denial, answers the canary wrongly, or loses its cluster connection. The previous image stays in Podman's storage:

```sh
sudo systemctl stop technitium-dns
sudo cp -p /etc/dns-appliance/sources.env.previous /etc/dns-appliance/sources.env
sudo mv /var/lib/technitium /var/lib/technitium.failed
sudo tar -C /var/lib -xpf /var/lib/dns-appliance/technitium-previous.tar
sudo systemctl start technitium-dns
```

Run the same checks with the previous version, stop the rollout, and keep `/var/lib/technitium.failed` for diagnosis. After all three nodes have run the new version for a day, remove the rollback copies (`sources.env.previous`, `technitium-previous.tar`) and the previous image (`sudo podman image rm docker.io/technitium/dns-server:<previous version>`).

## Import enrollment and form the DNS cluster

After all three standalone nodes have complete enrollment records:

```sh
engine/installer/management/import-enrollment \
  --enrollment /Volumes/DNS-ENROLL \
  --identity /secure/dns-recovery-age-key.txt \
  --output /secure/dns-bootstrap

DNS_CLUSTER_CREDENTIALS_DIR=/secure/dns-bootstrap \
DNS_CLUSTER_ACCESS_OUTPUT=/secure/cluster-access.json.age \
  engine/installer/management/cluster-bootstrap
```

Move imported values into the principal secret store, rotate bootstrap credentials, and delete temporary plaintext. Verify cluster peers and a DNS canary before enabling another management step.

## Enroll the overlays

Enroll each overlay the World selects (`overlays` in `burn-history/home.yaml`); an unselected client is not installed on the appliances. Both commands reach the nodes over LAN SSH at `10.77.5.1` through `10.77.5.3`, need Internet access to the overlay control plane, and never move a long-lived credential to an appliance. Before re-enrolling a reinstalled node, remove its stale peer with the same role name from the overlay by hand; otherwise the new peer is renamed (for example `dns01-1`) and access by role name breaks.

### Tailscale

Apply the reviewed tailnet policy first. Then provide protected OAuth file paths:

```sh
TAILSCALE_OAUTH_CLIENT_ID_FILE=/secure/tailscale/client-id \
TAILSCALE_OAUTH_CLIENT_SECRET_FILE=/secure/tailscale/client-secret \
  engine/installer/management/tailscale-enroll --all
```

Confirm each node's hostname, `tag:dns-appliance`, Tailscale address, peer reachability, `accept-dns=false`, and absence of routes, exit-node behavior, Tailscale SSH, Serve, and Funnel.

For remote DNS, use the three enrolled nodes' Tailscale IPv4 addresses as tailnet nameservers, not their `10.77.5.x` LAN addresses. No subnet routing is required. First allow the intended client identities to reach `tag:dns-appliance` on both UDP and TCP 53 in the tailnet policy; `engine/installer/management/tailscale-policy.example.hujson` allows every tailnet member (`autogroup:member`), and its `tests` section, with the owner's login and another existing tag filled in, makes the tailnet reject a policy that takes ports 22, 9090, or 53 from the owner or gives them to that tag. The appliance recursion ACL includes `100.64.0.0/10`; nftables accepts DNS on `tailscale0` and rejects that source range on other network interfaces.

Before changing tailnet DNS, run `dig @<node-tailscale-ip> home.arpa SOA` and `dig @<node-tailscale-ip> example.com A` from an approved remote client for each node, then repeat both with `+tcp`. Check that an unauthorized peer cannot query them. These live checks require installed, enrolled appliances and are separate from source simulations.

Choose restricted nameservers for `home.arpa` when only internal names should use the appliances. To send public lookups through them as well, configure global nameservers and enable the tailnet DNS override on clients. Keep all three appliances on `--accept-dns=false` to avoid making their own resolver depend on this client configuration. All three nameservers must serve the same intended data; listing them does not establish strict primary/secondary query order. Technitium web administration still uses the LAN listener or a verified SSH tunnel to loopback.

### NetBird

Complete these preconditions in the NetBird dashboard before the first appliance enrolls:

1. Under Settings > Networks, set the network range to `10.78.0.0/16`. It must stay outside `100.64.0.0/10`, which Tailscale claims on every interface of a node that runs both clients.
2. Remove or disable the built-in all-to-all `Default` policy.
3. Create the appliance group (`dns-appliances` by default) and an admin group, then create the policies in `engine/installer/management/netbird-policy.example.json` after replacing each `<group-id:NAME>` placeholder with that group's ID. They let the admin group reach the appliances on TCP 22, 53, 9090, 9100, and 53443 and UDP 53, and the appliances reach each other on TCP 53443.
4. Create a dedicated service user and a personal access token with the narrowest role that can create and delete setup keys and read groups, peers, routes, and network routers. Store the token on one line of a protected file outside the checkout.

Then enroll:

```sh
NETBIRD_API_TOKEN_FILE=/secure/netbird/api-token \
  engine/installer/management/netbird-enroll --all
```

`NETBIRD_MANAGEMENT_URL` selects a self-hosted management server by its HTTPS origin instead of hosted NetBird Cloud. The command creates one one-off setup key per node, deletes it after use, and verifies each node's hostname, address in `10.78.0.0/16`, group membership, disabled DNS management, routes and NetBird SSH server, absence of any routing-peer role, and a resolver naming only `127.0.0.1`. If it reports that a setup key's deletion could not be confirmed, delete the named key ID in the dashboard.

## DNS change and router cutover

The cluster serves two reviewed zones: `burn-history/dns-records.zone` (`home.arpa`) and `burn-history/dns-reverse-records.zone` (`77.10.in-addr.arpa`, one PTR record per static name). They hold every record except the SOA and apex NS records, which the cluster manages for zones in its catalog; `dnsctl` imports and compares each zone without them. Plan and apply each zone on its own.

### Reach the API

The Technitium API listens only on each appliance's loopback and LAN addresses. On the LAN, `TECHNITIUM_URL=https://10.77.5.1:53443` reaches the cluster Primary `dns01`. A management host outside the LAN opens an SSH tunnel over the overlay to `dns01`'s `127.0.0.1:53443` and uses the tunnel's local end as `TECHNITIUM_URL`:

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:53443:127.0.0.1:53443 dns-operator@dns01
```

Keep that command running in its own terminal. A saved plan binds the exact `TECHNITIUM_URL`, so plan and apply through the same local URL; a plan made on the LAN URL cannot be applied through the tunnel, or the reverse. With `TECHNITIUM_CA_FILE`, curl checks the certificate's name against the URL's host: when the certificate does not name `127.0.0.1`, map a name it carries to `127.0.0.1` in the management host's hosts file and use that name in the URL, for example `https://dns01.dns-cluster.home.arpa:53443`.

### Create the reverse zone once

`dnsctl` imports into an existing zone only; while `77.10.in-addr.arpa` does not exist, plan fails with the export error Technitium returns. Create it once on `dns01`, the cluster Primary, as a Primary zone in the cluster catalog `cluster-catalog.<cluster domain>` (`cluster-catalog.dns-cluster.home.arpa` with the default cluster domain), so it replicates to `dns02` and `dns03` and the cluster manages its SOA and apex NS, as `cluster-bootstrap` does for `home.arpa`. Use an administrator token of `dns01` from a protected header file whose one line is `Authorization: Bearer <token>` (mode 0600, outside the checkout), so the token never appears in a command argument:

```sh
curl --fail --silent --show-error \
  --cacert /secure/dns/technitium-ca.pem \
  --header @/secure/dns/admin-authorization-header \
  -X POST "$TECHNITIUM_URL/api/zones/create" \
  --data-urlencode zone=77.10.in-addr.arpa \
  --data-urlencode type=Primary \
  --data-urlencode catalog=cluster-catalog.dns-cluster.home.arpa
```

The response must be JSON with `"status":"ok"`; Technitium also reports errors with HTTP success and `"status":"error"`. Then run `dnsctl plan burn-history/dns-reverse-records.zone` with the planner token: it must print a plan for `77.10.in-addr.arpa` whose diff adds every PTR record. If the export is refused for access, give `agent-dns-reader` and `agent-dns-planner` view and `agent-dns-applier` view and modify permission on the new zone, matching `home.arpa`, in the web console's zone permissions on `dns01`, and plan again.

### Plan and apply

Check health, create a plan, compare it with the reviewed zone change, then apply from the exact approved clean commit using the command's literal confirmation:

```sh
export TECHNITIUM_URL=https://10.77.5.1:53443   # or the tunnel's local URL
export TECHNITIUM_TOKEN_FILE=/secure/dns/reader-token
export TECHNITIUM_CA_FILE=/secure/dns/technitium-ca.pem
engine/installer/management/dnsctl health

export TECHNITIUM_TOKEN_FILE=/secure/dns/planner-token
engine/installer/management/dnsctl plan burn-history/dns-records.zone \
  --out /secure/dns/plans/<new-plan>.json

export TECHNITIUM_TOKEN_FILE=/secure/dns/applier-token
engine/installer/management/dnsctl apply \
  --plan /secure/dns/plans/<new-plan>.json \
  --plan-sha256 <plan_sha256> \
  --confirm APPLY
```

Use `burn-history/dns-reverse-records.zone` in place of `burn-history/dns-records.zone` for the reverse zone. Save the plan from a clean checkout of the reviewed commit and review it; `plan --out` prints its `plan_sha256` on stderr. The diff lists records as `<owner> <ttl> IN <TYPE> <data>` with absolute names and leaves out the SOA and apex NS, so a changed SOA serial in the file alone is not a change. Apply rejects a different hash, endpoint, `HEAD`, or zone file, a live zone whose export changed in any byte since the plan (a new live SOA serial included), and a plan already applied; in each case make and review a new plan. Verify pull-request approval before apply; the command does not prove it. Change one logical zone operation at a time and query the canary over UDP and TCP before continuing; after a reverse-zone apply, also query one PTR record, for example `dig @10.77.5.1 -x 10.77.0.1` and the same with `+tcp`.

Router DHCP DNS changes are last. Record old values, retain a wired recovery client, advertise all three resolver addresses, renew one test lease, and observe a full lease cycle. If client resolution fails, restore the old DHCP DNS values before investigating the nodes.

## Backup, restore, and reinstall

Collect only already-encrypted backups:

```sh
engine/installer/management/collect-backups /secure/dns-backups
```

Periodically decrypt and restore one in an isolated Technitium environment; file presence alone is not recovery proof. The current restore command always disables TLS certificate verification. Use it only for an isolated restore drill; it is not qualified for a production node until trusted-CA or pinned-fingerprint verification is implemented. The drill still binds confirmation to the exact target URL:

```sh
engine/installer/management/restore-node \
  --url https://restore-lab.local:53443 \
  --token-file /secure/dns/restore-token \
  --backup /secure/dns-backups/dns01/backup.zip.age \
  --identity /secure/dns-recovery-age-key.txt \
  --confirm 'RESTORE https://restore-lab.local:53443'
```

Verify the restored canary and remove the isolated lab plaintext afterward; do not target a production node with this command. A completed appliance can be reinstalled only after a generation-bound authorization is written:

```sh
engine/installer/management/authorize-reinstall \
  --enrollment /Volumes/DNS-ENROLL \
  --role dns01 \
  --confirm 'ERASE dns01'
```

## Resolve role names on the management host

The status monitor and the Agent Gateway reach the nodes as `dns01`, `dns02`, and `dns03`; the management host's resolver decides which path a name takes (LAN, Tailscale, or NetBird). The management host must resolve these names without depending on the DNS cluster itself, so that both still reach the nodes when the cluster fails. Use a hosts file entry or an overlay's own DNS (Tailscale MagicDNS or NetBird DNS), never the appliances as the management host's resolver for these names. The status monitor reports a name that does not resolve as a per-node name-resolution failure.

## Deploy the Agent Gateway

Use a dedicated non-sudo management-host account and a checkout at `/srv/diy-device-os-bootstrap-for-jeonghan`. Create a Python 3.10-or-newer environment outside the checkout and install only the locked dependencies:

```sh
sudo useradd --create-home --shell /bin/sh device-agent
sudo install -d -o device-agent -g device-agent /opt/device-os-agent
sudo -u device-agent python3 -m venv /opt/device-os-agent/venv
sudo -u device-agent /opt/device-os-agent/venv/bin/python -m pip install \
  --requirement /srv/diy-device-os-bootstrap-for-jeonghan/engine/agent/requirements.lock
```

Provision mode-0600 reader, planner, and optional applier token files readable by only `device-agent`; provision the trusted Technitium CA separately. Set the fixed gateway variables in the account's reviewed host-side environment and never accept them from the SSH client:

```sh
DEVICE_OS_AGENT_PYTHON=/opt/device-os-agent/venv/bin/python
DEVICE_OS_AGENT_DNS_READER_TOKEN_FILE=/secure/dns/reader.token
DEVICE_OS_AGENT_DNS_PLANNER_TOKEN_FILE=/secure/dns/planner.token
DEVICE_OS_AGENT_DNS_APPLIER_TOKEN_FILE=/secure/dns/applier.token
DEVICE_OS_AGENT_TECHNITIUM_CA_FILE=/secure/dns/technitium-ca.pem
DEVICE_OS_AGENT_DNS01_URL=https://dns01:53443
DEVICE_OS_AGENT_DNS02_URL=https://dns02:53443
DEVICE_OS_AGENT_DNS03_URL=https://dns03:53443
```

Omit the applier token and `DEVICE_OS_AGENT_ALLOW_APPLY` for the initial read-only deployment. Add the client's public key to the dedicated account with a forced command:

```text
restrict,command="/srv/diy-device-os-bootstrap-for-jeonghan/engine/agent/run" ssh-ed25519 AAAA... operator-agent
```

When an overlay CLI is not on the account's `PATH`, also set `DEVICE_OS_AGENT_TAILSCALE_COMMAND` or `DEVICE_OS_AGENT_NETBIRD_COMMAND` to its absolute executable path. The SSH server must not use `AcceptEnv` for gateway variables. The overlay access policy (a tailnet ACL, or a NetBird policy from the client's group to the management host's group on TCP 22 as in `engine/agent/netbird-policy.example.json`) and the host firewall permit only the reviewed client identity to reach this account's SSH port; no router port is forwarded. Configure the remote MCP client to invoke ordinary SSH:

```json
{
  "mcpServers": {
    "device-os": {
      "command": "ssh",
      "args": ["-T", "device-agent@management-host"]
    }
  }
}
```

Verify the isolated tool boundary and then the live forced-command path:

```sh
/opt/device-os-agent/venv/bin/python \
  /srv/diy-device-os-bootstrap-for-jeonghan/engine/agent/tests/gateway_simulation.py
ssh -T device-agent@management-host
```

Prove repository, World, capacity, network, tunnel, DNS health, and DNS plan calls first. Confirm physical-media, installation, restore, enrollment, arbitrary command, path, and URL tools are absent. Only after trusted TLS and rollback are proven may the host administrator add the applier token, set `DEVICE_OS_AGENT_ALLOW_APPLY=1`, and run one separately approved canary apply.

## Runtime configuration

| Name | Role and allowed scope |
| --- | --- |
| `DEVICE_OS_MEDIA` | Selects one declared World media ID for the current invocation; current values are `dns-install` and `inventory-capture` |
| `DEVICE_OS_WORLD` | Selects an explicit draft when more than one exists; path must remain within `burn-history/` as registered in `burn-history/.paths.yaml` |
| `DEVICE_OS_WORLD_PLAN` | Installer working path for a resolved World plan; generated, not committed |
| `USB_MEDIA_CATALOG` | Installer working path for the resolved media plan; generated, not committed |
| `USB_MEDIA_CACHE_DIR` | Ignored cache for verified bootloader and public OS downloads; changing it does not bypass digest checks |
| `DNS_APPLIANCE_INVENTORY_DIR` | Directory that holds the per-role folders (`dns01/`, `dns02/`, `dns03/`) used by the DNS image build and readiness check; defaults to `burn-history/os-installs`. Reviewed mode reads `<dir>/<role>/hardware.conf` (ignored real captures); guided mode reads `<dir>/<role>/os.conf` |
| `DNS_APPLIANCE_AUTHORIZED_KEYS` | File containing only the operator's public SSH key material for the image; defaults to `burn-history/keys/operator-authorized-keys` |
| `DNS_APPLIANCE_AGE_RECIPIENT` | File containing only the public age recipient used to encrypt enrollment output; defaults to `burn-history/keys/age-recipient` |
| `DNS_APPLIANCE_CACHE_DIR` | Ignored cache for digest-pinned DNS runtime inputs; defaults to `engine/installer/cache/` |
| `DNS_APPLIANCE_ARTIFACT_DIR` | Ignored destination for build manifests, checksums, package closure, and SBOM; defaults to `engine/installer/artifacts/` |
| `DNS_CLUSTER_CREDENTIALS_DIR` | Protected management-host directory containing imported node credentials |
| `DNS_CLUSTER_ACCESS_OUTPUT` | Protected destination for the encrypted cluster access bundle |
| `DNS_CLUSTER_AGE_RECIPIENT` | Public age-recipient file used for the encrypted cluster access bundle; defaults to `burn-history/keys/age-recipient` |
| `DNS_CLUSTER_DOMAIN` | Cluster domain override; defaults to `dns-cluster.home.arpa` and must match reviewed DNS intent |
| `DNS_CLUSTER_ZONE_FILE` | Reviewed zone-file override; defaults to the tracked `burn-history/dns-records.zone` |
| `DNSCTL_AUDIT_LOG` | Protected append-only destination for redacted DNS plan/apply events |
| `TECHNITIUM_URL` | Direct management-command target URL; callers use reviewed fixed node endpoints or the local end of an SSH tunnel to a node's loopback API, not arbitrary agent input |
| `TECHNITIUM_TOKEN_FILE` | Protected role-specific token file for direct management commands |
| `TAILSCALE_OAUTH_CLIENT_ID_FILE` | Protected file containing the OAuth client ID; value must not be passed directly |
| `TAILSCALE_OAUTH_CLIENT_SECRET_FILE` | Protected file containing the OAuth secret; value must not be passed directly |
| `NETBIRD_API_TOKEN_FILE` | Protected file whose first line is the NetBird service user's personal access token; value must not be passed directly |
| `NETBIRD_MANAGEMENT_URL` | HTTPS origin of the NetBird management server for the API and `netbird up`; defaults to `https://api.netbird.io` |
| `NETBIRD_APPLIANCE_GROUP` | NetBird group assigned by each setup key; defaults to `dns-appliances` |
| `NETBIRD_SSH_USER` | Appliance SSH account used by `netbird-enroll`; defaults to `dns-operator` |
| `TECHNITIUM_CA_FILE` | Trusted CA bundle required for DNS apply through the agent path |
| `DEVICE_OS_AGENT_STATE_DIR` | Protected management-host runtime state directory for the gateway |
| `DEVICE_OS_AGENT_DNS_READER_TOKEN_FILE`, `DEVICE_OS_AGENT_DNS_PLANNER_TOKEN_FILE`, `DEVICE_OS_AGENT_DNS_APPLIER_TOKEN_FILE` | Fixed protected files for separate DNS authorities; token values are never environment variables |
| `DEVICE_OS_AGENT_DNS01_URL`, `DEVICE_OS_AGENT_DNS02_URL`, `DEVICE_OS_AGENT_DNS03_URL` | Administrator-fixed appliance URLs; callers cannot supply URLs through tools |
| `DEVICE_OS_AGENT_TECHNITIUM_CA_FILE` | Administrator-fixed trusted CA path forwarded as `TECHNITIUM_CA_FILE` for apply |
| `DEVICE_OS_AGENT_ALLOW_APPLY` | Management-host policy switch; the tool remains discoverable, but only literal `1` permits execution and all delegated gates still run |
| `DEVICE_OS_AGENT_TAILSCALE_COMMAND`, `DEVICE_OS_AGENT_NETBIRD_COMMAND` | Administrator-fixed absolute executable paths of the overlay CLIs for read-only tunnel status when they are not on `PATH`; never a tool argument |

The principal secret store remains intentionally implementation-neutral. All concrete paths in examples are operator-selected protected locations outside the checkout.
