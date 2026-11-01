#!/bin/bash
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# Runs the status monitor's --check-once against a local fake node-exporter on
# 127.0.0.1:9100, a role-style DNS name that resolves through the hosts file,
# an unused loopback address, and an unresolvable .invalid name. It also checks
# configuration rejection and HTML rendering. No real node is contacted.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
monitor=$repo_root/management/dns-appliance-status-monitor
temporary=$(mktemp -d "${TMPDIR:-/tmp}/dns-status-monitor-test.XXXXXX")
server_pid=

cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$temporary"
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL $*" >&2
    exit 1
}

export PYTHONDONTWRITEBYTECODE=1

cat > "$temporary/metrics-server.py" <<'EOF'
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

body_path = Path(sys.argv[1])
request_log = Path(sys.argv[2])
ready = Path(sys.argv[3])


class Handler(BaseHTTPRequestHandler):
    def log_request(self, code="-", size="-"):
        with request_log.open("a", encoding="utf-8") as log:
            log.write(f"{self.command} {self.path}\n")

    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        body = body_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = ThreadingHTTPServer(("127.0.0.1", 9100), Handler)
ready.write_text("ready\n", encoding="utf-8")
server.serve_forever()
EOF

cat > "$temporary/metrics-skipped" <<'EOF'
# HELP node_load1 1m load average.
# TYPE node_load1 gauge
node_load1 0.25
# HELP dns_appliance_reboot_pending Whether a reboot is required.
# TYPE dns_appliance_reboot_pending gauge
dns_appliance_reboot_pending 1
# HELP dns_appliance_reboot_skipped_consecutive Consecutive guarded reboot skips.
# TYPE dns_appliance_reboot_skipped_consecutive gauge
dns_appliance_reboot_skipped_consecutive 2
# HELP dns_appliance_reboot_last_skip_timestamp_seconds Time of the last skipped reboot.
# TYPE dns_appliance_reboot_last_skip_timestamp_seconds gauge
dns_appliance_reboot_last_skip_timestamp_seconds 1.7e+09
node_textfile_scrape_error 0
EOF

cat > "$temporary/metrics-clear" <<'EOF'
dns_appliance_reboot_pending 0
dns_appliance_reboot_skipped_consecutive 0
dns_appliance_reboot_last_skip_timestamp_seconds 0
EOF

cat > "$temporary/metrics-absent" <<'EOF'
# HELP node_load1 1m load average.
# TYPE node_load1 gauge
node_load1 0.25
EOF

cp "$temporary/metrics-skipped" "$temporary/metrics-body"
python3 "$temporary/metrics-server.py" "$temporary/metrics-body" \
    "$temporary/requests.log" "$temporary/ready" &
server_pid=$!
for _ in $(seq 1 50); do
    [ -e "$temporary/ready" ] && break
    kill -0 "$server_pid" 2>/dev/null || fail "fake metrics server did not start on 127.0.0.1:9100"
    sleep 0.1
done
[ -e "$temporary/ready" ] || fail "fake metrics server did not become ready"

cat > "$temporary/config.json" <<'EOF'
{
  "refresh_seconds": 10,
  "nodes": [
    { "name": "dns01", "host": "localhost", "query": "dns01.home.arpa" },
    { "name": "dns02", "host": "127.0.0.2", "query": "dns02.home.arpa" },
    { "name": "dns03", "host": "dns03.invalid", "query": "dns03.home.arpa" }
  ]
}
EOF

check_once() {
    python3 "$monitor/server.py" --config "$temporary/config.json" --check-once > "$temporary/$1.json" \
        || fail "--check-once exited non-zero for the $1 metrics"
}

check_once skipped
cp "$temporary/metrics-clear" "$temporary/metrics-body"
check_once clear
cp "$temporary/metrics-absent" "$temporary/metrics-body"
check_once absent

cat > "$temporary/assert.py" <<'EOF'
import json
import sys
from pathlib import Path

temporary = Path(sys.argv[1])
monitor = Path(sys.argv[2])
probes = ["DNS UDP", "DNS TCP", "Cockpit", "Technitium", "Metrics"]
nulls = {"pending": None, "skipped_consecutive": None, "last_skip": None}


def fail(message):
    print(f"FAIL {message}", file=sys.stderr)
    sys.exit(1)


def load(label):
    results = json.loads((temporary / f"{label}.json").read_text(encoding="utf-8"))
    nodes = {node["name"]: node for node in results}
    if list(nodes) != ["dns01", "dns02", "dns03"]:
        fail(f"{label}: unexpected node list {list(nodes)}")
    for name, node in nodes.items():
        for key in ("name", "host", "checks", "reboot", "resolution"):
            if key not in node:
                fail(f"{label}: {name} lacks {key}")
        if "address" in node:
            fail(f"{label}: {name} still reports an address field")
        if [check["service"] for check in node["checks"]] != probes:
            fail(f"{label}: {name} probe set changed: {node['checks']}")
    return nodes


