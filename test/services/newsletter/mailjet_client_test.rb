require "test_helper"

class Newsletter::MailjetClientTest < ActiveSupport::TestCase
  setup do
    @client = Newsletter::MailjetClient.new(
      api_key: "api-key",
      secret_key: "secret-key",
      list_id: "123456"
    )
  end

  test "creates campaign draft with mailjet newsletter attributes" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    captured_attributes = nil

    with_app_config(:mailer_from, "redaktion@stuttgart-live.de") do
      with_mailjet_senders([
        mailjet_response("id" => 9876, "email" => "redaktion@stuttgart-live.de", "status" => "Active")
      ]) do
        handler = proc do |attributes|
          captured_attributes = attributes
          mailjet_response("ID" => 4242)
        end

        response = nil
        with_mailjet_create(Mailjet::Campaigndraft, handler) do
          response = @client.create_campaign_draft(issue:)
        end

        assert_equal 4242, response.fetch("ID")
      end
    end

    assert_equal "KW 33", captured_attributes.fetch(:title)
    assert_equal "Deine Woche", captured_attributes.fetch(:subject)
    assert_equal "html2", captured_attributes.fetch(:edit_mode)
    assert_equal 123456, captured_attributes.fetch("ContactsListID")
    assert_equal 9876, captured_attributes.fetch("Sender")
    assert_equal "redaktion@stuttgart-live.de", captured_attributes.fetch(:sender_email)
    assert_equal "Stuttgart Live", captured_attributes.fetch(:sender_name)
  end

  test "creates segmented campaign draft when issue has synced interest" do
    issue = NewsletterIssue.create!(
      title: "Pop KW 33",
      subject: "Pop Highlights",
      newsletter_interest: newsletter_interests(:pop)
    )
    captured_attributes = nil

    with_app_config(:mailjet_sender, "1234567") do
      handler = proc do |attributes|
        captured_attributes = attributes
        mailjet_response("ID" => 4242)
      end

      with_mailjet_create(Mailjet::Campaigndraft, handler) do
        @client.create_campaign_draft(issue:)
      end
    end

    assert_equal 1001, captured_attributes.fetch("SegmentationID")
  end

  test "subscribes contact with interest properties" do
    captured_attributes = nil

    handler = proc do |attributes|
      captured_attributes = attributes
      mailjet_response("ContactID" => "mailjet-contact-1")
    end

    with_mailjet_create(Mailjet::Contactslist_managecontact, handler) do
      @client.subscribe(
        email: "subscriber@example.com",
        properties: { "interest_pop_indie_singer_songwriter" => true }
      )
    end

    assert_equal "123456", captured_attributes.fetch(:id)
    assert_equal "addnoforce", captured_attributes.fetch(:action)
    assert_equal "subscriber@example.com", captured_attributes.fetch(:email)
    assert_equal({ "interest_pop_indie_singer_songwriter" => true }, captured_attributes.fetch(:properties))
  end

  test "creates contact metadata and segment for interest" do
    metadata_attributes = nil
    segment_attributes = nil

    with_mailjet_all(Mailjet::Contactmetadata, []) do
      with_mailjet_all(Mailjet::Contactfilter, []) do
        with_mailjet_create(Mailjet::Contactmetadata, proc { |attributes|
          metadata_attributes = attributes
          mailjet_response("ID" => 3131)
        }) do
          with_mailjet_create(Mailjet::Contactfilter, proc { |attributes|
            segment_attributes = attributes
            mailjet_response("ID" => 4242)
          }) do
            @client.ensure_contact_property(name: "interest_pop", data_type: "bool")
            @client.create_contact_segment(
              name: "stuttgart_live_newsletter_pop",
              expression: "(interest_pop=true)",
              description: "Pop"
            )
          end
        end
      end
    end

    assert_equal "interest_pop", metadata_attributes.fetch(:name)
    assert_equal "bool", metadata_attributes.fetch(:datatype)
    assert_equal "static", metadata_attributes.fetch(:namespace)
    assert_equal "stuttgart_live_newsletter_pop", segment_attributes.fetch(:name)
    assert_equal "(interest_pop=true)", segment_attributes.fetch(:expression)
  end

  test "extracts sender email and name from formatted mailer from value" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    captured_attributes = nil

    with_app_config(:mailer_from, "Stuttgart Live <newsletter@russ-live.de>") do
      with_mailjet_senders([
        mailjet_response("id" => 9876, "email" => "newsletter@russ-live.de", "status" => "Active")
      ]) do
        handler = proc do |attributes|
          captured_attributes = attributes
          mailjet_response("ID" => 4242)
        end

        with_mailjet_create(Mailjet::Campaigndraft, handler) do
          @client.create_campaign_draft(issue:)
        end
      end
    end

    assert_equal "newsletter@russ-live.de", captured_attributes.fetch(:sender_email)
    assert_equal "Stuttgart Live", captured_attributes.fetch(:sender_name)
    assert_equal "newsletter@russ-live.de", captured_attributes.fetch(:reply_email)
  end

  test "uses configured mailjet sender when present" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    captured_attributes = nil

    with_app_config(:mailer_from, "Stuttgart Live <newsletter@russ-live.de>") do
      with_app_config(:mailjet_sender, "1234567") do
        with_mailjet_senders([
          mailjet_response("id" => 1234567, "email" => "newsletter@russ-live.de", "status" => "Active")
        ]) do
          handler = proc do |attributes|
            captured_attributes = attributes
            mailjet_response("ID" => 4242)
          end

          with_mailjet_create(Mailjet::Campaigndraft, handler) do
            @client.create_campaign_draft(issue:)
          end
        end
      end
    end

    assert_equal 1234567, captured_attributes.fetch("Sender")
    assert_equal "newsletter@russ-live.de", captured_attributes.fetch(:sender_email)
  end

  test "ignores configured sender name and resolves active sender id" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    captured_attributes = nil

    with_app_config(:mailer_from, "Stuttgart Live <newsletter@russ-live.de>") do
      with_app_config(:mailjet_sender, "Stuttgart Live") do
        with_mailjet_senders([
          mailjet_response("id" => 9876, "email" => "newsletter@russ-live.de", "status" => "Active")
        ]) do
          handler = proc do |attributes|
            captured_attributes = attributes
            mailjet_response("ID" => 4242)
          end

          with_mailjet_create(Mailjet::Campaigndraft, handler) do
            @client.create_campaign_draft(issue:)
          end
        end
      end
    end

    assert_equal 9876, captured_attributes.fetch("Sender")
  end

  test "falls back to any active mailjet sender when configured sender address is not active" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    captured_attributes = nil

    with_app_config(:mailer_from, "Stuttgart Live <schopp3r@mailbox.org>") do
      with_mailjet_senders(lambda { |filters|
        if filters[:email].present?
          []
        else
          [ mailjet_response("id" => 6484988928, "email" => "stuttgart.live.concert@gmail.com", "status" => "Active") ]
        end
      }) do
        handler = proc do |attributes|
          captured_attributes = attributes
          mailjet_response("ID" => 4242)
        end

        with_mailjet_create(Mailjet::Campaigndraft, handler) do
          @client.create_campaign_draft(issue:)
        end
      end
    end

    assert_equal 6484988928, captured_attributes.fetch("Sender")
    assert_equal "stuttgart.live.concert@gmail.com", captured_attributes.fetch(:sender_email)
    assert_equal "stuttgart.live.concert@gmail.com", captured_attributes.fetch(:reply_email)
    assert_equal "Stuttgart Live", captured_attributes.fetch(:sender_name)
  end

  test "raises helpful error when no active sender exists in mailjet" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")

    with_app_config(:mailer_from, "Stuttgart Live <newsletter@russ-live.de>") do
      with_mailjet_senders([]) do
        error = assert_raises Newsletter::MailjetClient::Error do
          @client.create_campaign_draft(issue:)
        end

        assert_includes error.message, "No active Mailjet sender found in Mailjet"
      end
    end
  end

  test "wraps mailjet bad request errors" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Deine Woche")
    handler = proc { raise Mailjet::BadRequest.new("Bad request", nil) }

    error = with_app_config(:mailjet_sender, "1234567") do
      assert_raises Newsletter::MailjetClient::Error do
        with_mailjet_create(Mailjet::Campaigndraft, handler) do
          @client.create_campaign_draft(issue:)
        end
      end
    end

    assert_includes error.message, "Bad request"
  end

  test "updates campaign draft content" do
    captured_attributes = nil

    handler = proc do |attributes|
      captured_attributes = attributes
      mailjet_response("ID" => attributes.fetch(:id))
    end

    response = nil
    with_mailjet_create(Mailjet::Campaigndraft_detailcontent, handler) do
      response = @client.update_campaign_content(draft_id: 4242, html: "<h1>Hi</h1>", text: "Hi")
    end

    assert_equal 4242, response.fetch("ID")
    assert_equal 4242, captured_attributes.fetch(:id)
    assert_equal "<h1>Hi</h1>", captured_attributes.fetch(:html_part)
    assert_equal "Hi", captured_attributes.fetch(:text_part)
  end

  test "sends campaign test to fixed addresses" do
    captured_attributes = nil

    handler = proc do |attributes|
      captured_attributes = attributes
      mailjet_response("ID" => attributes.fetch(:id))
    end

    response = nil
    with_mailjet_create(Mailjet::Campaigndraft_test, handler) do
      response = @client.send_campaign_test(draft_id: 4242)
    end

    assert_equal 4242, response.fetch("ID")
    assert_equal [
      {
        "Email" => "katharinaschopper@russ-live.de",
        "Name" => "Katharina Schopper"
      },
      {
        "Email" => "mail@inorange.org",
        "Name" => "mail@inorange.org"
      }
    ], captured_attributes.fetch(:recipients)
  end

  test "sends campaign to configured test list" do
    captured_attributes = nil

    handler = proc do |attributes|
      captured_attributes = attributes
      mailjet_response("ID" => attributes.fetch(:id))
    end

    response = nil
    with_mailjet_create(Mailjet::Campaigndraft_send, handler) do
      response = @client.send_campaign_to_test_list(draft_id: 4242)
    end

    assert_equal 4242, response.fetch("ID")
    assert_equal 4242, captured_attributes.fetch(:id)
  end

  test "sends transactional email through mailjet send api" do
    captured_attributes = nil

    with_app_config(:mailer_from, "Stuttgart Live <schopp3r@mailbox.org>") do
      with_mailjet_senders(lambda { |filters|
        if filters[:email].present?
          []
        else
          [ mailjet_response("id" => 6484988928, "email" => "stuttgart.live.concert@gmail.com", "status" => "Active") ]
        end
      }) do
        with_mailjet_create(Mailjet::Send, proc { |attributes|
          captured_attributes = attributes
          mailjet_response("Messages" => [ { "Status" => "success" } ])
        }) do
          @client.send_transactional_email(
            to: "confirm@example.com",
            subject: "Bitte bestätigen",
            html: "<p>Hallo</p>",
            text: "Hallo"
          )
        end
      end
    end

    message = captured_attributes.fetch(:messages).first
    assert_equal(
      { "Email" => "stuttgart.live.concert@gmail.com", "Name" => "Stuttgart Live" },
      message.fetch("From")
    )
    assert_equal [ { "Email" => "confirm@example.com" } ], message.fetch("To")
    assert_equal "Bitte bestätigen", message.fetch("Subject")
    assert_equal "<p>Hallo</p>", message.fetch("HTMLPart")
    assert_equal "Hallo", message.fetch("TextPart")
  end

  private

  def with_mailjet_create(resource, handler)
    original_method = resource.method(:create)
    resource.singleton_class.send(:define_method, :create) { |attributes| handler.call(attributes) }
    yield
  ensure
    resource.singleton_class.send(:define_method, :create, original_method)
  end

  def with_mailjet_all(resource, responses)
    original_method = resource.method(:all)
    resource.singleton_class.send(:define_method, :all) { |*| responses }
    yield
  ensure
    resource.singleton_class.send(:define_method, :all, original_method)
  end

  def with_mailjet_senders(senders)
    original_method = Mailjet::Sender.method(:all)
    Mailjet::Sender.singleton_class.send(:define_method, :all) do |filters|
      senders.respond_to?(:call) ? senders.call(filters) : senders
    end
    yield
  ensure
    Mailjet::Sender.singleton_class.send(:define_method, :all, original_method)
  end

  def with_app_config(method_name, value)
    original_method = AppConfig.method(method_name)
    AppConfig.singleton_class.send(:define_method, method_name) { value }
    yield
  ensure
    AppConfig.singleton_class.send(:define_method, method_name, original_method)
  end

  def mailjet_response(attributes)
    Struct.new(:attributes).new(attributes)
  end
end
