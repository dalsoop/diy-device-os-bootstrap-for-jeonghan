#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
"""Isolated contract simulation for the management-host MCP gateway."""

from __future__ import annotations

import asyncio
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import stat
import tempfile

from mcp import Client
from mcp.server.mcpserver.exceptions import ToolError


AGENT_ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "device_os_agent_server", AGENT_ROOT / "server.py"
)
assert SPEC and SPEC.loader
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


def executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def expect_tool_error(action, text: str) -> None:
    try:
        action()
    except ToolError as error:
        assert text in str(error), str(error)
    else:
        raise AssertionError(f"expected ToolError containing: {text}")


TAILSCALE_STATUS = {
    "BackendState": "Running",
    "Self": {"HostName": "management"},
    "Peer": {
        "a": {"HostName": "dns01", "Online": True, "TailscaleIPs": ["100.64.0.1"]},
        "b": {
            "HostName": "dns02",
            "Online": False,
            "TailscaleIPs": ["100.64.0.2", "fd7a:115c:a1e0::2"],
        },
        "c": {"HostName": "unrelated", "Online": True, "TailscaleIPs": ["100.64.0.9"]},
    },
}
NETBIRD_STATUS = {
    "peers": {
        "total": 6,
        "connected": 4,
        "details": [
            {
                "fqdn": "dns01.netbird.cloud",
                "netbirdIp": "100.92.0.11",
                "status": "Connected",
            },
            {
                "fqdn": "dns02.netbird.cloud",
                "netbirdIp": "100.92.0.12",
                "netbirdIpv6": "fd00:4e42::12",
                "status": "Idle",
            },
            {
                "fqdn": "dns03.netbird.cloud.",
                "netbirdIp": "100.92.0.13",
                "status": "Connecting",
            },
            {
                "fqdn": "dns01-old.netbird.cloud",
                "netbirdIp": "100.92.0.21",
                "status": "Connected",
            },
            {
                "fqdn": "workstation.netbird.cloud",
                "netbirdIp": "100.92.0.31",
                "status": "Connected",
            },
            {"fqdn": "", "netbirdIp": "100.92.0.41", "status": "Connected"},
        ],
    },
    "management": {"url": "https://netbird.example:443", "connected": True, "error": ""},
    "netbirdIp": "100.92.0.1/16",
    "fqdn": "management.netbird.cloud",
    "daemonStatus": "Connected",
}


def printing(path: Path, output: str, require_shlvl: bool = False) -> None:
    """Write a builtin-only fake CLI so a restricted PATH still runs it."""
    executable(
        path,
        "#!/bin/sh\n"
        "set -eu\n"
        + ('[ -n "${SHLVL:-}" ]\n' if require_shlvl else "")
        + '[ "$*" = "status --json" ]\n'
        + f"printf '%s\\n' {shlex.quote(output)}\n",
    )


