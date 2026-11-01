# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only
# frozen_string_literal: true

require "ipaddr"
require "pathname"
require "yaml"

# The World's network plan: a reviewed preset plus the operator's overrides,
# validated as a whole. Everything the installer embeds per node (os.conf) is
# derived from it, so no address is written by hand outside the World.
module NetworkPlan
  class Error < StandardError; end

  ROLES = %w[dns01 dns02 dns03].freeze
  FIELDS = %w[lan gateway upstreamDns management domain clusterDomain dhcpRange netbirdRange nodes].freeze
  HOSTNAME = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\z/
  PRESETS_PATH = Pathname(__dir__).join("../presets/network-plans.yaml").expand_path
  PRIVATE = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16].map { |value| IPAddr.new(value) }.freeze
  # Ranges other software on the same machines or networks takes by default.
  RESERVED = {
    "Tailscale and carrier-grade NAT (100.64.0.0/10)" => ["100.64.0.0", "100.127.255.255"],
    "Docker default address pools (172.17.0.0-172.31.255.255)" => ["172.17.0.0", "172.31.255.255"],
    "k3s pod and service networks (10.42.0.0/15)" => ["10.42.0.0", "10.43.255.255"],
    "Podman default network (10.88.0.0/16)" => ["10.88.0.0", "10.88.255.255"],
    "Podman, Kubernetes service and Flannel pools (10.89.0.0-10.255.255.255)" => ["10.89.0.0", "10.255.255.255"]
  }.transform_values { |low, high| [IPAddr.new(low).to_i, IPAddr.new(high).to_i] }.freeze

  module_function

  def fail_plan(message)
    raise Error, message
  end

  def presets(path = PRESETS_PATH)
    document = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
    fail_plan("network plan presets are malformed") unless document.is_a?(Hash) &&
                                                          document["kind"] == "NetworkPlanPresets" &&
                                                          document["presets"].is_a?(Hash)
    document["presets"]
  end

  # World.spec.networkPlan -> the merged, validated plan (string keys).
  def resolve(spec_plan, overlays, presets_path: PRESETS_PATH)
    fail_plan("World.spec.networkPlan must be a mapping") unless spec_plan.is_a?(Hash)
    unknown = spec_plan.keys - FIELDS - ["preset"]
    fail_plan("unknown networkPlan field: #{unknown.first}") unless unknown.empty?
    plan = {}
    if spec_plan.key?("preset")
      name = spec_plan["preset"]
      all = presets(presets_path)
      fail_plan("unknown network plan preset: #{name}") unless name.is_a?(String) && all.key?(name)
      plan = all[name].reject { |key, _value| key == "description" }
    end
    spec_plan.each do |key, value|
      next if key == "preset"

      if key == "nodes"
        fail_plan("networkPlan.nodes must be a mapping") unless value.is_a?(Hash)
        plan["nodes"] = (plan["nodes"] || {}).merge(value)
      else
        plan[key] = value
      end
    end
    validate(plan, overlays)
  end

  def text(plan, key)
    value = plan[key]
    fail_plan("networkPlan.#{key} must be a non-empty string") unless value.is_a?(String) && !value.empty?
    value
  end

  def network(plan, key)
    value = text(plan, key)
    fail_plan("networkPlan.#{key} must be an IPv4 CIDR") unless value.match?(%r{\A\d+\.\d+\.\d+\.\d+/\d+\z})
    cidr = IPAddr.new(value)
    fail_plan("networkPlan.#{key} must be an IPv4 CIDR") unless cidr.ipv4?
    fail_plan("networkPlan.#{key} is not a network address: #{value}") unless cidr.to_s == value.split("/").first
    [cidr, value.split("/").last.to_i]
  rescue IPAddr::InvalidAddressError
    fail_plan("networkPlan.#{key} is not a valid CIDR")
  end

  def host(value, label)
    fail_plan("#{label} must be an IPv4 address") unless value.is_a?(String) && value.match?(/\A\d+\.\d+\.\d+\.\d+\z/)
    address = IPAddr.new(value)
    fail_plan("#{label} must be an IPv4 address") unless address.ipv4? && address.to_s == value
    address
  rescue IPAddr::InvalidAddressError
    fail_plan("#{label} is not a valid IPv4 address")
  end

  def bounds(cidr, prefix)
    low = cidr.to_i
    [low, low + (2**(32 - prefix)) - 1]
  end

  def overlaps?(a, b)
    a[0] <= b[1] && b[0] <= a[1]
  end

  def reject_reserved(label, range)
    RESERVED.each do |name, reserved|
      fail_plan("#{label} overlaps #{name}") if overlaps?(range, reserved)
    end
  end

  def usable_host(address, lan, label, gateway: nil)
    value = address.to_i
    fail_plan("#{label} is outside the LAN") unless value.between?(lan[0], lan[1])
    fail_plan("#{label} is the LAN's network or broadcast address") if [lan[0], lan[1]].include?(value)
    fail_plan("#{label} is the gateway") if gateway && value == gateway.to_i
  end

  def validate(plan, overlays)
    lan_cidr, lan_prefix = network(plan, "lan")
    fail_plan("networkPlan.lan prefix must be between /8 and /30") unless lan_prefix.between?(8, 30)
    fail_plan("networkPlan.lan must be a private (RFC 1918) range") unless PRIVATE.any? { |block| block.include?(lan_cidr) }
    lan = bounds(lan_cidr, lan_prefix)
    reject_reserved("networkPlan.lan", lan)

    gateway = host(plan["gateway"], "networkPlan.gateway")
    usable_host(gateway, lan, "networkPlan.gateway")
    upstream = host(plan["upstreamDns"], "networkPlan.upstreamDns")

    management_cidr, management_prefix = network(plan, "management")
    management = bounds(management_cidr, management_prefix)
    fail_plan("networkPlan.management must lie inside the LAN") unless management_prefix >= lan_prefix &&
                                                                     management[0] >= lan[0] && management[1] <= lan[1]

    %w[domain clusterDomain].each do |key|
      fail_plan("networkPlan.#{key} must be a lowercase DNS name") unless HOSTNAME.match?(text(plan, key))
    end

    dhcp = nil
    if plan.key?("dhcpRange")
      first, last = text(plan, "dhcpRange").split("-", 2)
      fail_plan("networkPlan.dhcpRange must be FIRST-LAST") if last.nil?
      dhcp = [host(first, "networkPlan.dhcpRange start").to_i, host(last, "networkPlan.dhcpRange end").to_i]
      fail_plan("networkPlan.dhcpRange is reversed") if dhcp[0] > dhcp[1]
      fail_plan("networkPlan.dhcpRange lies outside the LAN") unless dhcp[0] >= lan[0] && dhcp[1] <= lan[1]
      fail_plan("networkPlan.gateway lies inside the DHCP range") if gateway.to_i.between?(*dhcp)
    end

    nodes = plan["nodes"]
    fail_plan("networkPlan.nodes must name exactly #{ROLES.join(', ')}") unless nodes.is_a?(Hash) && nodes.keys.sort == ROLES
    addresses = ROLES.map do |role|
      address = host(nodes[role], "networkPlan.nodes.#{role}")
      usable_host(address, lan, "networkPlan.nodes.#{role}", gateway: gateway)
      fail_plan("networkPlan.nodes.#{role} lies inside the DHCP range") if dhcp && address.to_i.between?(*dhcp)
      address.to_s
    end
    fail_plan("networkPlan.nodes repeat an address") unless addresses.uniq.length == addresses.length

    netbird = nil
    if overlays.include?("netbird")
      netbird_cidr, netbird_prefix = network(plan, "netbirdRange")
      fail_plan("networkPlan.netbirdRange prefix must be between /8 and /28") unless netbird_prefix.between?(8, 28)
      netbird_range = bounds(netbird_cidr, netbird_prefix)
      fail_plan("networkPlan.netbirdRange overlaps the LAN") if overlaps?(netbird_range, lan)
      reject_reserved("networkPlan.netbirdRange", netbird_range)
      netbird = plan["netbirdRange"]
    end

    {
      "lan" => plan["lan"],
      "prefix_length" => lan_prefix,
      "netmask" => IPAddr.new("255.255.255.255").mask(lan_prefix).to_s,
      "gateway" => gateway.to_s,
      "upstream_dns" => upstream.to_s,
      "management" => plan["management"],
      "domain" => plan["domain"],
      "cluster_domain" => plan["clusterDomain"],
      "dhcp_range" => plan["dhcpRange"],
      "netbird_range" => netbird,
      "nodes" => ROLES.zip(addresses).to_h
    }
  end

  # The installer's per-node network profile for one role.
  def os_conf(resolved, role)
    lines = [
      "role=#{role}",
      "address=#{resolved['nodes'].fetch(role)}",
      "prefix_length=#{resolved['prefix_length']}",
      "netmask=#{resolved['netmask']}",
      "gateway=#{resolved['gateway']}",
      "dns_servers=#{resolved['upstream_dns']}",
      "domain=#{resolved['domain']}",
      "lan_cidr=#{resolved['lan']}",
      "management_cidr=#{resolved['management']}",
      "cluster_domain=#{resolved['cluster_domain']}"
    ]
    lines << "netbird_range=#{resolved['netbird_range']}" if resolved["netbird_range"]
    lines += %w[
      expected_product_name_sha256=REPLACE_WITH_CAPTURE
      expected_product_sku_sha256=REPLACE_WITH_CAPTURE
      expected_system_serial_sha256=REPLACE_WITH_CAPTURE
      expected_system_uuid_sha256=REPLACE_WITH_CAPTURE
      expected_mac_sha256=REPLACE_WITH_CAPTURE
      expected_disk_model_sha256=REPLACE_WITH_CAPTURE
      expected_disk_serial_sha256=REPLACE_WITH_CAPTURE
      expected_disk_min_bytes=0
      destructive_install_enabled=false
    ]
    lines.join("\n") + "\n"
  end
end
