require "csv"
require "json"
require "digest"
require "time"
require "open3"
require_relative "dns_change_policy"

module Ops
  class DnsInventory
    TYPES = %w[A AAAA CNAME MX TXT NS SOA SRV CAA].freeze
    SERVERS = { "stuttgart-live.de" => %w[ns27.domaincontrol.com ns28.domaincontrol.com], "russ-live.de" => %w[docks07.rzone.de shades02.rzone.de] }.freeze

    def initialize(zone:, provider:, source:)
      raise ArgumentError, "Unbekannte Zone" unless SERVERS.key?(zone)
      @zone, @provider, @source = zone, provider, source
      if provider == "hosteurope" && zone == "stuttgart-live.de"
        @expected = self.class.hosteurope_records(source, zone:)
        @controls = {}
      elsif provider == "strato" && zone == "russ-live.de"
        portal = JSON.parse(source)
        raise ArgumentError, "Vollständige STRATO-Ansicht einschließlich aller Subdomains erforderlich" unless portal["zone"] == zone && portal["inventory_complete"] == true && portal["records"].is_a?(Array) && portal["controls"].is_a?(Hash) && portal["controls"]["existing_subdomains"].is_a?(Array)
        @expected, @controls = portal.values_at("records", "controls")
        @expected.each do |row|
          raise ArgumentError, "Ungültige Provider-Zeile" unless row.is_a?(Hash) && %w[name type value].all? { |key| row[key].is_a?(String) }
        end
      else
        raise ArgumentError, "Provider und Zone stimmen nicht überein"
      end
    end

    def query_plan
      names = @expected.map { |record| record.fetch("name") }
      names.concat([ @zone, "www.#{@zone}", "staging.#{@zone}", "_dmarc.#{@zone}" ])
      names.concat(%W[_acme-challenge.#{@zone} _acme-challenge.www.#{@zone} _acme-challenge.staging.#{@zone}])
      @controls.fetch("existing_subdomains", []).each do |name|
        names.concat([ name, "autodiscover.#{name}", "_dmarc.#{name}" ])
      end
      names.each { |name| raise ArgumentError, "Name außerhalb der Zone" unless name == @zone || name.end_with?(".#{@zone}") }
      names.uniq.product((TYPES + @expected.map { |record| record.fetch("type") }).uniq)
    end

    def snapshot(server:, query: method(:dig))
      raise ArgumentError, "Unbekannter autoritativer Nameserver" unless SERVERS.fetch(@zone).include?(server)
      answers = query_plan.map { |name, type| { "name" => name, "type" => type, "response" => query.call(server, name, type) } }
      records = answers.flat_map { |answer| self.class.parse_answer(answer.fetch("response"), zone: @zone) }.uniq
      @expected.each do |expected|
        match = records.any? do |record|
          expected.all? do |key, value|
            next true unless %w[name type value priority ttl].include?(key)
            normalized = key == "value" ? self.class.normalize_value(expected.fetch("type"), value) : value
            record[key] == normalized
          end
        end
        raise ArgumentError, "Provider/Autorität weichen ab: #{expected.fetch('name')} #{expected.fetch('type')}" unless match
      end
      raise ArgumentError, "Autoritative SOA fehlt" unless records.any? { |record| record["name"] == @zone && record["type"] == "SOA" }
      { "zone" => @zone, "provider" => @provider, "inventory_complete" => true, "captured_at" => Time.now.utc.iso8601,
        "source_sha256" => Digest::SHA256.hexdigest(@source), "server" => server, "provider_controls" => @controls,
        "records" => records.sort_by { |record| [ record["name"], record["type"], record["value"] ] }, "queries" => answers }
    end

    def self.hosteurope_records(source, zone:)
      csv = CSV.parse(source, headers: true)
      raise ArgumentError, "Unbekanntes Host-Europe-Exportformat" unless csv.headers == %w[recordtyp hostname pointer extra]
      csv.map do |row|
        type, host, value, extra = row.values_at("recordtyp", "hostname", "pointer", "extra")
        priority = nil
        if type == "SRV"
          parts = host.to_s.split("/")
          raise ArgumentError, "Unbekanntes gepacktes SRV-Format" unless parts.size == 7 && parts[2].start_with?("_") && parts[5].match?(/\A\d+:\d+:\d+\z/)
          port, priority, weight = parts[5].split(":").map { |part| Integer(part) }
          host, value = parts[2], "#{weight} #{port} #{parts[4]}"
        elsif %w[MX NS].include?(type)
          value, host = host, zone
          priority = Integer(extra) if type == "MX"
        end
        name = host.to_s.empty? || host == "@" ? zone : host.to_s.delete_suffix(".")
        name = "#{name}.#{zone}" unless name == zone || name.end_with?(".#{zone}")
        raise ArgumentError, "Unvollständige Provider-Zeile" if type.to_s.empty? || value.to_s.empty?
        { "name" => name.downcase, "type" => type, "value" => normalize_value(type, value), "priority" => priority }
      end
    end

    def self.parse_answer(response, zone:)
      raise ArgumentError, "DNS-Antwort fehlt oder ist nicht autoritativ" unless response.match?(/status: (?:NOERROR|NXDOMAIN)\b/) && response.match?(/flags: [^;]*\baa\b/)
      response.lines.filter_map do |line|
        next if line.strip.empty? || line.start_with?(";")
        match = line.match(/\A(\S+)\s+(\d+)\s+IN\s+(\S+)\s+(.+?)\s*\z/)
        raise ArgumentError, "Unlesbare DNS-Antwort" unless match
        name, ttl, type, value = match.captures
        name = name.downcase.delete_suffix(".")
        next unless name == zone || name.end_with?(".#{zone}")
        priority = nil
        priority, value = value.split(/\s+/, 2) if %w[MX SRV].include?(type)
        value = parse_txt(value) if type == "TXT"
        record = { "name" => name, "type" => type, "value" => normalize_value(type, value), "priority" => priority && Integer(priority), "ttl" => Integer(ttl) }
        raise ArgumentError, "Ungültiger DNS-Datensatz" unless DnsChangePolicy.valid_record?(record)
        record
      end
    end

    def self.parse_txt(value)
      chunks = value.scan(/"((?:[^"\\]|\\.)*)"/).flatten
      raise ArgumentError, "Unlesbarer TXT-Datensatz" if chunks.empty? || !value.gsub(/"(?:[^"\\]|\\.)*"/, "").strip.empty?
      chunks.join.gsub(/\\(\d{3}|.)/) { Regexp.last_match(1).match?(/\A\d{3}\z/) ? Integer(Regexp.last_match(1)).chr : Regexp.last_match(1) }
    end

    def self.normalize_value(type, value)
      return value.downcase.delete_suffix(".") if %w[NS CNAME MX].include?(type)
      return value.split.map { |part| part.downcase.delete_suffix(".") }.join(" ") if %w[SRV SOA].include?(type)
      value
    end

    private

    def dig(server, name, type)
      out, _, status = Open3.capture3("dig", "@#{server}", name, type, "+norecurse", "+noall", "+answer", "+comments", "+time=3", "+tries=1")
      raise ArgumentError, "DNS-Abfrage fehlgeschlagen: #{name} #{type}" unless status.success?
      out
    end
  end
end
