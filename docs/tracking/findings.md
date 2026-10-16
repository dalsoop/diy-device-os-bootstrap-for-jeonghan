# Findings

## The first physical DNS pilot selected its installer USB

Under the original Ventoy boot path, the installer resolved `/dev/mapper/Ventoy` without following its sysfs slave and partition ancestry. The 30.8 GB SanDisk installer USB later showed the intended DNS target layout and an invalid EFI filesystem, proving that the removable installer became writable. This can destroy installation media and could select the wrong disk.

The source now resolves the physical parent, rejects unresolved ancestry, USB-backed and mounted candidates, and delays signature clearing until all checks pass. The finding remains open because source simulation cannot prove the repaired path on firmware and hardware. Rebuild the ISO and USB, pass VM BIOS/UEFI, and run one disposable physical `dns01` pilot before enabling another role.

## Revised macOS writer lacks physical qualification and an image builder

Two earlier physical writes copied selected ISO payloads correctly, but whole-device comparison differed after macOS mounted exFAT and changed filesystem metadata. The MBR-last writer now prevents mounting before body readback and passes isolated simulations.

The revised sequence has not been rerun on disposable hardware, and the repository cannot yet produce its required exact-size MBR raw image. This blocks calling macOS a complete build-and-burn path. Add a reproducible Linux/QEMU raw-image builder, then run the revised writer, filesystem checks, payload checks, and BIOS/UEFI boot on disposable media.

## Repository bundle symlinks can escape the checkout

When a configured repository bundle contains a symlink, current staging validates the textual relative path but ordinary copy behavior can follow the link outside the checkout. A malicious or accidental link could copy host files into generated media.

The current mitigation is to reject symlinks by review and repository policy. Closing the defect requires executable staging changes: resolve every source entry, prove it remains below the checkout, reject link escapes and race-prone replacements, and add file/tree escape fixtures before permitting symlinks.

## DNS apply is not bound to the reviewed plan

`dnsctl apply` checks literal confirmation, a caller-supplied commit equal to `HEAD`, and a clean tracked zone file. It does not consume an immutable `dnsctl plan` artifact, prove pull-request approval, or require unrelated tracked files to be clean. An operator can therefore apply state that was not the exact reviewed plan while still satisfying command checks.

Operational plan comparison remains required. Closing this needs a product decision on approval authority plus a signed or content-addressed plan format, expiry/state rules, and apply-time current-state comparison.

## Catalog schemas and executable validation can drift

The published JSON Schemas reject additional properties, while the jq verifier and Installer consumer independently implement their accepted subsets. A document can therefore pass one representation and fail another, weakening compatibility claims.

The repository currently coordinates manual updates and fixtures. Closing this requires executable validation work: generate one representation from another or run schema validation plus cross-consumer fixtures in CI.

## Vendor checksum provenance is not retained consistently

Catalog values are syntax-checked and downloads are verified against them, but the repository does not retain signed or independently captured authoritative checksum provenance for every release. If a URL and digest are changed together maliciously, successful download verification alone cannot establish authenticity.

Reviewers must verify each update through an authoritative vendor channel and preserve that evidence in the pull request. A durable provenance format, retention policy, and repository integration remain undecided.

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

## The image builder accepts more than one erase-enabled role

The rollout policy enables only the current pilot role, but `build-image` checks only that the enabled-role count is greater than zero. If two or three real inventory files are enabled, one ISO can authorize unattended installation on every matching machine even though operations require one-at-a-time expansion.

The current mitigation is operator review of all three ignored inventory files before every build. Closing the gap requires deciding whether later steady-state media may intentionally enable several roles; if not, the builder must require exactly one enabled role and add rejection coverage for multiple enabled inventories.
