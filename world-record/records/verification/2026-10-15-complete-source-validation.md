# Complete source validation — 2026-10-15

Commit: recorded by CI and pull request after this evidence file is committed.

## Passed locally

- Shell syntax for every executable under `engine/installer/dns-image/`,
  `engine/installer/management/`, `engine/installer/build/` and
  `engine/installer/tests/`.
- ShellCheck with sourced-file following enabled.
- `engine/installer/tests/install-gate-simulation.sh`: 12/12 passed.
- `engine/installer/tests/management-simulation.sh`: 4/4 passed.
- `engine/installer/tests/repository-contract.sh`: passed.
- `engine/installer/build/verify-locks`: passed.
- JSON parsing of `engine/installer/schemas/enrollment-record.schema.json`: passed.
- YAML parsing of both GitHub Actions workflows: passed.
- `git diff --check`: passed.
- Repository secret-pattern scan: no private-key or literal secret finding.

## Not proved by this run

- No ISO was built because this run used the operator workstation, not the
  designated amd64 Debian 13 build host.
- No systemd unit was executed or verified by `systemd-analyze` on the
  operator workstation.
- No physical USB was written.
- No BIOS, UEFI, Secure Boot, power-loss, HP hardware, Cockpit login,
  Technitium cluster, backup/restore, or router DHCP test was performed.

The release and physical pilot gates in `engine/installer/docs/verification.md`
remain open.
