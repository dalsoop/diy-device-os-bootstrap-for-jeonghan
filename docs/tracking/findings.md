# Findings

## The first physical DNS pilot selected its installer USB

Under the original Ventoy boot path, the installer resolved `/dev/mapper/Ventoy` without following its sysfs slave and partition ancestry. The 30.8 GB SanDisk installer USB later showed the intended DNS target layout and an invalid EFI filesystem, proving that the removable installer became writable. This can destroy installation media and could select the wrong disk.

The source now resolves the physical parent, rejects unresolved ancestry, USB-backed and mounted candidates, and delays signature clearing until all checks pass. The finding remains open because source simulation cannot prove the repaired path on firmware and hardware. Rebuild the ISO and USB, pass VM BIOS/UEFI, and run one disposable physical `dns01` pilot before enabling another role.

## Revised macOS image path still lacks filesystem and firmware qualification

Two earlier physical writes copied selected ISO payloads correctly, but whole-device comparison differed after macOS mounted exFAT and changed filesystem metadata. The MBR-last writer now prevents mounting before body readback and passes isolated simulations.

The repository now builds an exact-size MBR image through a privileged Debian
13 container whose loop device is isolated inside the Linux VM. It rejects
repository-bundle symlinks before assembly, and the macOS writer binds its exact
confirmation to device path, media name, USB serial, and byte size. An earlier
physical write completed full raw readback but its generation was rejected
because the command resolved `dns-install` while the raw image contained
`inventory-capture`; that mismatch exposed a missing provenance binding.

The builder and writer now bind image bytes to Catalog and World media through
an adjacent manifest. On 2026-10-17 the bound path wrote the
15,833,497,600-byte `inventory-capture` image, passed full MBR-last raw readback,
ejected the target, and emitted inspected generation
`20261017093655-jeonghan-home` with the correct media identity and no raw USB
serial. Mount-time filesystem checks, payload checks, and BIOS/UEFI boot remain
required before qualification.

## Inventory capture still requires manual terminal input

The current `inventory-capture` media boots a stock Debian Live image and
stages a capture script plus an English guide on the `DEVICE-OS` partition. The
operator must mount that partition and manually supply the role, address,
interface, and disk. This is non-destructive, but it invites transcription and
wrong-device mistakes and does not match the Korean-first World presentation.

The current USB remains usable as the conservative capture path. Closing the
usability gap requires an offline Korean capture UI that reads the roles and
addresses from the resolved World, detects candidate NICs and internal disks,
asks the operator only to choose the node and resolve genuine ambiguity, then
writes a schema-validated machine record and human-readable summary. The
capture image must remain incapable of erasing an internal disk.

## Destructive approval is exposed as a shell-looking token

The writer correctly binds authorization to the currently inspected device
path, media name, serial, and exact byte size, but `inspect-targets` displays the
binding as an `ERASE ...` line. An operator can reasonably paste that line into
a shell, where it fails as an unknown command, or mistake the internal token for
the whole burn command.

The exact target binding must remain. The operator-facing coordinator should
instead present a natural-language target summary and request natural-language
approval; after a fresh identity check it should construct and pass the exact
token internally. Direct low-level writer use may retain `--confirm` for tests
and expert recovery, but ordinary documentation and agent interaction should
not instruct the operator to execute the token.

## DNS apply is not bound to the reviewed plan

`dnsctl apply` checks literal confirmation, a caller-supplied commit equal to `HEAD`, and a clean tracked zone file. It does not consume an immutable `dnsctl plan` artifact, prove pull-request approval, or require unrelated tracked files to be clean. An operator can therefore apply state that was not the exact reviewed plan while still satisfying command checks.

Operational plan comparison remains required. Closing this needs a product decision on approval authority plus a signed or content-addressed plan format, expiry/state rules, and apply-time current-state comparison.

## Catalog schemas and executable validation can drift

