#!/usr/bin/env python3
"""Dependency-free, read-only status page for the three DNS appliances."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import html
import http.client
import ipaddress
import json
import math
import re
import secrets
import socket
import struct
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


PORTS = (("Cockpit", 9090), ("Technitium", 53443), ("Metrics", 9100))
METRICS_PORT = 9100
METRICS_LIMIT = 4 * 1024 * 1024
REBOOT_METRICS = (
    "dns_appliance_reboot_pending",
    "dns_appliance_reboot_skipped_consecutive",
    "dns_appliance_reboot_last_skip_timestamp_seconds",
)
EMPTY_REBOOT = {"pending": None, "skipped_consecutive": None, "last_skip": None}
NODE_FIELDS = ("name", "host", "query")
HOST_LABEL = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


def dns_name(name: str) -> bytes:
    labels = name.rstrip(".").split(".")
    encoded = bytearray()
    for label in labels:
        wire = label.encode("idna")
        if not wire or len(wire) > 63:
            raise ValueError(f"invalid DNS label: {label!r}")
        encoded.append(len(wire))
        encoded.extend(wire)
    encoded.append(0)
    return bytes(encoded)


def dns_packet(query: str, identifier: int) -> bytes:
    return struct.pack("!HHHHHH", identifier, 0x0100, 1, 0, 0, 0) + dns_name(query) + struct.pack("!HH", 1, 1)


def valid_dns_response(payload: bytes, identifier: int) -> bool:
    if len(payload) < 12:
        return False
    response_id, flags, _, answers, _, _ = struct.unpack("!HHHHHH", payload[:12])
    return response_id == identifier and flags & 0x8000 != 0 and flags & 0x000F == 0 and answers > 0


def check_dns(address: str, query: str, transport: str, timeout: float = 1.5) -> tuple[bool, str]:
    identifier = secrets.randbelow(65536)
    packet = dns_packet(query, identifier)
    started = time.monotonic()
    try:
        if transport == "udp":
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(timeout)
                client.sendto(packet, (address, 53))
                response, _ = client.recvfrom(4096)
        else:
            with socket.create_connection((address, 53), timeout=timeout) as client:
                client.sendall(struct.pack("!H", len(packet)) + packet)
                size_data = client.recv(2)
                if len(size_data) != 2:
                    raise OSError("short TCP DNS length")
                expected = struct.unpack("!H", size_data)[0]
                chunks = bytearray()
                while len(chunks) < expected:
                    chunk = client.recv(expected - len(chunks))
                    if not chunk:
                        raise OSError("short TCP DNS response")
                    chunks.extend(chunk)
                response = bytes(chunks)
        elapsed = round((time.monotonic() - started) * 1000)
        return valid_dns_response(response, identifier), f"{elapsed} ms"
    except (OSError, ValueError) as error:
        return False, str(error)


def check_tcp(address: str, port: int, timeout: float = 1.5) -> tuple[bool, str]:
    started = time.monotonic()
    try:
        with socket.create_connection((address, port), timeout=timeout):
            elapsed = round((time.monotonic() - started) * 1000)
            return True, f"{elapsed} ms"
    except OSError as error:
        return False, str(error)


def resolve_host(host: str) -> tuple[bool, str]:
    """Resolve a configured host to one IPv4 address through the system resolver."""
    try:
        return True, str(ipaddress.IPv4Address(host))
    except ipaddress.AddressValueError:
        pass
    try:
        infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    except (OSError, UnicodeError) as error:
        return False, str(error) or "name did not resolve"
    for info in infos:
        return True, str(info[4][0])
    return False, "name has no IPv4 address"


def parse_metrics(text: str) -> dict[str, float]:
    """Return the first unlabelled-or-labelled sample of each reboot metric."""
    samples: dict[str, float] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) < 2:
            continue
        name = fields[0].split("{", 1)[0]
        if name not in REBOOT_METRICS or name in samples:
            continue
        try:
            value = float(fields[1])
        except ValueError:
            continue
        if math.isfinite(value):
            samples[name] = value
    return samples


def reboot_state(samples: dict[str, float]) -> dict[str, object]:
    pending = samples.get("dns_appliance_reboot_pending")
    skipped = samples.get("dns_appliance_reboot_skipped_consecutive")
    last_skip = samples.get("dns_appliance_reboot_last_skip_timestamp_seconds")
    state: dict[str, object] = dict(EMPTY_REBOOT)
    if pending in (0.0, 1.0):
        state["pending"] = pending == 1.0
    if skipped is not None and skipped >= 0 and skipped.is_integer():
        state["skipped_consecutive"] = int(skipped)
    if last_skip is not None and last_skip > 0:
        try:
            moment = datetime.datetime.fromtimestamp(last_skip, tz=datetime.timezone.utc)
            state["last_skip"] = moment.strftime("%Y-%m-%dT%H:%M:%SZ")
        except (OverflowError, OSError, ValueError):
            pass
    return state


def check_reboot(address: str, host: str, timeout: float = 1.5) -> dict[str, object]:
    """Read the reboot-guard metrics from node exporter with one GET request."""
    connection = http.client.HTTPConnection(address, METRICS_PORT, timeout=timeout)
    try:
        connection.request("GET", "/metrics", headers={"Host": f"{host}:{METRICS_PORT}"})
        response = connection.getresponse()
        if response.status != 200:
            return dict(EMPTY_REBOOT)
        body = response.read(METRICS_LIMIT + 1)
        if len(body) > METRICS_LIMIT:
            return dict(EMPTY_REBOOT)
        return reboot_state(parse_metrics(body.decode("utf-8", "replace")))
    except (OSError, http.client.HTTPException):
        return dict(EMPTY_REBOOT)
    finally:
        connection.close()


def check_node(node: dict[str, str]) -> dict[str, object]:
    resolved, detail = resolve_host(node["host"])
    result: dict[str, object] = {
        "name": node["name"],
        "host": node["host"],
        "resolution": {"ok": resolved, "detail": detail},
    }
    services = [f"DNS {transport.upper()}" for transport in ("udp", "tcp")] + [service for service, _ in PORTS]
    if not resolved:
        not_probed = "not probed: host name did not resolve"
        result["checks"] = [{"service": service, "ok": False, "detail": not_probed} for service in services]
        result["reboot"] = dict(EMPTY_REBOOT)
        return result
    address = detail
    checks = []
    for transport in ("udp", "tcp"):
        ok, check_detail = check_dns(address, node["query"], transport)
        checks.append({"service": f"DNS {transport.upper()}", "ok": ok, "detail": check_detail})
    for service, port in PORTS:
        ok, check_detail = check_tcp(address, port)
        checks.append({"service": service, "ok": ok, "detail": check_detail})
    result["checks"] = checks
    result["reboot"] = check_reboot(address, node["host"])
    return result


def run_checks(config: dict[str, object]) -> list[dict[str, object]]:
    nodes = config["nodes"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(nodes)) as pool:
        return list(pool.map(check_node, nodes))


def render_node(node: dict[str, object]) -> str:
    resolution = node["resolution"]
    if resolution["ok"]:
        resolved = f"<td class='ok'>{html.escape(resolution['detail'])}</td>"
    else:
        resolved = f"<td class='bad'>실패: {html.escape(resolution['detail'])}</td>"
    reboot = node["reboot"]
    pending = {True: "예", False: "아니오", None: "알 수 없음"}[reboot["pending"]]
    skipped = reboot["skipped_consecutive"]
    skipped_text = "알 수 없음" if skipped is None else f"{skipped}회"
    last_skip = reboot["last_skip"] or "-"
    row = "<tr class='warn'>" if skipped is not None and skipped >= 1 else "<tr>"
    return (
        f"{row}<td>{html.escape(node['name'])}</td>"
        f"<td>{html.escape(node['host'])}</td>"
        f"{resolved}<td>{pending}</td><td>{skipped_text}</td>"
        f"<td>{html.escape(last_skip)}</td></tr>"
    )


def render(config: dict[str, object], results: list[dict[str, object]]) -> bytes:
    nodes = [render_node(node) for node in results]
    rows = []
    for node in results:
        for check in node["checks"]:
            state = "정상" if check["ok"] else "실패"
            css = "ok" if check["ok"] else "bad"
            rows.append(
                "<tr>"
                f"<td>{html.escape(node['name'])}</td>"
                f"<td>{html.escape(node['host'])}</td>"
                f"<td>{html.escape(check['service'])}</td>"
                f"<td class='{css}'>{state}</td>"
                f"<td>{html.escape(check['detail'])}</td>"
                "</tr>"
            )
    refresh = int(config.get("refresh_seconds", 10))
    page = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta http-equiv="refresh" content="{refresh}">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DNS 장비 상태판</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;background:#111827;color:#f9fafb}}table{{width:100%;border-collapse:collapse;background:#1f2937;margin-bottom:1.5rem}}th,td{{padding:.7rem;border-bottom:1px solid #374151;text-align:left}}.ok{{color:#34d399;font-weight:700}}.bad{{color:#fb7185;font-weight:700}}tr.warn td{{background:#78350f}}small{{color:#9ca3af}}</style>
</head><body><h1>DNS 장비 상태판</h1>
<p>설치 후 핵심 서비스가 응답하는지 읽기 전용으로 확인합니다. 재부팅이 연속으로 건너뛰어진 장비는 강조됩니다.</p>
<table><thead><tr><th>장비</th><th>호스트</th><th>이름 해석</th><th>재부팅 대기</th><th>연속 건너뜀</th><th>마지막 건너뜀 (UTC)</th></tr></thead>
<tbody>{''.join(nodes)}</tbody></table>
<table><thead><tr><th>장비</th><th>호스트</th><th>서비스</th><th>상태</th><th>응답</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table>
<p><small>{refresh}초마다 자동 갱신 · {time.strftime('%Y-%m-%d %H:%M:%S')}</small></p></body></html>"""
    return page.encode("utf-8")


