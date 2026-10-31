# DNS Appliance Status Monitor

This read-only Korean status page shows whether all three DNS appliances answer
after installation and whether their guarded nightly reboot is being skipped. It
needs no external packages, account, or cloud service and does not change the
target nodes.

Run it on Pop!_OS or another Linux system with Python 3:

```sh
./start
```

Open <http://127.0.0.1:8080>. Every ten seconds it checks DNS over UDP and TCP,
Cockpit on 9090, Technitium management on 53443, and node exporter on 9100.
The server binds to localhost by default and is not exposed to other devices.

## Reaching nodes by name

Each node in `config.json` has `name`, `host`, and `query`. `host` is a DNS name
or an IPv4 address; the bundled config uses the role names `dns01`, `dns02`, and
`dns03`. Which network path a name takes is decided by the management host's
resolver, so the same config works over the LAN, Tailscale, or NetBird.

The management host must resolve the role names without depending on the DNS
cluster itself: use a hosts file entry or an overlay's own DNS (Tailscale
MagicDNS or NetBird DNS). Otherwise the monitor cannot reach the nodes exactly
when the cluster fails. A name that does not resolve is shown per node as a
name-resolution failure, separately from the service probes.

## Reboot state

The page also reads `http://<host>:9100/metrics` with one GET request and shows,
per node, whether a reboot is pending, how many consecutive nightly reboots were
skipped because a peer did not answer, and the last skip time in UTC. A node
with one or more consecutive skips is highlighted. Unknown values appear when
the node exporter is unreachable or the metrics are absent.

`./start --check-once` prints the same results as JSON: for each node `name`,
`host`, `resolution` (`ok`, `detail`), `checks`, and
`reboot` (`pending`, `skipped_consecutive`, `last_skip`; each `null` when
unknown, and `last_skip` also `null` when the node never skipped).

To expose the page on the LAN, bind explicitly to a management-host address, for
example `./start --listen 10.77.0.X`, only after adding suitable firewall and
access controls.
