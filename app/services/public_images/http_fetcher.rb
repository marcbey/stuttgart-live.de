module PublicImages
  class HttpFetcher < GuardedHttpFetcher
    MAX_BYTES = 12.megabytes

    def initialize(**options)
      super(retries: 1, max_redirects: 3, total_timeout: 25, **options)
    end

    def call(url, max_bytes: MAX_BYTES)
      super(url, max_bytes: [ max_bytes, MAX_BYTES ].min)
    end
  end
end
