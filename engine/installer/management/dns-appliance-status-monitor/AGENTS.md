# DNS Appliance Status Monitor

This nested module serves a local, read-only HTML status page and probes the
three DNS appliances by their configured host.

- Keep the default listener on `127.0.0.1`. A non-loopback bind requires an
  explicit address plus separately managed firewall and access controls.
- Nodes are configured as `name`, `host`, and `query`. `host` is a DNS name or
  an IPv4 address and resolves through the management host's resolver; the
  `address` field is rejected. The documented rule is that the management host
  resolves role names without depending on the DNS cluster (hosts file or an
  overlay's own DNS).
- Report a host that does not resolve as a per-node name-resolution failure,
  never as a crash or as a probe success.
- Probes may read DNS over UDP/TCP, test TCP reachability for Cockpit,
  Technitium, and metrics, and issue one bounded GET for
  `http://<host>:9100/metrics` to read the reboot-guard metrics. They must not
  authenticate, mutate nodes, or expose a write endpoint.
- Keep the runtime dependency-free beyond Python 3 so the copied USB bundle can
  run without installation or Internet access.
- Treat probe failure or skipped reboots as status information, not permission
  to repair, reboot, or change a node.
- Verify configuration parsing, loopback binding, expected probe labels,
  reboot-field parsing, and failure rendering when changing the HTTP surface;
  `engine/installer/tests/status-monitor-simulation.sh` covers them.
