require "test_helper"

class Backend::EventImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:needs_review_one)
    @user = users(:one)
  end

  test "requires authentication for uploads" do
    post backend_event_event_images_url(@event), params: {
      status: "needs_review",
      event_image: {
        purpose: EventImage::PURPOSE_SLIDER,
        files: [ uploaded_image ]
      }
    }

    assert_redirected_to new_session_url
  end

  test "creates multiple slider images" do
    sign_in_as(@user)

    assert_difference -> { @event.event_images.slider.count }, 2 do
      post backend_event_event_images_url(@event), params: {
        status: "needs_review",
        event_image: {
          purpose: EventImage::PURPOSE_SLIDER,
          alt_text: "Slider Alt",
          sub_text: "Slider Sub",
          files: [ uploaded_image, uploaded_image ]
        }
      }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    created = @event.event_images.slider.ordered.last
    assert_equal "Slider Alt", created.alt_text
    assert_equal "Slider Sub", created.sub_text
  end

  test "ignores filename strings and redirects with alert" do
    sign_in_as(@user)

    assert_no_difference -> { @event.event_images.count } do
      post backend_event_event_images_url(@event), params: {
        status: "needs_review",
        event_image: {
          purpose: EventImage::PURPOSE_SLIDER,
          files: [ "foo.jpg", "bar.png" ]
        }
      }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    assert_match(/gültige Bilddateien/, flash[:alert].to_s)
  end

  test "replaces existing detail hero image" do
    sign_in_as(@user)
    existing = create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO)

    assert_difference -> { @event.event_images.detail_hero.count }, 0 do
      post backend_event_event_images_url(@event), params: {
        status: "needs_review",
        event_image: {
          purpose: EventImage::PURPOSE_DETAIL_HERO,
          files: [ uploaded_image ]
        }
      }
    end

    assert_not EventImage.exists?(existing.id)
  end

  test "creates event image with optional grid settings" do
    sign_in_as(@user)

    assert_difference -> { @event.event_images.detail_hero.count }, 1 do
      post backend_event_event_images_url(@event), params: {
        status: "needs_review",
        event_image: {
          purpose: EventImage::PURPOSE_DETAIL_HERO,
          alt_text: "Eventbild Alt",
          sub_text: "Eventbild Sub",
          grid_variant: EventImage::GRID_VARIANT_2X1,
          card_focus_x: "18",
          card_focus_y: "72",
          card_zoom: "145",
          files: [ uploaded_image ]
        }
      }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    created = @event.event_images.detail_hero.ordered.last
    assert_equal "Eventbild Alt", created.alt_text
    assert_equal "Eventbild Sub", created.sub_text
    assert_equal EventImage::GRID_VARIANT_2X1, created.grid_variant
    assert_equal 18.0, created.card_focus_x_value
    assert_equal 72.0, created.card_focus_y_value
    assert_equal 145.0, created.card_zoom_value
  end

  test "deletes event image" do
    sign_in_as(@user)
    create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO)

    assert_difference -> { @event.event_images.detail_hero.count }, -1 do
      delete destroy_editorial_main_backend_event_event_images_url(@event), params: { status: "needs_review" }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
  end

  test "updates alt and sub text" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_SLIDER, alt_text: nil, sub_text: nil)

    patch backend_event_event_image_url(@event, image), params: {
      status: "needs_review",
      event_image: {
        alt_text: "Neuer Alt",
        sub_text: "Neue Subline"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    image.reload
    assert_equal "Neuer Alt", image.alt_text
    assert_equal "Neue Subline", image.sub_text
  end

  test "updates slider image metadata via turbo stream without redirect" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_SLIDER, alt_text: nil, sub_text: nil)

    patch backend_event_event_image_url(@event, image), params: {
      status: "needs_review",
      event_image: {
        alt_text: "Neuer Alt",
        sub_text: "Neue Subline"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Bild-Metadaten wurden gespeichert."
    assert_includes response.body, "target=\"#{ActionView::RecordIdentifier.dom_id(image, :slider_card)}\""
    assert_includes response.body, "action=\"replace\""
    image.reload
    assert_equal "Neuer Alt", image.alt_text
    assert_equal "Neue Subline", image.sub_text
  end

  test "updates card crop settings for event image" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    patch backend_event_event_image_url(@event, image), params: {
      status: "needs_review",
      event_image: {
        card_focus_x: "18",
        card_focus_y: "72",
        card_zoom: "145"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    image.reload
    assert_equal 18.0, image.card_focus_x_value
    assert_equal 72.0, image.card_focus_y_value
    assert_equal 145.0, image.card_zoom_value
  end

  test "updates grid variant for event image" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    patch backend_event_event_image_url(@event, image), params: {
      status: "needs_review",
      event_image: {
        grid_variant: EventImage::GRID_VARIANT_1X2
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    assert_equal EventImage::GRID_VARIANT_1X2, image.reload.grid_variant
  end

  test "creates event image from import image" do
    sign_in_as(@user)
    import_image = create_import_event_image

    response = fake_image_response

    count_before = EventImage.where(event: @event, purpose: EventImage::PURPOSE_DETAIL_HERO).count
    http_singleton = Net::HTTP.singleton_class
    original_get_response = Net::HTTP.method(:get_response)

    http_singleton.define_method(:get_response, ->(_uri) { response })
    begin
      post create_from_import_backend_event_event_images_url(@event), params: {
        status: "needs_review",
          event_image: {
            import_event_image_id: import_image.id,
            purpose: EventImage::PURPOSE_DETAIL_HERO,
            grid_variant: EventImage::GRID_VARIANT_1X1
          }
        }
    ensure
      http_singleton.define_method(:get_response, original_get_response)
    end

    count_after = EventImage.where(event: @event, purpose: EventImage::PURPOSE_DETAIL_HERO).count
    assert_equal count_before + 1, count_after, flash[:alert].presence || "expected imported image to be created"
    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
  end

  test "deletes arbitrary event image by member route" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    assert_difference -> { @event.event_images.count }, -1 do
      delete backend_event_event_image_url(@event, image), params: { status: "needs_review" }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
  end

  test "updates event image via turbo stream without redirect" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO, alt_text: nil, sub_text: nil)

    patch backend_event_event_image_url(@event, image), params: {
      status: "needs_review",
      event_image: {
        alt_text: "Neuer Eventbild Alt",
        sub_text: "Neue Eventbild Subline"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Eventbild wurde gespeichert."
    assert_includes response.body, "target=\"#{ActionView::RecordIdentifier.dom_id(@event, :event_image_section)}\""
    assert_includes response.body, "action=\"replace\""
  end

  test "deletes event image via turbo stream and replaces section" do
    sign_in_as(@user)
    create_event_image(purpose: EventImage::PURPOSE_DETAIL_HERO)

    assert_difference -> { @event.event_images.detail_hero.count }, -1 do
      delete destroy_editorial_main_backend_event_event_images_url(@event), params: { status: "needs_review" }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Eventbild wurde gelöscht."
    assert_includes response.body, "target=\"#{ActionView::RecordIdentifier.dom_id(@event, :event_image_section)}\""
    assert_includes response.body, "action=\"replace\""
  end

  test "deletes slider image via turbo stream and removes its card" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_SLIDER)
    card_id = ActionView::RecordIdentifier.dom_id(image, :slider_card)

    assert_difference -> { @event.event_images.count }, -1 do
      delete backend_event_event_image_url(@event, image), params: { status: "needs_review" }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Bild wurde gelöscht."
    assert_includes response.body, "target=\"#{card_id}\""
    assert_includes response.body, "action=\"remove\""
  end

  private

  def uploaded_image
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )
  end

  def create_event_image(purpose:, grid_variant: nil, alt_text: "Alt", sub_text: "Sub")
    image = @event.event_images.new(
      purpose: purpose,
      grid_variant: grid_variant,
      alt_text: alt_text,
      sub_text: sub_text
    )
    image.file.attach(uploaded_image)
    image.save!
    image
  end

  def create_import_event_image
    @event.import_event_images.create!(
      source: "eventim",
      image_type: "large",
      image_url: "https://img.example/event-large.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )
  end

  def fake_image_response
    Class.new do
      attr_reader :body, :content_type, :code

      def initialize(body:, content_type:, code:)
        @body = body
        @content_type = content_type
        @code = code
      end

      def is_a?(klass)
        klass == Net::HTTPSuccess || super
      end
    end.new(
      body: File.binread(Rails.root.join("test/fixtures/files/test_image.png")),
      content_type: "image/png",
      code: "200"
    )
  end
end
