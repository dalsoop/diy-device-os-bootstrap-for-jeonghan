#!/usr/bin/env ruby
# SPDX-FileCopyrightText: 2026 dalsoop
# SPDX-License-Identifier: GPL-3.0-only

require "fileutils"
require "json"
require "open3"
require "tmpdir"

runner = File.realpath(File.join(__dir__, "../bin/record-usb-event"))

def assert(condition, message)
  raise message unless condition
end

Dir.mktmpdir("usb-event-simulation") do |temporary|
  repo = File.join(temporary, "repo")
  output = File.join(repo, "world-record")
  FileUtils.mkdir_p(File.join(repo, "world-record/config"))
  File.write(File.join(repo, "world-record/config/home.yaml"), "kind: World\n")

  plan = {
    "schema_version" => 1,
    "source" => {
      "playbook" => "world-record/world-playbook.yaml",
      "world" => "world-record/config/home.yaml"
    },
    "world" => {
      "name" => "Test Home",
      "slug" => "test-home",
      "lifecycle" => "draft",
      "timezone" => "Asia/Seoul"
    },
    "media" => {
      "id" => "dns-install",
      "language" => "ko-KR",
      "entries" => ["dns-appliance"]
    },
    "policies" => {}
  }
  catalog = {
    "schema_version" => 1,
    "catalog" => {
      "revision" => "a" * 40,
      "tree" => "b" * 40
    },
    "world" => plan,
    "entries" => []
  }
  plan_path = File.join(temporary, "world.json")
  catalog_path = File.join(temporary, "catalog.json")
  File.write(plan_path, JSON.generate(plan))
  File.write(catalog_path, JSON.generate(catalog))

  writer = File.join(temporary, "fake-writer")
  File.write(writer, <<~'RUBY')
    #!/usr/bin/env ruby
    require "json"
    device = ARGV[ARGV.index("--device") + 1]
    status = ENV.fetch("FAKE_WRITER_STATUS", "passed")
    evidence = {
      schema_version: 1,
      writer: ENV.fetch("FAKE_WRITER_MODE"),
      device_path: device,
      target: {
        display_name: ENV.fetch("FAKE_WRITER_NAME"),
        bytes: Integer(ENV.fetch("FAKE_WRITER_BYTES"), 10)
      },
      preflight_at: "2026-10-17T02:00:00+09:00",
      completed_at: status == "passed" ? "2026-10-17T02:00:01+09:00" : nil,
      readback: {
        method: "simulated-readback",
        status: status
      }
    }
    File.write(ENV.fetch("DEVICE_OS_WRITE_EVIDENCE"), JSON.pretty_generate(evidence))
    exit(status == "passed" ? 0 : 9)
  RUBY
  FileUtils.chmod(0o755, writer)

  common = {
    "DEVICE_OS_TEST_MODE" => "1",
    "DEVICE_OS_EVENT_REPO_ROOT" => repo,
    "DEVICE_OS_EVENT_OUTPUT_ROOT" => output,
    "FAKE_WRITER_MODE" => "linux-ventoy"
  }

  [
    ["/dev/test-a", "Test USB A", "15833497600", "2026-10-17T02:00:00+09:00"],
    ["/dev/test-b", "Test USB B", "30784094208", "2026-10-17T02:00:01+09:00"]
  ].each do |device, name, bytes, time|
    environment = common.merge(
      "DEVICE_OS_EVENT_TIME" => time,
      "FAKE_WRITER_NAME" => name,
      "FAKE_WRITER_BYTES" => bytes
    )
    stdout, stderr, status = Open3.capture3(
      environment,
      runner,
      "--world-plan", plan_path,
      "--catalog", catalog_path,
      "--writer", "linux-ventoy",
      "--device", device,
      "--", writer, "--device", device
    )
    assert(status.success?, "successful simulated write failed: #{stdout} #{stderr}")
  end

  generations = Dir.glob(File.join(output, "records/usb/*")).sort
  assert(generations.map { |path| File.basename(path) } == [
    "20261017020000-test-home",
    "20261017020001-test-home"
  ], "two devices did not create two generations")
  generations.each do |generation|
    %w[world.yaml world.lock.json media-manifest.json verification.json event.json].each do |name|
      assert(File.file?(File.join(generation, name)), "generation is missing #{name}")
    end
    event = JSON.parse(File.read(File.join(generation, "event.json")))
    assert(event["status"] == "succeeded", "successful event was not recorded")
  end

  collision_environment = common.merge(
    "DEVICE_OS_EVENT_TIME" => "2026-10-17T02:00:00+09:00",
    "FAKE_WRITER_NAME" => "Collision USB",
    "FAKE_WRITER_BYTES" => "15833497600"
  )
  _stdout, stderr, status = Open3.capture3(
    collision_environment,
    runner,
    "--world-plan", plan_path,
    "--catalog", catalog_path,
    "--writer", "linux-ventoy",
    "--device", "/dev/test-collision",
    "--", writer, "--device", "/dev/test-collision"
  )
  assert(!status.success? && stderr.include?("generation ID collision"), "generation collision was accepted")
  assert(Dir.glob(File.join(output, "records/usb/*")).length == 2, "collision overwrote or added a generation")

  _stdout, stderr, status = Open3.capture3(
    common.merge(
      "DEVICE_OS_EVENT_TIME" => "2026-10-17T02:00:03+09:00",
      "FAKE_WRITER_NAME" => "Ambiguous USB",
      "FAKE_WRITER_BYTES" => "15833497600"
    ),
    runner,
    "--world-plan", plan_path,
    "--catalog", catalog_path,
    "--writer", "linux-ventoy",
    "--device", "/dev/test-a",
    "--", writer, "--device", "/dev/test-a", "--device", "/dev/test-b"
  )
  assert(!status.success? && stderr.include?("exactly one --device"), "ambiguous writer target was accepted")

  failure_environment = common.merge(
    "DEVICE_OS_EVENT_TIME" => "2026-10-17T02:00:02+09:00",
    "FAKE_WRITER_NAME" => "Test USB C",
    "FAKE_WRITER_BYTES" => "64000000000",
    "FAKE_WRITER_STATUS" => "pending"
  )
  _stdout, _stderr, status = Open3.capture3(
    failure_environment,
    runner,
    "--world-plan", plan_path,
    "--catalog", catalog_path,
    "--writer", "linux-ventoy",
    "--device", "/dev/test-c",
    "--", writer, "--device", "/dev/test-c"
  )
  assert(status.exitstatus == 9, "failed writer status was not preserved")
  assert(!File.exist?(File.join(output, "records/usb/20261017020002-test-home")), "failed write published a generation")
  failed_events = Dir.glob(File.join(output, "records/usb-failed/2026/*.json"))
  assert(failed_events.length == 1, "failed write did not create exactly one event")
  failed = JSON.parse(File.read(failed_events.first))
  assert(failed["status"] == "failed", "failed event status is wrong")
  assert(failed["failure_code"] == "writer-exit-nonzero", "failed event reason is wrong")

  tracked_json = Dir.glob(File.join(output, "records/{usb-failed,usb}/**/*.json"), File::FNM_EXTGLOB)
  assert(tracked_json.none? { |path| File.read(path).match?(/serial/i) }, "event output contains a serial field")

  puts "USB event simulations: passed"
end
