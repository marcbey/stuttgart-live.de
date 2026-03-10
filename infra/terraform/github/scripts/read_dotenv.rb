#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

query = JSON.parse($stdin.read)
dotenv_file = File.expand_path(query.fetch("dotenv_file"))
keys = query.fetch("keys_csv", "").split(",").map(&:strip).reject(&:empty?)

values = {}

if File.exist?(dotenv_file)
  File.readlines(dotenv_file, chomp: true).each do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")

    normalized = line.sub(/\Aexport\s+/, "")
    key, value = normalized.split("=", 2)
    next if key.nil? || value.nil?

    if value.length >= 2
      quoted_with_double = value.start_with?("\"") && value.end_with?("\"")
      quoted_with_single = value.start_with?("'") && value.end_with?("'")
      value = value[1..-2] if quoted_with_double || quoted_with_single
    end

    values[key] = value
  end
end

result = keys.to_h { |key| [ key, values.fetch(key, "") ] }
puts JSON.generate(result)
