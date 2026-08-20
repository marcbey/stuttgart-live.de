require "test_helper"

class Newsletter::RendererTest < ActiveSupport::TestCase
  test "renders selected events and news as html and text" do
    issue = newsletter_issue_with_items

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "Published Artist"
    assert_includes rendered.html, "Newsletter News"
    assert_includes rendered.text, "Published Artist"
    assert_includes rendered.text, "Newsletter News"
  end

  test "renders event image when one is available" do
    event = events(:published_one)
    event.import_event_images.create!(
      source: "easyticket",
      image_type: "image_url",
      image_url: "https://img.example.test/newsletter-event-1200x800.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche", created_by: users(:one))
    issue.newsletter_issue_items.create!(item: event, position: 1)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "<img"
    assert_match %r{<img[^>]+src="https://[^"]+"}, rendered.html
  end

  test "renders images in a compact left column" do
    event = events(:published_one)
    event.import_event_images.create!(
      source: "easyticket",
      image_type: "image_url",
      image_url: "https://img.example.test/newsletter-event-1200x800.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche", created_by: users(:one))
    issue.newsletter_issue_items.create!(item: event, position: 1)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "newsletter-item-media"
    assert_includes rendered.html, "newsletter-item-content"
    assert_includes rendered.html, 'width="112"'
    assert_includes rendered.html, "width:112px;max-width:112px"
  end

  test "renders intro line breaks in html newsletter" do
    issue = newsletter_issue_with_items
    issue.update!(intro: "Erste Zeile\nZweite Zeile mit **fett** und <Tag>")

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, 'Erste Zeile<br>Zweite Zeile mit <strong style="font-weight:700;">fett</strong> und &lt;Tag&gt;'
    assert_includes rendered.text, "Erste Zeile\nZweite Zeile mit **fett** und <Tag>"
  end

  test "renders intro heart markers in turquoise" do
    issue = newsletter_issue_with_items
    issue.update!(intro: "Persönlich für dich 💜")

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, 'Persönlich für dich <span style="color:#28c7c2;font-size:1.5em;line-height:0;">&#9829;</span>'
    assert_includes rendered.text, "Persönlich für dich 💜"
  end

  test "renders legal footer with unsubscribe and company details" do
    issue = newsletter_issue_with_items

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "Noch nicht genug?"
    assert_not_includes rendered.html, "Du willst mehr? Wir haben mehr!"
    assert_includes rendered.html, "Mehr Events entdecken"
    assert_includes rendered.html, "www.stuttgart-live.de"
    assert_includes rendered.html, "hier abmelden"
    assert_includes rendered.html, 'href="[[UNSUB_LINK_DE]]"'
    assert_includes rendered.html, "Datenschutz"
    assert_includes rendered.html, "Impressum"
    assert_includes rendered.html, "SKS Michael Russ GmbH"
    assert_includes rendered.html, "Charlottenplatz 17, 70173 Stuttgart"
    assert_includes rendered.html, "Dies ist eine automatisch generierte E-Mail."
    assert_includes rendered.html, "newsletter/instagram"
    assert_includes rendered.html, "newsletter/tiktok"
    assert_includes rendered.html, "newsletter/facebook"
    assert_includes rendered.text, "Mehr Events entdecken: https://example.com/"
    assert_includes rendered.text, "Newsletter abbestellen: [[UNSUB_LINK_DE]]"
    assert_includes rendered.text, "Dies ist eine automatisch generierte E-Mail."
    assert_includes rendered.text, "info@stuttgart-live.de"
  end

  test "renders a more understated Stuttgart Live branded layout" do
    issue = newsletter_issue_with_items

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "<span style=\"font-weight:800;\">STUTTGART</span>"
    assert_includes rendered.html, "<span style=\"font-weight:300;\">LIVE</span>"
    assert_not_includes rendered.html, "border-bottom:1px solid #d8d8d8;padding:12px 0"
    assert_not_includes rendered.html, "text-transform:uppercase;font-weight:800;\">Published Artist"
    assert_not_includes rendered.html, "#2bd7cf"
  end

  test "renders weekly mix header with logo and social icons" do
    event = create_published_event(
      slug: "newsletter-header-title-pop",
      title: "Header Title Pop",
      artist_name: "Header Title Artist",
      start_at: 1.week.from_now,
      genre: genres(:pop)
    )
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Stuttgart Live Wochenmix",
      header_title: "Alter ausgeblendeter Header",
      jump_menu_title: "Wähle dein Genre",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "newsletter/logo-sl"
    assert_includes rendered.html, "newsletter/instagram"
    assert_includes rendered.html, "newsletter/tiktok"
    assert_includes rendered.html, "newsletter/facebook"
    assert_includes rendered.html, "https://www.instagram.com/stuttgart.live.concert/"
    assert_includes rendered.html, "https://www.tiktok.com/@stuttgart.live.concert"
    assert_includes rendered.html, "https://www.facebook.com/stuttgartlive"
    assert_includes rendered.html, "Dein Stuttgart Live Wochenmix"
    assert_not_includes rendered.html, "Alter ausgeblendeter Header"
    assert_includes rendered.html, "Wähle dein Genre"
  end

  test "falls back to default header and jump menu titles when blank" do
    event = create_published_event(
      slug: "newsletter-default-title-pop",
      title: "Default Title Pop",
      artist_name: "Default Title Artist",
      start_at: 1.week.from_now,
      genre: genres(:pop)
    )
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "Dein Wochenmix"
    assert_includes rendered.html, "Für was interessierst du dich? Spring hinein ins Vergnügen :-)"
  end

  test "uses configured newsletter public url for media" do
    with_env("NEWSLETTER_PUBLIC_URL" => "https://newsletter-preview.example.test") do
      issue = NewsletterIssue.create!(
        title: "Wochenmix",
        subject: "Dein Wochenmix",
        layout_variant: "genre_weekly_mix",
        created_by: users(:one)
      )

      rendered = Newsletter::Renderer.call(issue)

      assert_includes rendered.html, "https://newsletter-preview.example.test/assets/newsletter/logo-sl"
      assert_not_includes rendered.html, "localhost"
    end
  end

  test "renders team tip after weekly jump menu and before genre sections" do
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 1.week.from_now)
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      intro: "Intro unter dem Kopfbereich.",
      team_tip_profile_key: "sarah-sandner",
      team_tip_name: "Sarah",
      team_tip_role: "Marketing",
      team_tip_text: "Sarah empfiehlt diese Woche besondere Konzertabende.",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_operator rendered.html.index("Dein Wochenmix"), :<, rendered.html.index("Intro unter dem Kopfbereich.")
    assert_operator rendered.html.index("Intro unter dem Kopfbereich."), :<, rendered.html.index("Sarahs Wochentipp")
    assert_operator rendered.html.index("Sarahs Wochentipp"), :<, rendered.html.index("Für was interessierst du dich? Spring hinein ins Vergnügen :-)")
    assert_operator rendered.html.index("Für was interessierst du dich? Spring hinein ins Vergnügen :-)"), :<, rendered.html.index('id="genre-pop-indie-singer-songwriter"')
    assert_not_includes rendered.html, "Sarahs heißer Tipp"
    assert_not_includes rendered.html, ">Wochentipp</p>"
    assert_includes rendered.html, "newsletter/team/sarah"
    assert_includes rendered.html, "border-radius:14px"
    assert_includes rendered.html, "&#8220;"
    assert_not_includes rendered.html, "&#8221;"
    assert_includes rendered.html, "Sarah empfiehlt diese Woche"
  end

  test "renders weekly mix news after team tip and before genre sections" do
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 1.week.from_now)
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      team_tip_name: "Sarah",
      team_tip_text: "Sarah empfiehlt diese Woche besondere Konzertabende.",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)
    issue.newsletter_issue_items.create!(item: blog_post, position: 2)

    rendered = Newsletter::Renderer.call(issue)

    assert_operator rendered.html.index("Sarahs Wochentipp"), :<, rendered.html.index("Für was interessierst du dich? Spring hinein ins Vergnügen :-)")
    assert_operator rendered.html.index("Für was interessierst du dich? Spring hinein ins Vergnügen :-)"), :<, rendered.html.index(">News</h2>")
    assert_operator rendered.html.index(">News</h2>"), :<, rendered.html.index('id="genre-pop-indie-singer-songwriter"')
    assert_includes rendered.text, "NEWS"
    assert_operator rendered.text.index("NEWS"), :<, rendered.text.index("POP")
  end

  test "renders weekly genre mix with jump menu and genre sections" do
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 1.week.from_now)
    event.import_event_images.create!(
      source: "easyticket",
      image_type: "image_url",
      image_url: "https://img.example.test/newsletter-card-1200x800.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, '<meta name="viewport" content="width=device-width, initial-scale=1">'
    assert_includes rendered.html, 'class="newsletter-shell"'
    assert_includes rendered.html, "width:640px;max-width:640px;border-collapse:collapse;background:#fff;margin:0 auto"
    assert_includes rendered.html, ".newsletter-shell"
    assert_includes rendered.html, "width: 100% !important"
    assert_includes rendered.html, "max-width: 100% !important"
    assert_includes rendered.html, "newsletter-weekly-header"
    assert_includes rendered.html, "margin:0 0 20px;padding:22px 24px 14px;background:#303636;color:#fff"
    assert_includes rendered.html, "margin:0;padding:0"
    assert_includes rendered.html, "@media only screen and (max-width: 680px)"
    assert_includes rendered.html, ".newsletter-weekly-header"
    assert_includes rendered.html, "padding-top: 15px !important"
    assert_includes rendered.html, "padding-bottom: 8px !important"
    assert_includes rendered.html, ".newsletter-logo-table"
    assert_includes rendered.html, ".newsletter-genre-link:hover"
    assert_includes rendered.html, ".newsletter-event-button:hover"
    assert_includes rendered.html, ".newsletter-card-row"
    assert_includes rendered.html, ".newsletter-mobile-item-row"
    assert_includes rendered.html, "display: table-row !important"
    assert_includes rendered.html, ".newsletter-header-social-icons"
    assert_includes rendered.html, ".newsletter-header-title"
    assert_includes rendered.html, ".newsletter-genre-jump-nav"
    assert_includes rendered.html, ".newsletter-genre-back-link"
    assert_includes rendered.html, ".newsletter-mobile-more-row"
    assert_includes rendered.html, ".newsletter-team-tip-desktop-row"
    assert_includes rendered.html, ".newsletter-team-tip-mobile-row"
    assert_includes rendered.html, ".newsletter-team-tip-mobile-content"
    assert_includes rendered.html, "<!--[if !mso]><!-->"
    assert_includes rendered.html, "<!--<![endif]-->"
    assert_includes rendered.html, "display: none !important"
    assert_includes rendered.html, "width: 104px !important"
    assert_includes rendered.html, "font-size: 17px !important"
    assert_includes rendered.html, "font-size: 18px !important"
    assert_includes rendered.html, "font-size: 24px !important"
    assert_includes rendered.html, "font-size: 13px !important"
    assert_includes rendered.html, "newsletter-footer-headline"
    assert_includes rendered.html, "newsletter-footer-cta"
    assert_includes rendered.html, "font-size: 22px !important"
    assert_includes rendered.html, "background: #303636"
    assert_includes rendered.html, "border-color: #303636"
    assert_includes rendered.html, "color: #ffffff"
    assert_includes rendered.html, "padding:5px 8px"
    assert_includes rendered.html, 'class="newsletter-genre-link"'
    assert_includes rendered.html, "border:1px solid #303636"
    assert_includes rendered.html, "background:#fff;color:#102223"
    assert_includes rendered.html, "font-size:12px;font-weight:bold;line-height:1.2"
    assert_includes rendered.html, "Für was interessierst du dich? Spring hinein ins Vergnügen :-)"
    assert_includes rendered.html, "Newsletter im Browser öffnen"
    assert_includes rendered.html, 'href="[[PERMALINK]]"'
    assert_includes rendered.html, 'id="newsletter-genres"'
    assert_includes rendered.html, 'name="newsletter-genres"'
    assert_includes rendered.html, 'style="display:block;font-size:1px;line-height:1px;mso-line-height-rule:exactly;color:transparent;text-decoration:none;">&nbsp;</a>'
    assert_includes rendered.html, 'href="#genre-pop-indie-singer-songwriter" target="_self"'
    assert_includes rendered.html, 'id="genre-pop-indie-singer-songwriter"'
    assert_includes rendered.html, '<h2 class="newsletter-section-heading-title"'
    assert_includes rendered.html, ">Pop</h2>"
    assert_includes rendered.html, 'href="#newsletter-genres" target="_self"'
    assert_includes rendered.html, "Zur Genre-Auswahl ↑"
    assert_includes rendered.html, ">Pop</h2>"
    assert_includes rendered.html, "Mehr Pop auf Stuttgart Live"
    assert_includes rendered.html, 'href="https://example.com/pop-indie-singer-songwriter"'
    assert_includes rendered.html, "newsletter-card-column"
    assert_includes rendered.html, "newsletter-card-row"
    assert_includes rendered.html, "newsletter-mobile-item-row"
    assert_includes rendered.html, "newsletter-mobile-image"
    assert_includes rendered.html, "newsletter-mobile-title"
    assert_includes rendered.html, "newsletter-intro"
    assert_includes rendered.html, "newsletter-jump-title"
    assert_includes rendered.html, "newsletter-section-heading-title"
    assert_includes rendered.html, "newsletter-footer-copy"
    assert_includes rendered.html, "newsletter-card-image"
    assert_includes rendered.html, 'class="newsletter-event-button"'
    assert_includes rendered.html, "font-size:9px;letter-spacing:.05em;color:#667071"
    assert_not_includes rendered.html, "font-size:9px;text-transform:uppercase;letter-spacing:.05em;color:#667071"
    assert_includes rendered.html, 'width="33.33%"'
    assert_includes rendered.html, "width:33.33%;vertical-align:top"
    assert_not_includes rendered.html, 'width="50%"'
    assert_includes rendered.html, 'width="176"'
    assert_includes rendered.html, 'height="176"'
    assert_includes rendered.html, 'width="104"'
    assert_includes rendered.html, 'height="104"'
    assert_includes rendered.html, "width:176px;max-width:100%;height:176px"
    assert_includes rendered.html, "width:104px;max-width:104px;height:104px"
    assert_includes rendered.html, "height:186px"
    assert_includes rendered.html, "height:72px"
    assert_includes rendered.html, "height:36px;vertical-align:top;padding-top:5px"
    assert_not_includes rendered.html, "object-fit:cover"
    assert_includes rendered.html, "border-radius:10px"
    assert_includes rendered.text, "POP"
  end

  test "limits mobile genre rows and links to the website genre page" do
    events = 3.times.map do |index|
      create_published_event(
        slug: "newsletter-mobile-pop-#{index}",
        title: "Mobile Pop #{index}",
        artist_name: "Mobile Pop Artist #{index}",
        start_at: (index + 1).days.from_now,
        genre: genres(:pop)
      )
    end
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    events.each.with_index(1) do |event, position|
      issue.newsletter_issue_items.create!(item: event, position:, section_key: genres(:pop).slug)
    end

    rendered = Newsletter::Renderer.call(issue)

    assert_equal 3, rendered.html.scan('class="newsletter-card-column"').length
    assert_equal 2, rendered.html.scan('class="newsletter-mobile-item-row"').length
    assert_includes rendered.html, "Mobile Pop Artist 0"
    assert_includes rendered.html, "Mobile Pop Artist 1"
    assert_not_includes rendered.html, "newsletter-mobile-title\" style=\"margin:0 0 5px;font-size:16px;line-height:1.18;font-weight:600;\">Mobile Pop Artist 2"
    assert_includes rendered.html, "Mehr Pop auf Stuttgart Live"
    assert_includes rendered.html, 'href="https://example.com/pop-indie-singer-songwriter"'
  end

  test "renders weekly genre mix card image variants with padded background" do
    event = create_published_event(
      slug: "newsletter-attached-image-pop",
      title: "Attached Image Pop",
      artist_name: "Attached Image Artist",
      start_at: 1.week.from_now,
      genre: genres(:pop)
    )
    event.promotion_banner_image.attach(create_uploaded_blob(filename: "newsletter-attached-image.png", width: 1200, height: 800))
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: event, position: 1, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "newsletter-card-image"
    assert_includes rendered.html, "Attached Image Artist"
  end

  test "renders weekly genre items by upcoming date within each genre" do
    later_event = create_published_event(
      slug: "newsletter-later-pop",
      title: "Later Pop",
      artist_name: "Later Pop Artist",
      start_at: 2.weeks.from_now,
      genre: genres(:pop)
    )
    sooner_event = create_published_event(
      slug: "newsletter-sooner-pop",
      title: "Sooner Pop",
      artist_name: "Sooner Pop Artist",
      start_at: 2.days.from_now,
      genre: genres(:pop)
    )
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: later_event, position: 1, section_key: genres(:pop).slug)
    issue.newsletter_issue_items.create!(item: sooner_event, position: 2, section_key: genres(:pop).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, "padding:12px 6px 18px 0"
    assert_includes rendered.html, "padding:12px 0 18px 6px"
    assert_operator rendered.html.index("Sooner Pop Artist"), :<, rendered.html.index("Later Pop Artist")
  end

  test "renders only the next upcoming date for event series in weekly genre mix" do
    series = EventSeries.create!(origin: "manual", name: "Mamma Mia")
    later_event = create_published_event(
      slug: "renderer-mamma-mia-later",
      title: "Mamma Mia",
      artist_name: "Mamma Mia",
      start_at: 2.weeks.from_now,
      genre: genres(:musical),
      event_series: series
    )
    sooner_event = create_published_event(
      slug: "renderer-mamma-mia-sooner",
      title: "Mamma Mia",
      artist_name: "Mamma Mia",
      start_at: 2.days.from_now,
      genre: genres(:musical),
      event_series: series
    )
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    issue.newsletter_issue_items.create!(item: later_event, position: 1, section_key: genres(:musical).slug)
    issue.newsletter_issue_items.create!(item: sooner_event, position: 2, section_key: genres(:musical).slug)

    rendered = Newsletter::Renderer.call(issue)

    assert_includes rendered.html, I18n.l(sooner_event.start_at, format: "%d.%m.%Y %H:%M Uhr")
    assert_not_includes rendered.html, I18n.l(later_event.start_at, format: "%d.%m.%Y %H:%M Uhr")
  end

  private

  def newsletter_issue_with_items
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche", created_by: users(:one))
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1)
    issue.newsletter_issue_items.create!(item: blog_post, position: 2)
    issue
  end

  def blog_post
    @blog_post ||= BlogPost.create!(
      title: "Newsletter News",
      teaser: "Ein kurzer Teaser.",
      body: "<div>Inhalt.</div>",
      author: users(:one),
      status: "published",
      published_at: 1.hour.ago,
      published_by: users(:one)
    )
  end

  def create_published_event(slug:, title:, artist_name:, start_at:, genre:, event_series: nil)
    Event.create!(
      slug:,
      source_fingerprint: "renderer::#{slug}",
      title:,
      artist_name:,
      normalized_artist_name: artist_name.parameterize,
      start_at:,
      venue_record: venues(:lka_longhorn),
      city: "Stuttgart",
      event_info: "Infos",
      status: "published",
      published_at: 1.day.ago,
      published_by: users(:one),
      completeness_score: 100,
      completeness_flags: [],
      primary_source: "test",
      auto_published: false,
      event_series:,
      event_series_assignment: event_series.present? ? "manual" : "auto"
    ).tap { |event| event.genres << genre }
  end

  def with_env(values)
    original_values = values.each_key.to_h { |key| [ key, ENV[key] ] }

    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
