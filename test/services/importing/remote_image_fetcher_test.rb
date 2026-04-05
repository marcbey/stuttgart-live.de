require "test_helper"
require "socket"

class Importing::RemoteImageFetcherTest < ActiveSupport::TestCase
  test "downloads an image from a local http endpoint" do
    image_body = solid_png_binary(width: 12, height: 8)

    with_http_server(
      path: "/image.png",
      body: image_body,
      content_type: "image/png"
    ) do |url|
      downloaded_file = Importing::RemoteImageFetcher.call(url:)

      assert_equal "image.png", downloaded_file.filename
      assert_equal "image/png", downloaded_file.content_type
      assert_equal image_body, downloaded_file.io.read
    end
  end

  private

  def with_http_server(path:, body:, content_type:)
    server = TCPServer.open("127.0.0.1", 0)

    thread = Thread.new do
      client = server.accept

      begin
        while (line = client.gets)
          break if line == "\r\n"
        end

        client.write <<~HTTP
          HTTP/1.1 200 OK\r
          Content-Type: #{content_type}\r
          Content-Length: #{body.bytesize}\r
          Connection: close\r
          \r
        HTTP
        client.write(body)
      ensure
        client.close
      end
    end

    yield "http://127.0.0.1:#{server.addr[1]}#{path}"
  ensure
    server&.close
    thread&.join
  end
end
