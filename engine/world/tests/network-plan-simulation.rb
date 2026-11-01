#!/usr/bin/env ruby
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
# frozen_string_literal: true

# The network plan is the only place node addresses are written: presets,
# overrides, the overlap rules, and the generated per-node installer profiles.

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

MODULE_ROOT = Pathname(__dir__).join("..").expand_path
ROOT = MODULE_ROOT.join("../../burn-history").expand_path
RESOLVER = MODULE_ROOT.join("bin/resolve-world")
RENDERER = MODULE_ROOT.join("bin/render-network-plan")

def fail_test(message)
  warn "network-plan-simulation: #{message}"
  exit 1
end

def run(script, playbook, *arguments)
  Open3.capture3(RbConfig.ruby, script.to_s, *arguments, "--playbook", playbook.to_s)
end

# The committed profiles and zone records match the committed World.
_out, err, status = run(RENDERER, ROOT.join(".paths.yaml"), "--check")
fail_test("the committed os.conf files or zone records drifted from the World: #{err}") unless status.success?

def with_world(mutation)
  Dir.mktmpdir("network-plan-") do |directory|
    root = Pathname(directory)
    FileUtils.cp(ROOT.join(".paths.yaml"), root.join(".paths.yaml"))
    world = YAML.safe_load_file(ROOT.join("home.yaml"), permitted_classes: [], aliases: false)
    mutation.call(world)
    File.write(root.join("home.yaml"), YAML.dump(world))
    yield root
  end
end

def profile(root, role)
  root.join("os-installs", role, "os.conf").read.lines.map(&:chomp).to_h { |line| line.split("=", 2) }
end

# A /24 home-router preset renders that plan into every node profile.
with_world(lambda { |world| world["spec"]["networkPlan"] = { "preset" => "home-router-24" } }) do |root|
  _out, err, status = run(RESOLVER, root.join(".paths.yaml"))
  fail_test("the home-router-24 World was rejected: #{err}") unless status.success?
  _out, err, status = run(RENDERER, root.join(".paths.yaml"), "--check")
  fail_test("--check passed before any profile existed") if status.success?
  _out, err, status = run(RENDERER, root.join(".paths.yaml"), "--write")
  fail_test("--write failed: #{err}") unless status.success?
  dns02 = profile(root, "dns02")
  {
    "address" => "192.168.1.54", "prefix_length" => "24", "netmask" => "255.255.255.0",
    "gateway" => "192.168.1.1", "dns_servers" => "192.168.1.1", "lan_cidr" => "192.168.1.0/24",
    "management_cidr" => "192.168.1.0/26", "netbird_range" => "10.78.0.0/16",
    "destructive_install_enabled" => "false"
  }.each do |key, value|
    fail_test("home-router-24 dns02 #{key} is #{dns02[key].inspect}, expected #{value}") unless dns02[key] == value
  end
  _out, err, status = run(RENDERER, root.join(".paths.yaml"), "--check")
  fail_test("--check failed right after --write: #{err}") unless status.success?
end

# Overrides replace single fields of a preset.
with_world(lambda { |world|
  world["spec"]["networkPlan"] = { "preset" => "home-10-77", "netbirdRange" => "10.66.0.0/16",
                                   "nodes" => { "dns03" => "10.77.5.30" } }
}) do |root|
  _out, err, status = run(RENDERER, root.join(".paths.yaml"), "--write")
  fail_test("an overridden plan was rejected: #{err}") unless status.success?
  fail_test("the node override was lost") unless profile(root, "dns03")["address"] == "10.77.5.30"
  fail_test("the untouched node changed") unless profile(root, "dns01")["address"] == "10.77.5.1"
  fail_test("the NetBird override was lost") unless profile(root, "dns01")["netbird_range"] == "10.66.0.0/16"
end

# A World without NetBird needs no NetBird range, and its profiles carry none.
with_world(lambda { |world|
  world["spec"]["overlays"] = %w[tailscale]
  world["spec"]["networkPlan"] = { "preset" => "home-10-77" }
}) do |root|
  _out, err, status = run(RENDERER, root.join(".paths.yaml"), "--write")
  fail_test("a Tailscale-only plan was rejected: #{err}") unless status.success?
  fail_test("a Tailscale-only profile carries a NetBird range") if profile(root, "dns01").key?("netbird_range")
