require "test_helper"
require "open3"

class DnsAuditTest < ActiveSupport::TestCase
  test "CLI rejects incomplete inventories and unrelated provider controls but accepts exact forwarding change" do
    Dir.mktmpdir do |root|
      before = { "zone" => "russ-live.de", "inventory_complete" => true, "provider_controls" => { "redirect" => "old forwarding", "vpn" => { "A" => "195.50.138.106" } },
        "records" => [ { "name" => "russ-live.de", "type" => "A", "value" => "217.160.0.49", "priority" => nil, "ttl" => 300 } ] }
      after = Marshal.load(Marshal.dump(before))
      after["provider_controls"]["redirect"] = "disabled"
      allow = { "zone" => "russ-live.de", "changes" => [], "provider_control_changes" => [ { "key" => "redirect", "before" => "old forwarding", "after" => "disabled" } ] }
      check = lambda do |snapshot|
        File.delete(File.join(root, "report.json")) if File.exist?(File.join(root, "report.json"))
        { "before" => before, "after" => snapshot, "allow" => allow }.each { |name, data| File.write(File.join(root, "#{name}.json"), JSON.generate(data)) }
        Open3.capture3("mise", "exec", "--", "bundle", "exec", "ruby", Rails.root.join("bin/dns-audit").to_s,
          "--before", File.join(root, "before.json"), "--after", File.join(root, "after.json"), "--allow", File.join(root, "allow.json"), "--report", File.join(root, "report.json"))
      end
      out, err, status = check.call(after)
      assert status.success?, out + err
      assert_equal 0o600, File.stat(File.join(root, "report.json")).mode & 0o777
      changed = Marshal.load(Marshal.dump(after))
      changed["provider_controls"]["vpn"]["A"] = "203.0.113.1"
      assert_not check.call(changed).last.success?
      assert_not check.call(after.merge("inventory_complete" => false)).last.success?
    end
  end
end
