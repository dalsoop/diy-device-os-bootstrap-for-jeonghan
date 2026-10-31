# Test Module

These tests prove source contracts and fail-closed behavior without touching
real hardware.

- Never open a real block device, contact production DNS nodes, use live
  credentials, or depend on a mounted installer USB.
- Build fixtures under a temporary directory and remove them with traps.
- Every destructive success case needs counter-cases for wrong identity,
  ambiguity, removable media, installer media, stale authorization, and malformed
  input as applicable.
- New source kinds and profile adapters require success, unknown-value, path,
  digest, and staging rejection coverage.
- Assert observable contracts and exit status; do not accept a warning when the
  safe behavior is failure.
- Fake every network client (`curl`, `ssh`, `dig`, overlay CLIs) and every
  state-changing command (`systemctl`, `logger`); never reach a real overlay
  control plane, router, or Debian mirror. Prove that tokens and keys never
  reach arguments or output.
- Kernel-level checks (`firewall-namespace-simulation.sh`) run only inside
  throwaway network namespaces they create and delete; they never change the
  host's ruleset or interfaces, and they fail instead of skipping when
  privileges are missing.
- Add every new simulation to the "Run Installer simulations" step in
  `.github/workflows/ci.yml` and to the lists in `repository-contract.sh`.
- Passing simulation is not physical qualification. Test output must not claim
  firmware, Secure Boot, real USB, or power-loss coverage.