end

{
  "unknown preset" => { "preset" => "office" },
  "unknown field" => { "preset" => "home-10-77", "vlan" => 5 },
  "public LAN" => { "preset" => "home-10-77", "lan" => "8.8.0.0/16", "gateway" => "8.8.0.1",
                    "management" => "8.8.0.0/24", "nodes" => { "dns01" => "8.8.5.1", "dns02" => "8.8.5.2", "dns03" => "8.8.5.3" } },
  "LAN on Podman's default network" => { "preset" => "home-10-77", "lan" => "10.88.0.0/16", "gateway" => "10.88.0.1",
                                         "management" => "10.88.0.0/24",
                                         "nodes" => { "dns01" => "10.88.5.1", "dns02" => "10.88.5.2", "dns03" => "10.88.5.3" } },
  "LAN that is not a network address" => { "preset" => "home-10-77", "lan" => "10.77.5.0/16" },
  "gateway outside the LAN" => { "preset" => "home-10-77", "gateway" => "10.79.0.1" },
  "management outside the LAN" => { "preset" => "home-10-77", "management" => "10.79.0.0/24" },
  "node outside the LAN" => { "preset" => "home-10-77", "nodes" => { "dns01" => "10.79.5.1" } },
  "node on the gateway" => { "preset" => "home-10-77", "nodes" => { "dns01" => "10.77.0.1" } },
  "repeated node address" => { "preset" => "home-10-77", "nodes" => { "dns02" => "10.77.5.1" } },
  "node inside the DHCP range" => { "preset" => "home-router-24", "nodes" => { "dns01" => "192.168.1.150" } },
  "NetBird overlapping the LAN" => { "preset" => "home-10-77", "netbirdRange" => "10.77.128.0/17" },
  "NetBird inside Tailscale's range" => { "preset" => "home-10-77", "netbirdRange" => "100.77.0.0/16" },
  "NetBird on Docker's pools" => { "preset" => "home-10-77", "netbirdRange" => "172.18.0.0/16" },
  "NetBird on Podman's pools" => { "preset" => "home-10-77", "netbirdRange" => "10.89.0.0/16" },
  "public NetBird range" => { "preset" => "home-10-77", "netbirdRange" => "151.0.0.0/8" },
  "loopback NetBird range" => { "preset" => "home-10-77", "netbirdRange" => "127.0.0.0/8" },
  "NetBird range wider than a private block" => { "preset" => "home-10-77", "netbirdRange" => "8.0.0.0/7" },
  "one-character domain" => { "preset" => "home-10-77", "domain" => "a" },
  "NetBird selected without a range" => { "lan" => "10.77.0.0/16", "gateway" => "10.77.0.1", "upstreamDns" => "10.77.0.1",
                                          "management" => "10.77.0.0/24", "domain" => "home.arpa",
                                          "clusterDomain" => "dns-cluster.home.arpa",
                                          "nodes" => { "dns01" => "10.77.5.1", "dns02" => "10.77.5.2", "dns03" => "10.77.5.3" } },
  "a fourth node" => { "preset" => "home-10-77", "nodes" => { "dns04" => "10.77.5.4" } }
}.each do |label, plan|
  with_world(lambda { |world| world["spec"]["networkPlan"] = plan }) do |root|
    _out, _err, status = run(RESOLVER, root.join(".paths.yaml"))
    fail_test("resolve-world accepted #{label}") if status.success?
    _out, _err, status = run(RENDERER, root.join(".paths.yaml"), "--write")
    fail_test("render-network-plan accepted #{label}") if status.success?
  end
end

# A node or network that also states an address must agree with the plan.
with_world(lambda { |world| world["spec"]["nodes"][0]["ipv4"] = "10.77.5.9" }) do |root|
  _out, _err, status = run(RESOLVER, root.join(".paths.yaml"))
  fail_test("a node address disagreeing with the plan was accepted") if status.success?
end
with_world(lambda { |world| world["spec"]["networks"][0]["cidr"] = "10.77.0.0/17" }) do |root|
  _out, _err, status = run(RESOLVER, root.join(".paths.yaml"))
  fail_test("a network disagreeing with the plan was accepted") if status.success?
end

puts "network-plan-simulation: passed"