def simulate_tunnel_status(root: Path) -> None:
    fakes = root / "overlay-fakes"
    bundle_tailscale = fakes / "bundle" / "tailscale"
    printing(bundle_tailscale, json.dumps(TAILSCALE_STATUS), require_shlvl=True)
    printing(fakes / "path-tailscale" / "tailscale", json.dumps(TAILSCALE_STATUS))
    printing(fakes / "path-netbird" / "netbird", json.dumps(NETBIRD_STATUS))
    printing(fakes / "fixed" / "netbird", json.dumps(NETBIRD_STATUS))
    printing(fakes / "invalid" / "netbird", "netbird is not running")
    printing(fakes / "invalid" / "netbird-shape", json.dumps({"peers": []}))
    printing(fakes / "invalid" / "tailscale", "not json")
    not_executable = fakes / "not-executable" / "netbird"
    not_executable.parent.mkdir(parents=True)
    not_executable.write_text("#!/bin/sh\n", encoding="utf-8")
    empty_path = fakes / "empty"
    empty_path.mkdir()

    saved_path = os.environ["PATH"]

    def configure(
        path: Path, tailscale: Path | str | None, netbird: Path | str | None
    ) -> None:
        os.environ["PATH"] = str(path)
        for name, value in (
            ("DEVICE_OS_AGENT_TAILSCALE_COMMAND", tailscale),
            ("DEVICE_OS_AGENT_NETBIRD_COMMAND", netbird),
        ):
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = str(value)

    expected_tailscale = {
        "available": True,
        "backend_state": "Running",
        "management_host": {"hostname": "management"},
        "dns_nodes": {
            "dns01": {"online": True, "addresses": ["100.64.0.1"]},
            "dns02": {
                "online": False,
                "addresses": ["100.64.0.2", "fd7a:115c:a1e0::2"],
            },
        },
    }
    expected_netbird = {
        "available": True,
        "management_connected": True,
        "management_host": {"hostname": "management"},
        "dns_nodes": {
            "dns01": {"online": True, "addresses": ["100.92.0.11"]},
            "dns02": {
                "online": False,
                "addresses": ["100.92.0.12", "fd00:4e42::12"],
            },
            "dns03": {"online": False, "addresses": ["100.92.0.13"]},
        },
    }
    absent_tailscale = {
        "available": False,
        "backend_state": None,
        "management_host": None,
        "dns_nodes": {},
    }
    absent_netbird = {
        "available": False,
        "management_connected": None,
        "management_host": None,
        "dns_nodes": {},
    }
    try:
        # Both overlays: Tailscale from the fixed bundle path, NetBird from PATH.
        configure(fakes / "path-netbird", bundle_tailscale, None)
        both = server.gateway.tunnel_status()
        assert both["schema_version"] == 2
        assert both["operation"] == "tunnel.status"
        assert both["data"] == {
            "overlays": {
                "tailscale": expected_tailscale,
                "netbird": expected_netbird,
            }
        }, both

        # Only Tailscale, found on PATH; NetBird is not installed.
        configure(fakes / "path-tailscale", None, None)
        only_tailscale = server.gateway.tunnel_status()["data"]["overlays"]
        assert only_tailscale == {
            "tailscale": expected_tailscale,
            "netbird": absent_netbird,
        }, only_tailscale

        # Only NetBird, from its fixed path; Tailscale is not installed.
        configure(empty_path, None, fakes / "fixed" / "netbird")
        only_netbird = server.gateway.tunnel_status()["data"]["overlays"]
        assert only_netbird == {
            "tailscale": absent_tailscale,
            "netbird": expected_netbird,
        }, only_netbird

        # Neither overlay CLI is installed.
        configure(empty_path, None, None)
        expect_tool_error(
            server.gateway.tunnel_status,
            "neither the Tailscale nor the NetBird CLI is available",
        )

        # A present CLI with invalid output fails the whole tool.
        configure(empty_path, bundle_tailscale, fakes / "invalid" / "netbird")
        expect_tool_error(
            server.gateway.tunnel_status, "NetBird returned invalid JSON"
        )
        configure(empty_path, None, fakes / "invalid" / "netbird-shape")
        expect_tool_error(
            server.gateway.tunnel_status, "NetBird returned invalid JSON"
        )
        configure(empty_path, fakes / "invalid" / "tailscale", None)
        expect_tool_error(
            server.gateway.tunnel_status, "Tailscale returned invalid JSON"
        )

        # A set command variable must be an absolute executable path.
        configure(empty_path, bundle_tailscale, not_executable)
        expect_tool_error(
            server.gateway.tunnel_status,
            "configured NetBird command is unavailable",
        )
        configure(empty_path, bundle_tailscale, "relative/netbird")
        expect_tool_error(
            server.gateway.tunnel_status,
            "configured NetBird command is unavailable",
        )
        configure(fakes / "path-netbird", "relative/tailscale", None)
        expect_tool_error(
            server.gateway.tunnel_status,
            "configured Tailscale command is unavailable",
        )
    finally:
        os.environ.pop("DEVICE_OS_AGENT_TAILSCALE_COMMAND", None)
        os.environ.pop("DEVICE_OS_AGENT_NETBIRD_COMMAND", None)
        os.environ["PATH"] = saved_path