def validate_host(host: object) -> None:
    """Accept an IPv4 address or a DNS name made of valid letter-digit-hyphen labels."""
    if not isinstance(host, str) or not host:
        raise ValueError("node host must be a non-empty string")
    try:
        ipaddress.IPv4Address(host)
        return
    except ipaddress.AddressValueError:
        pass
    name = host[:-1] if host.endswith(".") else host
    labels = name.split(".")
    if len(name) > 253 or not all(HOST_LABEL.match(label) for label in labels):
        raise ValueError(f"node host must be an IPv4 address or a DNS name: {host!r}")
    if all(label.isdigit() for label in labels):
        raise ValueError(f"node host looks like an incomplete IPv4 address: {host!r}")


def load_config(path: Path) -> dict[str, object]:
    config = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("config must be a JSON object")
    nodes = config.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError("config must contain at least one node")
    for node in nodes:
        if not isinstance(node, dict):
            raise ValueError("each node must be a JSON object")
        if "address" in node:
            raise ValueError("node field address is not accepted; use host (a DNS name or IPv4 address)")
        if set(node) != set(NODE_FIELDS):
            raise ValueError("each node requires exactly name, host, and query")
        if not isinstance(node["name"], str) or not node["name"]:
            raise ValueError("node name must be a non-empty string")
        validate_host(node["host"])
        if not isinstance(node["query"], str):
            raise ValueError("node query must be a DNS name")
        dns_name(node["query"])
    return config


def main() -> None:
    parser = argparse.ArgumentParser(description="세 DNS 장비의 설치 후 상태를 확인합니다.")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--check-once", action="store_true")
    args = parser.parse_args()
    try:
        config = load_config(args.config)
    except (OSError, ValueError, UnicodeError) as error:
        print(f"DNS 장비 상태판: 설정 오류 ({args.config}): {error}", file=sys.stderr)
        sys.exit(2)
    if args.check_once:
        print(json.dumps(run_checks(config), ensure_ascii=False, indent=2))
        return

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path not in ("/", "/index.html"):
                self.send_error(404)
                return
            body = render(config, run_checks(config))
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            return

    server = ThreadingHTTPServer((args.listen, args.port), Handler)
    print(f"DNS 장비 상태판: http://{args.listen}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
