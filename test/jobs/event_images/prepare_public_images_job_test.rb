require "test_helper"

module EventImages
  class PreparePublicImagesJobTest < ActiveJob::TestCase
    setup do
      event = events(:published_one)
      event.update!(start_at: 2.days.from_now)
      @image = event.import_event_images.create!(
        source: "easyticket", image_type: "image_url", image_url: "https://images.example/source.png",
        role: "cover", aspect_hint: "landscape", position: 0
      )
      clear_enqueued_jobs
    end

    test "missing remote images are discarded without retrying or creating blobs" do
      [ 404, 410 ].each do |status|
        with_http_status(status) do
          assert_no_difference "ActiveStorage::Blob.count" do
            assert_no_enqueued_jobs(only: PreparePublicImagesJob) do
              PreparePublicImagesJob.perform_now(@image)
            end
          end
        end

        assert_nil @image.reload.public_file
        assert_equal "https://images.example/source.png", @image.image_url
      end
    end

    test "temporary provider errors still retry preparation" do
      with_http_status(503) do
        assert_enqueued_with(job: PreparePublicImagesJob, args: [ @image ]) do
          PreparePublicImagesJob.perform_now(@image)
        end
      end

      assert_nil @image.reload.public_file
    end

    private

    def with_http_status(status)
      original_new = PublicImages::HttpFetcher.method(:new)
      fetcher = PublicImages::HttpFetcher.new(
        dns: ->(_) { [ "93.184.216.34" ] },
        transport: ->(*) { { status: status, headers: {}, body: "" } },
        interval: 0
      )
      PublicImages::HttpFetcher.define_singleton_method(:new) { fetcher }
      yield
    ensure
      PublicImages::HttpFetcher.define_singleton_method(:new, original_new)
    end
  end
end
