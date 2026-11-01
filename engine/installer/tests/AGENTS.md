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
- Kernel-level checks (`firewall-namespace-simulation.sh`, and the kernel
  hook check in `image-builder-simulation.sh`) run only inside throwaway
  network or mount namespaces they create; they never change the host's
  ruleset, interfaces, or `/run`, and they fail instead of skipping when
  privileges are missing.
- A file the system writes (such as `/run/reboot-required`) is produced by
  running the installed writer, not created by the test, wherever the outcome
  depends on that writer existing.
- Add every new simulation to the "Run Installer simulations" step in
  `.github/workflows/ci.yml` and to the lists in `repository-contract.sh`.
- Passing simulation is not physical qualification. Test output must not claim
  firmware, Secure Boot, real USB, or power-loss coverage.

