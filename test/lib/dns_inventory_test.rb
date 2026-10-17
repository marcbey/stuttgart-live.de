require "test_helper"
require_relative "../../script/ops/dns_inventory"

class DnsInventoryTest < ActiveSupport::TestCase
  test "normalizes the complete Host Europe export including packed SRV and unknown selectors" do
    csv = <<~CSV
      recordtyp,hostname,pointer,extra
      A,,83.169.28.13,
      MX,mail.protection.outlook.com,,0
      NS,ns.example.invalid,203.0.113.1,
      TXT,unknown._domainkey,public-key,
      SRV,146665576/447407/_sipfederationtls._tcp/16/sipfed.online.lync.com/5061:100:1/1020,,
    CSV
    rows = Ops::DnsInventory.hosteurope_records(csv, zone: "stuttgart-live.de")
    assert_equal 5, rows.size
    assert_equal({ "name" => "_sipfederationtls._tcp.stuttgart-live.de", "type" => "SRV", "value" => "1 5061 sipfed.online.lync.com", "priority" => 100 }, rows.last)
    assert_equal "stuttgart-live.de", rows[1].fetch("name")
    assert_equal "ns.example.invalid", rows[2].fetch("value")
    assert_equal "unknown._domainkey.stuttgart-live.de", rows[3].fetch("name")
    assert_raises(ArgumentError) { Ops::DnsInventory.hosteurope_records(csv.sub("5061:100:1", "unrecognized"), zone: "stuttgart-live.de") }
  end

  test "normalizes authoritative TXT chunks priorities and SOA while rejecting non authoritative failures" do
    answer = <<~DNS
      ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1
      ;; flags: qr aa; QUERY: 1, ANSWER: 3
      stuttgart-live.de. 600 IN TXT "v=spf1 " "include:example.invalid -all"
      stuttgart-live.de. 600 IN MX 0 MAIL.PROTECTION.OUTLOOK.COM.
      _sip._tcp.stuttgart-live.de. 3600 IN SRV 100 1 5061 SIPFED.ONLINE.LYNC.COM.
    DNS
    records = Ops::DnsInventory.parse_answer(answer, zone: "stuttgart-live.de")
    assert_equal "v=spf1 include:example.invalid -all", records[0].fetch("value")
    assert_equal 0, records[1].fetch("priority")
    assert_equal "mail.protection.outlook.com", records[1].fetch("value")
    assert_equal "1 5061 sipfed.online.lync.com", records[2].fetch("value")
    assert_raises(ArgumentError) { Ops::DnsInventory.parse_answer(answer.sub("qr aa", "qr rd ra"), zone: "stuttgart-live.de") }
    assert_raises(ArgumentError) { Ops::DnsInventory.parse_answer(answer.sub("NOERROR", "SERVFAIL"), zone: "stuttgart-live.de") }
  end

  test "requires a complete portal inventory and includes independent subdomains and defaults in query plan" do
    portal = { "zone" => "russ-live.de", "inventory_complete" => true, "records" => [ { "name" => "unknown._domainkey.russ-live.de", "type" => "CNAME", "value" => "public.example.invalid" } ],
      "controls" => { "existing_subdomains" => [ "vpn.russ-live.de" ], "vpn" => { "A" => "195.50.138.106" } } }
    inventory = Ops::DnsInventory.new(zone: "russ-live.de", provider: "strato", source: JSON.generate(portal))
    assert_includes inventory.query_plan, [ "vpn.russ-live.de", "AAAA" ]
    assert_includes inventory.query_plan, [ "autodiscover.vpn.russ-live.de", "CNAME" ]
    assert_includes inventory.query_plan, [ "unknown._domainkey.russ-live.de", "CNAME" ]
    assert_includes inventory.query_plan, [ "_dmarc.russ-live.de", "TXT" ]
    assert_raises(ArgumentError) { Ops::DnsInventory.new(zone: "russ-live.de", provider: "strato", source: JSON.generate(portal.merge("inventory_complete" => false))) }
    assert_raises(ArgumentError) { inventory.snapshot(server: "docks07.rzone.de", query: ->(*) { ";; status: NOERROR\n;; flags: qr aa;\n" }) }
  end
end