skipped = load("skipped")
dns01 = skipped["dns01"]
if dns01["host"] != "localhost":
    fail(f"dns01 host not echoed: {dns01['host']}")
if dns01["resolution"] != {"ok": True, "detail": "127.0.0.1"}:
    fail(f"dns01 did not resolve through the hosts file: {dns01['resolution']}")
expected = {"pending": True, "skipped_consecutive": 2, "last_skip": "2023-11-14T22:13:20Z"}
if dns01["reboot"] != expected:
    fail(f"dns01 reboot fields not parsed: {dns01['reboot']}")
metrics_probe = next(check for check in dns01["checks"] if check["service"] == "Metrics")
if not metrics_probe["ok"]:
    fail(f"dns01 Metrics probe failed against the fake exporter: {metrics_probe}")

dns02 = skipped["dns02"]
if dns02["host"] != "127.0.0.2" or dns02["resolution"] != {"ok": True, "detail": "127.0.0.2"}:
    fail(f"dns02 IPv4 host not accepted as-is: {dns02}")
if dns02["reboot"] != nulls:
    fail(f"dns02 reboot fields must be null when unreachable: {dns02['reboot']}")

dns03 = skipped["dns03"]
if dns03["resolution"]["ok"] is not False or not dns03["resolution"]["detail"]:
    fail(f"dns03 name-resolution failure not reported: {dns03['resolution']}")
if dns03["reboot"] != nulls:
    fail(f"dns03 reboot fields must be null without resolution: {dns03['reboot']}")
if any(check["ok"] for check in dns03["checks"]):
    fail(f"dns03 probes reported success without resolution: {dns03['checks']}")

clear = load("clear")
if clear["dns01"]["reboot"] != {"pending": False, "skipped_consecutive": 0, "last_skip": None}:
    fail(f"a zero last-skip timestamp must read as never skipped: {clear['dns01']['reboot']}")

absent = load("absent")
if absent["dns01"]["reboot"] != nulls:
    fail(f"absent reboot metrics must read as null: {absent['dns01']['reboot']}")

sys.path.insert(0, str(monitor))
import server  # noqa: E402

page = server.render({"refresh_seconds": 10}, list(skipped.values())).decode("utf-8")
for text in ("재부팅", "연속", "이름 해석", "localhost", "dns03.invalid", "2023-11-14T22:13:20Z"):
    if text not in page:
        fail(f"HTML page lacks {text!r}")
if page.count("class='warn'") != 1:
    fail("HTML page must highlight exactly the node with skipped reboots")
clear_page = server.render({"refresh_seconds": 10}, list(clear.values())).decode("utf-8")
if "class='warn'" in clear_page:
    fail("HTML page highlighted a node without skipped reboots")

bundled = server.load_config(monitor / "config.json")
if [node["host"] for node in bundled["nodes"]] != ["dns01", "dns02", "dns03"]:
    fail("bundled config must reach the nodes by role name")
EOF
python3 "$temporary/assert.py" "$temporary" "$monitor"

while IFS= read -r request; do
    [ "$request" = "GET /metrics" ] || fail "monitor sent a request other than GET /metrics: $request"
done < "$temporary/requests.log"
[ -s "$temporary/requests.log" ] || fail "monitor never fetched /metrics"

reject() {
    label=$1
    printf '{"nodes": [%s]}\n' "$2" > "$temporary/reject.json"
    if python3 "$monitor/server.py" --config "$temporary/reject.json" --check-once \
        > "$temporary/reject.out" 2> "$temporary/reject.err"; then
        fail "config with $label was accepted"
    fi
    if grep -q Traceback "$temporary/reject.err"; then
        fail "config with $label crashed instead of reporting an error"
    fi
    [ -s "$temporary/reject.err" ] || fail "config with $label was rejected without a message"
}

reject "an address field" '{"name": "dns01", "address": "10.77.5.1", "query": "dns01.home.arpa"}'
grep -q address "$temporary/reject.err" || fail "address rejection does not name the field"
reject "both address and host" \
    '{"name": "dns01", "host": "dns01", "address": "10.77.5.1", "query": "dns01.home.arpa"}'
reject "no host" '{"name": "dns01", "query": "dns01.home.arpa"}'
reject "an invalid host label" '{"name": "dns01", "host": "dns_01", "query": "dns01.home.arpa"}'
reject "an IPv6 host" '{"name": "dns01", "host": "2001:db8::1", "query": "dns01.home.arpa"}'
reject "a partial IPv4 host" '{"name": "dns01", "host": "10.77.5", "query": "dns01.home.arpa"}'
reject "an empty name" '{"name": "", "host": "dns01", "query": "dns01.home.arpa"}'

echo "RESULT status monitor simulation passed"
