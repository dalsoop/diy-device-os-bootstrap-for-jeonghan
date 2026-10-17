# Engineering Notes

## Installer media can masquerade as the internal target

**Symptom:** the installer reports EFI formatting trouble, or the USB later contains a 1 GiB EFI partition, Linux partition, and swap instead of the expected Ventoy layout.

**Cause:** Ventoy boots through `/dev/mapper/Ventoy`. Treating that mapper name as a complete device identity misses its sysfs slave and partition ancestry, so the physical installer USB can remain in the candidate set. CP850 conversion text from `mkfs.fat` is incidental; it does not explain target selection and does not prove a filesystem was created.

**Response:** stop immediately and preserve the media for inspection. Do not retry formatting. Rebuild from a revision that resolves mapper-to-partition-to-physical-parent ancestry, rejects unresolved ancestry and all USB-backed candidates, and clears stale signatures only after every identity check passes. Verify in VM BIOS/UEFI and on disposable physical `dns01` before enabling another node.

## macOS changes mounted exFAT metadata

**Symptom:** a full-disk `dd` appears successful, but a later whole-device `cmp` differs inside an exFAT partition.

**Cause:** Disk Arbitration mounts a newly visible filesystem and ordinary mount activity changes metadata before raw readback.

**Response:** use the MBR-last writer. It hides the first MiB, writes and verifies the image body, then writes and verifies the first MiB so filesystems cannot mount before their source bytes are checked. Afterward verify filesystem health and staged image checksums separately; a post-mount raw difference is neither proof of corruption nor proof of success.

## A valid raw image can be recorded under the wrong World media

**Symptom:** raw readback succeeds, but the generated World record names
`dns-install` while the physical USB contains the `inventory-capture` image.

**Cause:** the destructive command resolved the World's default media again and
did not bind that selection to the previously built raw image. Omitting
`DEVICE_OS_MEDIA=inventory-capture` therefore changed only the evidence inputs,
not the image bytes passed to the writer.

**Response:** reject the generation and retain a redacted failed event. Every
raw-image build emits an adjacent manifest containing the image hash, resolved
Catalog digest and identity, World slug, and media ID. The macOS writer rehashes
and compares all of them before live target inspection or any write.

## Capacity can remain indeterminate

**Symptom:** `world capacity` reports `PENDING` or null `fits` for a 16 GB target.

**Cause:** the DNS runtime artifact or matching manifest is absent, a selected public image is not present in the verified cache during offline calculation, or only a remote size estimate is available.

**Response:** run `world prepare` for selected public artifacts, then pass the exact DNS ISO and matching build manifest. Verify that no entry remains unknown or unverified before treating the result as a fit decision.

## Catalog availability is not World selection

**Symptom:** a valid Catalog entry does not appear in the generated USB.

**Cause:** the Catalog only makes the entry available. The selected World media definition controls the ordered payload; the Installer reference collection only supplies menu grouping and contributor fallback.

**Response:** change the World draft, rerun validate and plan, and inspect the selected entry list, DNS reserve, and capacity. Do not branch shared writer code or copy the Catalog item into local profiles.

## Declarative support has finite strategies

**Symptom:** adding an OS appears to require a product-specific branch in fetch or staging code.

**Cause:** the media introduces behavior outside the implemented `locked-download` or `runtime-artifact` source strategies, or outside `none` and `dns-appliance` profile adapters. The system is data-driven within those strategies, not a runtime plug-in loader.

**Response:** treat the change as a new behavior contract. Define accepted fields, failure behavior, cleanup, and security boundary; implement it once in the shared resolver; reject unknown values; and add success plus rejection fixtures. Do not disguise executable behavior as a Catalog-only edit.

## Catalog schema and executable validation can still drift

**Symptom:** a future Catalog document passes one validation path but fails another despite the tracked records and current valid and invalid fixtures passing CI.

**Cause:** CI now runs draft-2020-12 schema validation for tracked Catalog v2 records and explicit fixtures, but the schemas, jq verifier, and Installer consumer remain separate implementations. Cases not represented by current records or fixtures can still diverge.

**Response:** change schema, verifier, Installer consumer, and positive and rejection fixtures together. Treat CI schema validation as evidence for the exercised contract, not proof that independently maintained validators are equivalent for every possible document.

## A successful personal build is not redistribution approval

**Symptom:** a candidate has matching checksums, a complete SBOM, passing CI, or successful USB readback and is described as ready for public download.

**Cause:** build integrity and physical verification answer different questions from exact-artifact license, notice, corresponding-source, and trademark review. DNS images also combine multiple components whose reviews do not replace a review of the final ISO.

**Response:** keep the artifact personal-use-only. Public prebuilt distribution requires every exact artifact review, both DNS component and final gates, fulfilled digest-bound obligations, enabled repository policy, a successful prebuilt check, and protected `prebuilt-distribution` Environment approval by a human-only required reviewer. No lower evidence state promotes automatically.

## DNS installation intentionally fails before partitioning

**Symptom:** the unattended install stops without creating partitions.

**Cause:** disabled inventory, wrong DMI identity, NIC or disk mismatch, removable or mounted media, unresolved ancestry, zero or multiple internal disks, an active completed generation, or stale reinstall authorization is expected to fail closed.

**Response:** inspect from a trusted live environment and compare the observed machine with the captured local inventory. Recapture only after an intentional hardware change. Never edit a serial, UUID, MAC, or hash merely to make the gate pass.

## First boot reuses bootstrap credentials on retry

**Symptom:** a repeated first boot appears to reuse generated credentials.

**Cause:** credentials are generated once and retained until encrypted enrollment commits; regenerating them on every power-loss retry would leave the operator unable to know which credential reached the appliance.

**Response:** let first boot converge, verify the encrypted generation and public completion record, import it into the principal secret store, and rotate bootstrap credentials afterward.

## Tailscale connectivity can still violate appliance policy

**Symptom:** a node appears online but changes DNS behavior or routing.

**Cause:** a broad tailnet policy or enrollment preference can enable accepted DNS, advertised routes, exit-node behavior, or Tailscale SSH even though transport connectivity succeeds.

**Response:** treat enrollment as failed unless the expected hostname and `tag:dns-appliance` are present, `accept-dns=false`, no routes or exit node are advertised, and Tailscale SSH/Serve/Funnel are absent. A key revocation failure remains relevant until the one-hour key expires.

## A collected backup is not a recovery proof

**Symptom:** encrypted backup files exist, but recovery readiness is unknown.

**Cause:** collection proves transport and storage only; it does not prove age decryption, archive integrity, application import, or DNS behavior.

**Response:** periodically decrypt in an isolated environment, validate the archive, restore to an isolated Technitium instance, and query the canary over UDP and TCP. Keep this result separate from production restore authority.

## Network reachability depends on the router prefix

**Symptom:** the management host can reach `10.0.0.1` but not `10.0.5.1` through `10.0.5.3`.

**Cause:** the router may still treat the LAN as `10.0.0.0/24`; sharing the first octet does not make `10.0.5.0/24` directly reachable.

**Response:** preserve a wired recovery client and old router values, then configure a `10.0.0.0/16` LAN or an explicit route. Prove node reachability before changing DHCP DNS advertisement.