async def inspect_tools(race_enabled: Path) -> None:
    async with Client(server.mcp) as client:
        listed = await client.list_tools()
        names = {tool.name for tool in listed.tools}
        assert names == {
            "repository_status",
            "world_validate",
            "world_plan",
            "world_simulate",
            "world_capacity",
            "network_preflight",
            "tunnel_status",
            "dns_health",
            "dns_plan",
            "dns_apply",
        }
        assert not names.intersection(
            {"burn", "write", "restore", "reinstall", "shell", "exec"}
        )
        validated = await client.call_tool("world_validate", {})
        assert validated.is_error is not True
        assert validated.structured_content["ok"] is True
        race_enabled.touch()
        inventory, dns = await asyncio.gather(
            client.call_tool("world_plan", {"media": "inventory-capture"}),
            client.call_tool("world_plan", {"media": "dns-install"}),
        )
        assert inventory.structured_content["data"]["media"] == "inventory-capture"
        assert dns.structured_content["data"]["media"] == "dns-install"


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="device-os-agent-test-") as temporary:
        root = Path(temporary)
        invocation = root / "invocation.json"
        token = root / "applier.token"
        ca_file = root / "technitium-ca.pem"
        token.write_text("test-token\n", encoding="utf-8")
        token.chmod(0o600)
        ca_file.write_text("test-ca\n", encoding="utf-8")
        (root / "burn-history").mkdir(parents=True)
        (root / "burn-history" / "dns-records.zone").write_text(
            "$ORIGIN home.arpa.\n", encoding="utf-8"
        )
        executable(
            root / "device-os",
            "#!/bin/sh\n"
            "set -eu\n"
            "repo_root=$(CDPATH='' cd -- \"$(dirname -- \"$0\")\" && pwd)\n"
            "selected=${DEVICE_OS_MEDIA:-dns-install}\n"
            "plan=${DEVICE_OS_WORLD_PLAN:-$repo_root/work/device-os/world.json}\n"
            "if [ -e \"$repo_root/race-enabled\" ] && [ \"${2:-}\" = plan ]; then\n"
            "  mkdir -p \"$(dirname -- \"$plan\")\" \"$repo_root/race\"\n"
            "  if [ \"$selected\" = inventory-capture ]; then\n"
            "    printf '{\"media\":\"%s\"}\\n' \"$selected\" > \"$plan\"\n"
            "    : > \"$repo_root/race/inventory-ready\"\n"
            "    while [ ! -e \"$repo_root/race/dns-ready\" ]; do sleep 0.01; done\n"
            "  else\n"
            "    while [ ! -e \"$repo_root/race/inventory-ready\" ]; do sleep 0.01; done\n"
            "    printf '{\"media\":\"%s\"}\\n' \"$selected\" > \"$plan\"\n"
            "    : > \"$repo_root/race/dns-ready\"\n"
            "  fi\n"
            "  cat \"$plan\"\n"
            "else\n"
            "  printf '{\"command\":\"%s %s\",\"offline\":\"%s\",\"media\":\"%s\"}\\n' "
            '"${2:-}" "${3:-}" "${6:-}" "$selected"\n'
            "fi\n",
        )
        executable(
            root / "engine" / "installer" / "management" / "network-preflight",
            "#!/bin/sh\n"
            "set -eu\n"
            "[ \"$1\" = --json ]\n"
            "if [ \"${2:-}\" = --offline ]; then\n"
            "  printf '{\"router_cidr\":\"%s\",\"internet_checked\":false}\\n' \"$3\"\n"
            "else\n"
            "  printf '{\"router_cidr\":\"%s\",\"internet_checked\":true}\\n' \"$2\"\n"
            "fi\n",
        )
        executable(
            root / "engine" / "installer" / "management" / "dnsctl",
            "#!/bin/sh\n"
            "set -eu\n"
            "python3 - \"$@\" <<'PY'\n"
            "import json, os, sys\n"
            f"json.dump({{'argv': sys.argv[1:], 'env': {{k: v for k, v in os.environ.items() if k.startswith('TECHNITIUM_')}}, 'has_openai_key': 'OPENAI_API_KEY' in os.environ}}, open({str(invocation)!r}, 'w'))\n"
            "if '--out' in sys.argv:\n"
            "    out = sys.argv[sys.argv.index('--out') + 1]\n"
            "    assert not os.path.exists(out)\n"
            "    open(out, 'w').write('{\"schema_version\":2,\"changed\":true}\\n')\n"
            "print('{\"status\":\"ok\"}')\n"
            "PY\n",
        )
        os.environ["DEVICE_OS_AGENT_STATE_DIR"] = str(root / "state")
        server.gateway = server.Gateway(root)
        result = server.gateway.world_validate()
        assert result["ok"] is True
        inventory_plan = server.gateway.world_plan("inventory-capture")
        assert inventory_plan["data"]["media"] == "inventory-capture"
        expect_tool_error(
            lambda: server.gateway.world_plan("unknown-media"),
            "media must be",
        )
        capacity = server.gateway.world_capacity("16GB")
        assert capacity["data"]["offline"] == "--offline"
        inventory_capacity = server.gateway.world_capacity(
            "16GB", media="inventory-capture"
        )
        assert inventory_capacity["data"]["media"] == "inventory-capture"
        expect_tool_error(
            lambda: server.gateway.world_capacity("/dev/disk0"),
            "capacity must look like",
        )
        expect_tool_error(
            lambda: server.gateway.network_preflight("not-a-network"),
            "router_cidr is invalid",
        )
        network = server.gateway.network_preflight("10.77.0.1/16")
        assert network["data"]["internet_checked"] is True
        offline_network = server.gateway.network_preflight(
            "10.77.0.1/16", check_internet=False
        )
        assert offline_network["data"]["internet_checked"] is False
        simulate_tunnel_status(root)

        os.environ["DEVICE_OS_AGENT_DNS_PLANNER_TOKEN_FILE"] = str(token)
        os.environ["DEVICE_OS_AGENT_DNS_APPLIER_TOKEN_FILE"] = str(token)
        os.environ["DEVICE_OS_AGENT_DNS01_URL"] = "https://dns01:53443"
        os.environ["DEVICE_OS_AGENT_TECHNITIUM_CA_FILE"] = str(ca_file)
        os.environ["OPENAI_API_KEY"] = "must-not-reach-child"
        planned = server.gateway.dns_plan("dns01")
        plan_sha256 = planned["plan_sha256"]
        saved_plan = root / "state" / "dns-plans" / f"{plan_sha256}.json"
        assert hashlib.sha256(saved_plan.read_bytes()).hexdigest() == plan_sha256
        assert json.loads(invocation.read_text(encoding="utf-8"))["argv"][-2] == "--out"
        assert [path.name for path in saved_plan.parent.iterdir()] == [saved_plan.name]
        confirmation = f"APPLY home.arpa TO dns01 PLAN {plan_sha256}"
        os.environ.pop("DEVICE_OS_AGENT_ALLOW_APPLY", None)
        expect_tool_error(
            lambda: server.gateway.dns_apply("dns01", plan_sha256, confirmation),
            "disabled",
        )
        os.environ["DEVICE_OS_AGENT_ALLOW_APPLY"] = "1"
        expect_tool_error(
            lambda: server.gateway.dns_apply("dns01", plan_sha256, "APPLY"),
            "confirmation must exactly equal",
        )
        expect_tool_error(
            lambda: server.gateway.dns_apply("dns01", "a" * 40, confirmation),
            "plan_sha256 must be",
        )
        unknown = "b" * 64
        expect_tool_error(
            lambda: server.gateway.dns_apply(
                "dns01", unknown, f"APPLY home.arpa TO dns01 PLAN {unknown}"
            ),
            "no saved plan",
        )
        token.chmod(0o644)
        expect_tool_error(
            lambda: server.gateway.dns_apply("dns01", plan_sha256, confirmation),
            "must not be accessible by group or others",
        )
        token.chmod(0o600)
        applied = server.gateway.dns_apply("dns01", plan_sha256, confirmation)
        assert applied["ok"] is True
        recorded = json.loads(invocation.read_text(encoding="utf-8"))
        assert recorded["argv"] == [
            "apply",
            "--plan",
            str(saved_plan),
            "--plan-sha256",
            plan_sha256,
            "--confirm",
            "APPLY",
        ]
        assert recorded["env"] == {
            "TECHNITIUM_CA_FILE": str(ca_file),
            "TECHNITIUM_TOKEN_FILE": str(token),
            "TECHNITIUM_URL": "https://dns01:53443",
        }
        assert recorded["has_openai_key"] is False
        assert "test-token" not in invocation.read_text(encoding="utf-8")

        asyncio.run(inspect_tools(root / "race-enabled"))
        print("agent gateway simulations: passed")


if __name__ == "__main__":
    main()
