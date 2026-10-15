module LegacyRedirects
  class Benchmark
    def initialize(paths: nil, samples: 100, resolver: Resolver.method(:call))
      @paths = paths || LegacyRedirect.order(:id).limit(100).pluck(:source_path)
      @samples, @resolver = Integer(samples), resolver
      raise ArgumentError, "Samples must be between 1 and 10000" unless @samples.between?(1, 10_000)
    end

    def call
      raise ArgumentError, "No inventory paths available" if @paths.empty?
      { environment: "local", production_verified: false, excludes: "network and application 404 handling", warm: measure(cold: false), cold: measure(cold: true) }
    end

    private

    def measure(cold:)
      timings = @samples.times.map do |index|
        path = @paths[index % @paths.length]
        duration = nil
        LegacyRedirect.transaction(requires_new: true) do
          row = LegacyRedirect.find_by(source_path: path)
          if cold && row && !row.manual? && !row.disabled?
            row.update_columns(status: "unresolved", target_type: nil, target_id: nil, target_path: nil, checked_at: nil, resolution_version: nil)
            Rails.cache.delete("legacy_redirects/missing/#{Invalidation.version}/#{Digest::SHA256.hexdigest(path)}")
          end
          @resolver.call(path: path, query: "") unless cold
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @resolver.call(path: path, query: "")
          duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
          raise ActiveRecord::Rollback
        end
        duration
      end.sort
      { samples: timings.size, p50_ms: timings[((timings.size - 1) * 0.5).ceil].round(3), p95_ms: timings[((timings.size - 1) * 0.95).ceil].round(3) }
    end
  end
end