CI now validates all tracked Catalog v2 records and explicit accepted and rejected fixtures against the published draft-2020-12 JSON Schemas. This closes the absence of executable schema checks for the exercised records and fixtures.

The finding remains open in narrower form because the schemas, jq verifier, and Installer consumer are independently maintained. An unrepresented document can still expose different semantics. Closing the remaining gap requires generation from one representation or systematic cross-consumer equivalence testing beyond the current fixture set.

## Vendor checksum provenance is not retained consistently

Catalog values are syntax-checked and downloads are verified against them, but the repository does not retain signed or independently captured authoritative checksum provenance for every release. If a URL and digest are changed together maliciously, successful download verification alone cannot establish authenticity.

Reviewers must verify each update through an authoritative vendor channel and preserve that evidence in the pull request. A durable provenance format, retention policy, and repository integration remain undecided.

The redistribution metadata and schema checks do not close this finding. They bind a human review to an exact digest after evidence exists; they do not prove that the digest itself came from an independent authoritative vendor channel.

## Human-only prebuilt Environment is not verified

Repository policy names the protected GitHub Environment
`prebuilt-distribution` and requires a human-only required reviewer in addition
to a successful prebuilt-release check. No publishing job exists, generated
artifact distribution remains disabled, and repository source cannot prove the
external Environment settings or reviewer identity.

Before any prebuilt workflow is proposed, the repository owner must create or
inspect that Environment, confirm that agents cannot approve it, capture the
settings review outside generated media, and retain the independent
prebuilt-release gate. Until then the repository is source-only and must not be
described as ready to publish generated media.

## Management operations lack one complete audit trail

DNS plan/apply records only some completed outcomes, while cluster bootstrap, Tailscale enrollment, backup collection, reinstall authorization, restore, and router changes primarily leave console output and resulting state. Failures before command-specific logging may leave no durable event.

This limits incident reconstruction and proof of who authorized a sensitive operation. Operators must capture protected session records for now. Closing it needs a shared redacted event schema, append-only protected sink, failure-path coverage, retention policy, and operator identity source.

## Live agent path remains unverified

The MCP gateway passes isolated tool and policy simulations, but no evidence yet proves the dedicated account, Tailscale ACL, forced SSH command, protected credential paths, trusted Technitium CA, and three live DNS nodes operate together. A source pass cannot establish remote identity or network policy.

Provision the management-host account and tailnet policy only after node installation, then test read-only tools first, verify forbidden tools are absent, and enable one canary apply only after trusted TLS and rollback are proven.

## Tailscale enrollment does not inspect Serve or Funnel state

The enrollment command verifies running state, hostname, tag, address, accepted DNS, routes, exit-node settings, and Tailscale SSH preferences. It does not query the separate Serve/Funnel configuration, so a node can pass the implemented preference gate without source evidence that those listeners are absent.

Current deployment acceptance therefore requires a separate operator check for empty Serve and Funnel status. Closing the gap requires a stable machine-readable Tailscale status interface, failure fixtures, and a compatibility decision across pinned Tailscale versions.

## Agent results are clipped but not content-redacted

The gateway limits stdout and stderr to 64 KiB but returns delegated text without scanning for tokens, passwords, or other credential patterns. A delegated command regression could therefore expose a secret through MCP even though current commands are designed to keep credentials out of output.

The current mitigation is the fixed command allowlist, protected credential-file paths, explicit environment allowlist, and command-level output discipline. Closing the gap requires central content filtering with false-positive rules plus fixtures proving that complete and truncated credential-like output is blocked without echoing the value.

## Restore disables TLS certificate verification

`restore-node` always invokes the selected Technitium HTTPS origin with certificate verification disabled while sending a bearer token and decrypted backup. Exact URL confirmation prevents accidental target substitution by the operator but does not authenticate that endpoint.

The command is restricted to isolated restore drills and is not production-qualified. Closing this requires a trusted-CA or pinned-fingerprint input, endpoint validation, failure tests for an untrusted certificate, and a successful isolated restore with verification enabled.
