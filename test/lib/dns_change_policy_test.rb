require "test_helper"
require_relative "../../script/ops/dns_change_policy"

class DnsChangePolicyTest < ActiveSupport::TestCase
  def record(name: "stuttgart-live.de", type: "A", value: "83.169.28.13", priority: nil, ttl: 600)
    { "name" => name, "type" => type, "value" => value, "priority" => priority, "ttl" => ttl }
  end

  test "protects every non web value priority and TTL even against a bad allowlist" do
    records = [
      record(type: "MX", value: "mail.protection.outlook.com", priority: 0),
      record(type: "TXT", value: "v=spf1 include:example.invalid -all"),
      record(name: "unknown._domainkey.stuttgart-live.de", type: "TXT", value: "v=DKIM1; p=public"),
      record(name: "_dmarc.stuttgart-live.de", type: "TXT", value: "v=DMARC1; p=none"),
      record(name: "autodiscover.stuttgart-live.de", type: "CNAME", value: "autodiscover.outlook.com"),
      record(name: "_sip._tcp.stuttgart-live.de", type: "SRV", value: "1 5061 example.invalid", priority: 100),
      record(name: "vpn.russ-live.de", value: "195.50.138.106"),
      record(name: "unknown.stuttgart-live.de", type: "TYPE65400", value: "opaque"),
      record(type: "CAA", value: '0 issue "example.invalid"'),
      record(type: "NS", value: "ns.example.invalid")
    ]
    records.each do |original|
      [ original.merge("value" => "changed"), original.merge("ttl" => 300) ].each do |changed|
        allow = [ { "action" => "remove", "record" => original }, { "action" => "add", "record" => changed } ]
        refute_empty Ops::DnsChangePolicy.violations(before: [ original ], after: [ changed ], allowed_changes: allow), original.inspect
      end
    end
    mx = records.first
    refute_empty Ops::DnsChangePolicy.violations(before: [ mx ], after: [ mx.merge("priority" => 20) ], allowed_changes: [])
    assert_empty Ops::DnsChangePolicy.violations(before: records, after: records.reverse, allowed_changes: [])
  end

  test "allows only exact web deltas including targeted TTL change and reverse rollback" do
    before = [ record, record(name: "www.stuttgart-live.de", type: "AAAA", value: "2001:db8::1") ]
    after = [ record(value: "46.225.224.194", ttl: 300), record(name: "www.stuttgart-live.de", type: "CNAME", value: "stuttgart-live.de", ttl: 300) ]
    allow = before.map { |item| { "action" => "remove", "record" => item } } + after.map { |item| { "action" => "add", "record" => item } }
    assert_empty Ops::DnsChangePolicy.violations(before:, after:, allowed_changes: allow)
    refute_empty Ops::DnsChangePolicy.violations(before:, after: after + [ record(name: "unexpected.stuttgart-live.de") ], allowed_changes: allow)
    reverse = allow.map { |delta| delta.merge("action" => delta["action"] == "add" ? "remove" : "add") }
    assert_empty Ops::DnsChangePolicy.violations(before: after, after: before, allowed_changes: reverse)
    refute_empty Ops::DnsChangePolicy.violations(before:, after: after.map { |item| item.merge("ttl" => 999) }, allowed_changes: allow)
  end

  test "ACME values are a set and only our explicitly owned values may change" do
    foreign = record(name: "_acme-challenge.stuttgart-live.de", type: "TXT", value: "foreign-token")
    own = foreign.merge("value" => "our-token")
    allow = [ { "action" => "add", "record" => own, "owned_acme_value" => true } ]
    assert_empty Ops::DnsChangePolicy.violations(before: [ foreign ], after: [ own, foreign ], allowed_changes: allow)
    refute_empty Ops::DnsChangePolicy.violations(before: [ foreign ], after: [ own ], allowed_changes: allow)
    assert_empty Ops::DnsChangePolicy.violations(before: [ own, foreign ], after: [ foreign ], allowed_changes: [ allow.first.merge("action" => "remove") ])
    refute_empty Ops::DnsChangePolicy.violations(before: [], after: [ own ], allowed_changes: [ allow.first.except("owned_acme_value") ])
  end

  test "only the SOA serial may change and malformed snapshots cannot pass" do
    soa = record(type: "SOA", value: "ns.example.invalid hostmaster.example.invalid 100 28800 7200 604800 600")
    assert_empty Ops::DnsChangePolicy.violations(before: [ soa ], after: [ soa.merge("value" => soa["value"].sub("100", "101")) ], allowed_changes: [])
    refute_empty Ops::DnsChangePolicy.violations(before: [ soa ], after: [ soa.merge("value" => soa["value"].sub("28800", "300")) ], allowed_changes: [])
    refute_empty Ops::DnsChangePolicy.violations(before: [ record.except("ttl") ], after: [], allowed_changes: [])
    refute_empty Ops::DnsChangePolicy.violations(before: [ record, record ], after: [ record ], allowed_changes: [])
  end
end
