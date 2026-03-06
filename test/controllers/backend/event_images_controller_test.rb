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

  test "updates card crop settings for grid images" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_GRID_TILE, grid_variant: EventImage::GRID_VARIANT_1X1)

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

  test "deletes event image" do
    sign_in_as(@user)
    image = create_event_image(purpose: EventImage::PURPOSE_GRID_TILE, grid_variant: EventImage::GRID_VARIANT_1X1)

    assert_difference -> { @event.event_images.count }, -1 do
      delete backend_event_event_image_url(@event, image), params: { status: "needs_review" }
    end

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
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
end
