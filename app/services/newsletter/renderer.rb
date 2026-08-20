module Newsletter
  class Renderer
    include ActionView::Helpers::SanitizeHelper
    include ActionView::Helpers::TextHelper
    include Rails.application.routes.url_helpers

    Result = Data.define(:html, :text)

    def self.call(issue)
      new(issue).call
    end

    def initialize(issue)
      @issue = issue
    end

    def call
      Result.new(html: render_html, text: render_text)
    end

    private

    attr_reader :issue

    IMAGE_WIDTH = 112
    GENRE_CARD_COLUMNS = 3
    CARD_IMAGE_WIDTH = 176
    CARD_IMAGE_HEIGHT = 176
    MOBILE_CARD_IMAGE_WIDTH = 104
    MOBILE_CARD_IMAGE_HEIGHT = 104
    CARD_IMAGE_VARIANT_WIDTH = CARD_IMAGE_WIDTH * 2
    CARD_IMAGE_VARIANT_HEIGHT = CARD_IMAGE_HEIGHT * 2
    IMAGE_QUALITY = 82
    MOBILE_GENRE_ITEM_LIMIT = 2
    NEWSLETTER_LOGO_PATH = "newsletter/logo-sl.png"
    GENRE_NAV_ANCHOR = "newsletter-genres"
    MAILJET_PERMALINK_PLACEHOLDER = "[[PERMALINK]]"
    HEART_MARKERS = [ "\u{1FA75}", "\u{1F49C}", "\u{1F49A}" ].freeze
    TURQUOISE_HEART_HTML = '<span style="color:#28c7c2;font-size:1.5em;line-height:0;">&#9829;</span>'
    SOCIAL_LINKS = [
      {
        name: "Instagram",
        url: "https://www.instagram.com/stuttgart.live.concert/",
        image_path: "newsletter/instagram.png"
      },
      {
        name: "TikTok",
        url: "https://www.tiktok.com/@stuttgart.live.concert",
        image_path: "newsletter/tiktok.png"
      },
      {
        name: "Facebook",
        url: "https://www.facebook.com/stuttgartlive",
        image_path: "newsletter/facebook.png"
      }
    ].freeze

    def render_html
      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              .newsletter-genre-link:hover {
                background: #303636 !important;
                border-color: #303636 !important;
                color: #ffffff !important;
              }

              .newsletter-event-button:hover {
                background: #303636 !important;
                border-color: #303636 !important;
                color: #ffffff !important;
              }

              @media only screen and (max-width: 680px) {
                .newsletter-item-media,
                .newsletter-item-spacer,
                .newsletter-item-content,
                .newsletter-card-column,
                .newsletter-card-row {
                  display: none !important;
                }

                .newsletter-header-social-icons {
                  display: none !important;
                }

                .newsletter-header-title {
                  display: none !important;
                }

                .newsletter-genre-jump-nav,
                .newsletter-genre-back-link {
                  display: none !important;
                  max-height: 0 !important;
                  overflow: hidden !important;
                }

                .newsletter-weekly-header {
                  padding-top: 15px !important;
                  padding-bottom: 8px !important;
                  margin-bottom: 20px !important;
                }

                .newsletter-logo-table {
                  margin-bottom: 0 !important;
                }

                .newsletter-shell {
                  width: 100% !important;
                  max-width: 100% !important;
                }

                .newsletter-mobile-item-row {
                  display: table-row !important;
                  max-height: none !important;
                  overflow: visible !important;
                  mso-hide: none !important;
                }

                .newsletter-mobile-more-row {
                  display: table-row !important;
                  max-height: none !important;
                  overflow: visible !important;
                  mso-hide: none !important;
                }

                .newsletter-mobile-image-cell {
                  width: 104px !important;
                  padding: 12px 12px 12px 0 !important;
                }

                .newsletter-mobile-image {
                  width: 104px !important;
                  max-width: 104px !important;
                  height: 104px !important;
                }

                .newsletter-mobile-content-cell {
                  padding: 12px 0 !important;
                }

                .newsletter-mobile-label {
                  font-size: 12px !important;
                  line-height: 1.25 !important;
                }

                .newsletter-mobile-title {
                  font-size: 18px !important;
                  line-height: 1.18 !important;
                }

                .newsletter-mobile-teaser {
                  font-size: 15px !important;
                  line-height: 1.35 !important;
                }

                .newsletter-mobile-button-wrap {
                  padding-top: 8px !important;
                }

                .newsletter-event-button {
                  font-size: 14px !important;
                  line-height: 1.2 !important;
                  padding: 8px 13px !important;
                }

                .newsletter-intro {
                  font-size: 17px !important;
                  line-height: 1.48 !important;
                }

                .newsletter-team-tip-title {
                  font-size: 19px !important;
                  line-height: 1.18 !important;
                }

                .newsletter-team-tip-text {
                  font-size: 15px !important;
                  line-height: 1.42 !important;
                }

                .newsletter-team-tip-desktop-row {
                  display: none !important;
                }

                .newsletter-team-tip-mobile-row {
                  display: table-row !important;
                  max-height: none !important;
                  overflow: visible !important;
                  mso-hide: none !important;
                }

                .newsletter-team-tip-mobile-content {
                  text-align: left !important;
                }

                .newsletter-team-tip-mobile-avatar-wrap {
                  padding-bottom: 12px !important;
                }

                .newsletter-jump-title {
                  font-size: 17px !important;
                  line-height: 1.3 !important;
                }

                .newsletter-genre-link {
                  font-size: 13px !important;
                  line-height: 1.2 !important;
                  padding: 6px 9px !important;
                }

                .newsletter-section-heading-title {
                  font-size: 24px !important;
                  line-height: 1.1 !important;
                }

                .newsletter-footer-copy,
                .newsletter-footer-link-row,
                .newsletter-footer-address,
                .newsletter-footer-auto-note {
                  font-size: 13px !important;
                  line-height: 1.45 !important;
                }

                .newsletter-footer-headline {
                  font-size: 22px !important;
                  line-height: 1.2 !important;
                }

                .newsletter-footer-teaser {
                  font-size: 17px !important;
                  line-height: 1.35 !important;
                }

                .newsletter-footer-cta {
                  font-size: 17px !important;
                  line-height: 1.2 !important;
                  padding: 13px 18px !important;
                }

                .newsletter-footer-cta-table,
                .newsletter-footer-legal-table {
                  width: 100% !important;
                }

                .newsletter-item-media,
                .newsletter-item-spacer,
                .newsletter-item-content {
                  display: block !important;
                  width: 100% !important;
                }

                .newsletter-item-spacer,
                .newsletter-card-spacer {
                  height: 14px !important;
                }

                .newsletter-item-image {
                  width: 100% !important;
                  max-width: 100% !important;
                  height: auto !important;
                }
              }
            </style>
          </head>
          <body style="margin:0;background:#f6f6f3;color:#102223;font-family:Arial,sans-serif;">
            <div style="display:none;max-height:0;overflow:hidden;">#{escape(issue.preheader.to_s)}</div>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;border-collapse:collapse;background:#f6f6f3;margin:0;padding:0;">
              <tr>
                <td align="center" style="padding:0;">
                  <table class="newsletter-shell" role="presentation" width="640" cellspacing="0" cellpadding="0" border="0" style="width:640px;max-width:640px;border-collapse:collapse;background:#fff;margin:0 auto;">
                    <tr>
                      <td style="padding:0;">
                        #{browser_view_link_html}
                        #{opening_html}
                        <div style="padding:0 24px 24px;">
                          #{items_html}
                          #{footer_html}
                        </div>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    end

    def render_text
      parts = [ "STUTTGART LIVE", issue.subject, issue.intro.to_s.strip.presence, text_items, footer_text ]
      parts.compact.join("\n\n")
    end

    def opening_html
      return weekly_mix_header_html if issue.genre_weekly_mix?

      <<~HTML
        <div style="padding:24px 24px 0;">
          #{header_html}
          #{intro_html}
        </div>
      HTML
    end

    def weekly_mix_header_html
      <<~HTML
        <section class="newsletter-weekly-header" style="margin:0 0 20px;padding:22px 24px 14px;background:#303636;color:#fff;">
          #{header_html(dark: true)}
        </section>
      HTML
    end

    def header_html(dark: false)
      heading_color = dark ? "#fff" : "#102223"
      header_margin = dark ? "0" : "0 0 20px"

      <<~HTML
        <header style="margin:#{header_margin};padding:0;">
          #{brand_logo_html(dark: dark, heading_color: heading_color)}
          #{header_title_html(dark: dark, heading_color: heading_color)}
        </header>
      HTML
    end

    def header_title_html(dark:, heading_color:)
      unless dark
        return %(<h1 class="newsletter-header-title" style="margin:0;font-size:24px;line-height:1.15;font-weight:600;color:#{heading_color};">#{escape(issue.display_header_title)}</h1>)
      end

      %(<h1 class="newsletter-header-title" style="margin:0;font-size:20px;line-height:1.1;font-weight:300;text-transform:uppercase;letter-spacing:.08em;color:#dbe0df;">#{escape(issue.display_header_title)}</h1>)
    end

    def brand_logo_html(dark:, heading_color:)
      return text_logo_html(heading_color) unless dark

      logo_url = absolute_media_url(ActionController::Base.helpers.asset_path(NEWSLETTER_LOGO_PATH))
      return text_logo_html(heading_color) if logo_url.blank?

      <<~HTML
        <table class="newsletter-logo-table" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:0 0 10px;border-collapse:collapse;">
          <tr>
            <td align="left" valign="middle" style="padding:0;">
              <img src="#{logo_url}" width="260" alt="Stuttgart Live" style="display:block;width:260px;max-width:100%;height:auto;border:0;outline:none;text-decoration:none;">
            </td>
            <td class="newsletter-header-social-icons" align="right" valign="middle" style="padding:0;">
              #{social_icons_html}
            </td>
          </tr>
        </table>
      HTML
    end

    def social_icons_html
      SOCIAL_LINKS.map do |link|
        image_url = absolute_media_url(ActionController::Base.helpers.asset_path(link.fetch(:image_path)))
        next if image_url.blank?

        <<~HTML
          <a href="#{escape(link.fetch(:url))}" target="_blank" rel="noopener" style="display:inline-block;margin-left:7px;text-decoration:none;">
            <img src="#{escape(image_url)}" width="28" height="28" alt="#{escape(link.fetch(:name))}" style="display:block;width:28px;height:28px;border:0;outline:none;text-decoration:none;">
          </a>
        HTML
      end.compact.join
    end

    def text_logo_html(color)
      <<~HTML
        <p style="margin:0 0 10px;font-size:30px;line-height:1;letter-spacing:.03em;text-transform:uppercase;color:#{color};">
          <span style="font-weight:800;">STUTTGART</span><span style="font-weight:300;">LIVE</span>
        </p>
      HTML
    end

    def intro_html(dark: false)
      return "" if issue.intro.blank?

      color = dark ? "#fff" : "#263334"

      %(<p class="newsletter-intro" style="font-size:15px;line-height:1.45;margin:0 0 20px;color:#{color};">#{escape_with_line_breaks(issue.intro)}</p>)
    end

    def team_tip_html
      return "" unless issue.team_tip?

      <<~HTML
        <aside style="margin:12px 0 24px;padding:18px;border:1px solid #d4d7d4;border-radius:14px;background:#fbfbfa;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
            <tr class="newsletter-team-tip-desktop-row">
              <td width="70" valign="top" style="width:70px;vertical-align:top;">
                #{team_tip_avatar_html}
              </td>
              <td width="16" style="width:16px;font-size:1px;line-height:1px;">&nbsp;</td>
              <td valign="top" style="vertical-align:top;">
                <h2 class="newsletter-team-tip-title" style="margin:0 0 8px;font-size:18px;line-height:1.15;font-weight:600;">#{escape(issue.team_tip_name)}s Wochentipp</h2>
                #{team_tip_quote_html}
              </td>
          </tr>
            <!--[if !mso]><!-->
              <tr class="newsletter-team-tip-mobile-row" style="display:none;mso-hide:all;max-height:0;overflow:hidden;">
                <td colspan="3" align="center" style="padding:0;">
                  <div class="newsletter-team-tip-mobile-avatar-wrap" style="padding-bottom:12px;">
                    #{team_tip_avatar_html}
                  </div>
                  <div class="newsletter-team-tip-mobile-content" style="text-align:left;">
                    <h2 class="newsletter-team-tip-title" style="margin:0 0 8px;font-size:18px;line-height:1.15;font-weight:600;">#{escape(issue.team_tip_name)}s Wochentipp</h2>
                    #{team_tip_quote_html}
                  </div>
                </td>
              </tr>
            <!--<![endif]-->
        </table>
        </aside>
      HTML
    end

    def items_html
      return genre_weekly_mix_items_html if issue.genre_weekly_mix?

      [
        team_tip_html,
        issue.newsletter_issue_items.map { |item| item_html(item) }.join("\n")
      ].join("\n")
    end

    def genre_weekly_mix_items_html
      grouped_sections = genre_weekly_mix_sections
      news_items = genre_weekly_mix_news_items

      [
        intro_html,
        team_tip_html,
        (genre_jump_nav_html(grouped_sections) if grouped_sections.any?),
        news_section_html(news_items),
        grouped_sections.map { |section| genre_section_html(section) }.join("\n")
      ].compact_blank.join("\n")
    end

    def news_section_html(items)
      return "" if items.blank?

      <<~HTML
        <section style="padding-top:18px;">
          <h2 style="margin:0 0 8px;font-size:20px;line-height:1.1;font-weight:700;border-bottom:1px solid #111;padding-bottom:7px;">News</h2>
          #{items.map { |item| item_html(item) }.join("\n")}
        </section>
      HTML
    end

    def genre_jump_nav_html(sections, dark: false)
      question_color = dark ? "#fff" : "#263334"
      link_color = dark ? "#fff" : "#102223"
      link_border = dark ? "#7d8585" : "#303636"
      link_background = dark ? "#3d4545" : "#fff"

      links = sections.map do |section|
        <<~HTML
          <a class="newsletter-genre-link" href="##{genre_anchor(section[:group])}" target="_self" style="display:inline-block;margin:0 4px 5px 0;padding:5px 8px;border:1px solid #{link_border};border-radius:999px;background:#{link_background};color:#{link_color};text-decoration:none;font-size:12px;font-weight:bold;line-height:1.2;">#{escape(section[:group].label)}</a>
        HTML
      end.join

      <<~HTML
        <nav class="newsletter-genre-jump-nav" aria-label="Genres im Newsletter" style="margin:0;">
          #{email_anchor_html(GENRE_NAV_ANCHOR)}
          <p class="newsletter-jump-title" style="margin:0 0 9px;font-size:14px;line-height:1.25;font-weight:600;color:#{question_color};">
            #{escape(issue.display_jump_menu_title)}
          </p>
          <div>
            #{links}
          </div>
        </nav>
      HTML
    end

    def genre_section_html(section)
      anchor = genre_anchor(section[:group])

      <<~HTML
        <section style="padding-top:18px;">
          #{email_anchor_html(anchor)}
          <h2 class="newsletter-section-heading-title" style="margin:0 0 8px;font-size:20px;line-height:1.1;font-weight:700;border-bottom:1px solid #111;padding-bottom:7px;">#{escape(section[:group].label)}</h2>
          #{genre_item_cards_html(section)}
          #{genre_back_to_nav_html}
        </section>
      HTML
    end

    def genre_back_to_nav_html
      <<~HTML
        <p class="newsletter-genre-back-link" style="margin:4px 0 0;text-align:right;font-size:12px;line-height:1.3;">
          <a href="##{GENRE_NAV_ANCHOR}" target="_self" style="color:#102223;text-decoration:underline;font-weight:bold;">Zur Genre-Auswahl ↑</a>
        </p>
      HTML
    end

    def email_anchor_html(anchor)
      %(<a id="#{anchor}" name="#{anchor}" style="display:block;font-size:1px;line-height:1px;mso-line-height-rule:exactly;color:transparent;text-decoration:none;">&nbsp;</a>)
    end

    def genre_item_cards_html(section)
      items = section[:items]
      rows = items.each_slice(GENRE_CARD_COLUMNS).map do |row_items|
        <<~HTML
          <tr class="newsletter-card-row">
            #{row_items.map.with_index { |item, index| genre_item_card_column_html(item, index) }.join}
            #{empty_genre_item_card_columns_html(row_items.length)}
          </tr>
        HTML
      end
      mobile_rows = items.first(MOBILE_GENRE_ITEM_LIMIT).map { |item| genre_item_mobile_row_html(item) }

      <<~HTML
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
          #{rows.join}
          #{mobile_rows.join}
          #{genre_mobile_more_link_row_html(section)}
        </table>
      HTML
    end

    def browser_view_link_html
      <<~HTML
        <p style="margin:0;padding:10px 24px 8px;text-align:right;font-size:11px;line-height:1.3;color:#596364;">
          <a href="#{MAILJET_PERMALINK_PLACEHOLDER}" target="_blank" rel="noopener" style="color:#596364;text-decoration:underline;">Newsletter im Browser öffnen</a>
        </p>
      HTML
    end

    def genre_item_card_column_html(item, index)
      padding = genre_item_card_column_padding(index)

      <<~HTML
        <td class="newsletter-card-column" width="33.33%" valign="top" style="width:33.33%;vertical-align:top;padding:#{padding};">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;height:100%;">
            <tr>
              <td height="186" valign="top" style="height:186px;vertical-align:top;">
                #{genre_item_card_image_html(item)}
              </td>
            </tr>
            <tr>
              <td height="72" valign="top" style="height:72px;vertical-align:top;">
                #{genre_item_card_content_html(item)}
              </td>
            </tr>
            <tr>
              <td height="36" valign="top" style="height:36px;vertical-align:top;padding-top:5px;">
                #{genre_item_card_button_html(item)}
              </td>
            </tr>
          </table>
        </td>
      HTML
    end

    def empty_genre_item_card_columns_html(items_count)
      empty_count = GENRE_CARD_COLUMNS - items_count
      return "" unless empty_count.positive?

      (items_count...GENRE_CARD_COLUMNS).map do |index|
        <<~HTML
          <td class="newsletter-card-column newsletter-card-empty" width="33.33%" style="width:33.33%;padding:#{genre_item_card_column_padding(index)};">&nbsp;</td>
        HTML
      end.join
    end

    def genre_item_mobile_row_html(item)
      <<~HTML
        <!--[if !mso]><!-->
          <tr class="newsletter-mobile-item-row" style="display:none;mso-hide:all;max-height:0;overflow:hidden;">
            <td colspan="#{GENRE_CARD_COLUMNS}" style="padding:0;border-bottom:1px solid #eceeee;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;">
                <tr>
                  #{genre_item_mobile_image_cell_html(item)}
                  <td class="newsletter-mobile-content-cell" valign="top" style="vertical-align:top;padding:12px 0;">
                    #{genre_item_mobile_content_html(item)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        <!--<![endif]-->
      HTML
    end

    def genre_mobile_more_link_row_html(section)
      group = section.fetch(:group)

      <<~HTML
        <!--[if !mso]><!-->
          <tr class="newsletter-mobile-more-row" style="display:none;mso-hide:all;max-height:0;overflow:hidden;">
            <td colspan="#{GENRE_CARD_COLUMNS}" style="padding:14px 0 22px;">
              <a href="#{escape(genre_lane_url(group.slug, **route_url_options))}" target="_blank" rel="noopener" style="display:inline-block;color:#102223;text-decoration:underline;font-size:14px;line-height:1.3;font-weight:bold;">Mehr #{escape(group.label)} auf Stuttgart Live</a>
            </td>
          </tr>
        <!--<![endif]-->
      HTML
    end

    def genre_item_mobile_image_cell_html(item)
      image_url = item_image_url(item)
      return "" if image_url.blank?

      <<~HTML
        <td class="newsletter-mobile-image-cell" width="#{MOBILE_CARD_IMAGE_WIDTH}" valign="top" style="width:#{MOBILE_CARD_IMAGE_WIDTH}px;vertical-align:top;padding:12px 12px 12px 0;">
          <a href="#{escape(item_url(item))}" style="display:block;text-decoration:none;">
            <img class="newsletter-mobile-image" src="#{escape(image_url)}" width="#{MOBILE_CARD_IMAGE_WIDTH}" height="#{MOBILE_CARD_IMAGE_HEIGHT}" alt="#{escape(item.display_headline)}" style="display:block;width:#{MOBILE_CARD_IMAGE_WIDTH}px;max-width:#{MOBILE_CARD_IMAGE_WIDTH}px;height:#{MOBILE_CARD_IMAGE_HEIGHT}px;border:0;border-radius:8px;">
          </a>
        </td>
      HTML
    end

    def genre_item_mobile_content_html(item)
      <<~HTML
        <p class="newsletter-mobile-label" style="margin:0 0 4px;font-size:11px;line-height:1.25;color:#667071;">#{escape(item_label(item))}</p>
        <h3 class="newsletter-mobile-title" style="margin:0 0 5px;font-size:16px;line-height:1.18;font-weight:600;">#{escape(item.display_headline)}</h3>
        <p class="newsletter-mobile-teaser" style="margin:0;font-size:13px;line-height:1.3;color:#263334;">#{escape(item.display_teaser)}</p>
        <div class="newsletter-mobile-button-wrap" style="padding-top:8px;">
          #{genre_item_card_button_html(item)}
        </div>
      HTML
    end

    def genre_item_card_column_padding(index)
      case index
      when 0 then "12px 6px 18px 0"
      when GENRE_CARD_COLUMNS - 1 then "12px 0 18px 6px"
      else "12px 3px 18px"
      end
    end

    def genre_item_card_image_html(item)
      image_url = item_image_url(item)
      return "" if image_url.blank?

      <<~HTML
        <a href="#{escape(item_url(item))}" style="display:block;margin:0 0 10px;text-decoration:none;">
          <img class="newsletter-card-image" src="#{escape(image_url)}" width="#{CARD_IMAGE_WIDTH}" height="#{CARD_IMAGE_HEIGHT}" alt="#{escape(item.display_headline)}" style="display:block;width:#{CARD_IMAGE_WIDTH}px;max-width:100%;height:#{CARD_IMAGE_HEIGHT}px;border:0;border-radius:10px;">
        </a>
      HTML
    end

    def genre_item_card_content_html(item)
      <<~HTML
        <p style="margin:0 0 5px;font-size:9px;letter-spacing:.05em;color:#667071;">#{escape(item_label(item))}</p>
        <h3 style="margin:0 0 5px;font-size:14px;line-height:1.18;font-weight:600;">#{escape(item.display_headline)}</h3>
        <p style="margin:0;font-size:11px;line-height:1.3;color:#263334;">#{escape(item.display_teaser)}</p>
      HTML
    end

    def genre_item_card_button_html(item)
      <<~HTML
        <a class="newsletter-event-button" href="#{escape(item_url(item))}" style="display:inline-block;border:1px solid #111;color:#102223;font-size:12px;font-weight:bold;text-decoration:none;border-radius:999px;padding:7px 11px;">#{escape(item.display_cta_label)}</a>
      HTML
    end

    def item_html(item)
      image_url = item_image_url(item)
      return item_html_without_image(item) if image_url.blank?

      <<~HTML
        <article style="padding:12px 0;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
            <tr>
              <td class="newsletter-item-media" width="#{IMAGE_WIDTH}" valign="top" style="width:#{IMAGE_WIDTH}px;vertical-align:top;">
                #{image_html(item, image_url)}
              </td>
              <td class="newsletter-item-spacer" width="14" style="width:14px;font-size:1px;line-height:1px;">&nbsp;</td>
              <td class="newsletter-item-content" valign="top" style="vertical-align:top;">
                #{item_content_html(item)}
              </td>
            </tr>
          </table>
        </article>
      HTML
    end

    def item_html_without_image(item)
      <<~HTML
        <article style="padding:12px 0;">
          #{item_content_html(item)}
        </article>
      HTML
    end

    def item_content_html(item)
      <<~HTML
        <p style="margin:0 0 5px;font-size:11px;letter-spacing:.06em;color:#667071;">#{escape(item_label(item))}</p>
        <h3 style="margin:0 0 6px;font-size:18px;line-height:1.15;font-weight:600;">#{escape(item.display_headline)}</h3>
        <p style="margin:0 0 10px;font-size:14px;line-height:1.4;color:#263334;">#{escape(item.display_teaser)}</p>
        <a class="newsletter-event-button" href="#{escape(item_url(item))}" style="display:inline-block;border:1px solid #111;color:#102223;font-size:12px;font-weight:bold;text-decoration:none;border-radius:999px;padding:8px 12px;">#{escape(item.display_cta_label)}</a>
      HTML
    end

    def escape_with_line_breaks(text)
      escaped_text = escape(text).to_s
      escaped_text.gsub!(/\*\*(.+?)\*\*/, '<strong style="font-weight:700;">\1</strong>')
      HEART_MARKERS.each { |heart| escaped_text.gsub!(heart, TURQUOISE_HEART_HTML) }
      escaped_text.gsub(/\r\n?|\n/, "<br>")
    end

    def image_html(item, url)
      <<~HTML
        <a href="#{escape(item_url(item))}" style="display:block;text-decoration:none;">
          <img class="newsletter-item-image" src="#{escape(url)}" width="#{IMAGE_WIDTH}" alt="#{escape(item.display_headline)}" style="display:block;width:#{IMAGE_WIDTH}px;max-width:#{IMAGE_WIDTH}px;height:auto;border:0;">
        </a>
      HTML
    end

    def team_tip_avatar_html
      image_url = team_tip_image_url
      return team_tip_initials_html if image_url.blank?

      <<~HTML
        <img src="#{escape(image_url)}" width="70" height="70" alt="#{escape(issue.team_tip_name)}" style="display:block;width:70px;height:70px;border-radius:50%;object-fit:cover;border:0;">
      HTML
    end

    def team_tip_initials_html
      <<~HTML
        <div style="width:70px;height:70px;border-radius:50%;background:#111;color:#fff;font-size:18px;line-height:70px;text-align:center;font-weight:bold;">#{escape(issue.team_tip_initials)}</div>
      HTML
    end

    def team_tip_quote_html
      <<~HTML
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;">
          <tr>
            <td width="26" valign="top" style="width:26px;vertical-align:top;color:#111;font-size:44px;line-height:36px;font-family:Georgia,serif;">&#8220;</td>
            <td valign="top" style="vertical-align:top;">
              <p class="newsletter-team-tip-text" style="margin:0;font-size:14px;line-height:1.42;color:#263334;">#{escape(issue.team_tip_text)}</p>
            </td>
          </tr>
        </table>
      HTML
    end

    def team_tip_image_url
      issue.team_tip_image_url.presence || team_tip_profile_image_url
    end

    def team_tip_profile_image_url
      profile = Newsletter::TeamTipProfiles.find(issue.team_tip_profile_key)
      return if profile&.image_path.blank?

      absolute_media_url(ActionController::Base.helpers.asset_path(profile.image_path))
    end

    def text_items
      return genre_weekly_mix_text_items if issue.genre_weekly_mix?

      issue.newsletter_issue_items.map do |item|
        [ item_label(item), item.display_headline, item.display_teaser, item_url(item) ].join("\n")
      end.join("\n\n")
    end

    def genre_weekly_mix_text_items
      parts = []
      news_items = genre_weekly_mix_news_items
      parts << [ "NEWS", text_for_items(news_items) ].join("\n\n") if news_items.any?

      parts.concat(genre_weekly_mix_sections.map do |section|
        [
          section[:group].label.upcase,
          text_for_items(section[:items])
        ].join("\n\n")
      end)

      parts.join("\n\n")
    end

    def text_for_items(items)
      items.map do |item|
        [ item_label(item), item.display_headline, item.display_teaser, item_url(item) ].join("\n")
      end.join("\n\n")
    end

    def footer_html
      <<~HTML
        <footer style="margin:32px 0 0;padding:28px 0 0;border-top:1px solid #cfd3d1;color:#596364;text-align:center;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;border-collapse:collapse;">
            <tr>
              <td align="center" style="padding:0 22px 20px;">
                <p class="newsletter-footer-headline" style="margin:0 0 8px;font-size:25px;line-height:1.2;font-weight:700;color:#263334;">Noch nicht genug?</p>
                <p class="newsletter-footer-teaser" style="margin:0;font-size:18px;line-height:1.35;color:#263334;">
                  Auf unserer <strong style="font-weight:700;">Website</strong> warten noch jede Menge Highlights auf dich.
                </p>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:0 0 24px;">
                <table class="newsletter-footer-cta-table" role="presentation" width="430" cellspacing="0" cellpadding="0" border="0" style="width:430px;max-width:100%;border-collapse:collapse;">
                  <tr>
                    <td align="center" bgcolor="#28c7c2" style="border-radius:6px;background:#28c7c2;">
                      <a class="newsletter-footer-cta" href="#{escape(website_url)}" target="_blank" rel="noopener" style="display:block;background:#28c7c2;color:#102223;text-decoration:none;font-size:18px;line-height:1.2;font-weight:700;border-radius:6px;padding:15px 22px;">Mehr Events entdecken</a>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:0 0 26px;">
                <a href="#{escape(website_url)}" target="_blank" rel="noopener" style="color:#102223;text-decoration:underline;font-size:15px;line-height:1.4;">www.stuttgart-live.de</a>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:20px 0;border-top:1px solid #cfd3d1;border-bottom:1px solid #cfd3d1;">
                #{footer_social_icons_html}
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:22px 0 0;color:#a5adad;">
                <table class="newsletter-footer-legal-table" role="presentation" width="540" cellspacing="0" cellpadding="0" border="0" style="width:540px;max-width:100%;border-collapse:collapse;">
                  <tr>
                    <td align="center" style="padding:0;color:#a5adad;">
                      <p class="newsletter-footer-copy" style="margin:0 0 12px;font-size:12px;line-height:1.6;">
                        Du erhältst diese E-Mail, weil du dich für den Stuttgart Live Newsletter angemeldet hast.
                        Wenn du unseren Event-Newsletter nicht mehr erhalten möchtest, kannst du dich
                        <a href="[[UNSUB_LINK_DE]]" style="color:#596364;text-decoration:underline;">hier abmelden</a>.
                      </p>
                      <p class="newsletter-footer-auto-note" style="margin:0 0 12px;font-size:12px;line-height:1.6;">
                        Dies ist eine automatisch generierte E-Mail.<br>
                        Bitte antworte nicht auf diese E-Mail, da uns deine Anfrage hier nicht erreicht.
                      </p>
                      <p class="newsletter-footer-link-row" style="margin:0 0 12px;font-size:12px;line-height:1.45;">
                        <a href="#{escape(datenschutz_url(**route_url_options))}" style="color:#596364;text-decoration:underline;">Datenschutz</a>
                        <span style="color:#c2c7c7;">&nbsp;&middot;&nbsp;</span>
                        <a href="#{escape(imprint_url(**route_url_options))}" style="color:#596364;text-decoration:underline;">Impressum</a>
                      </p>
                      <p class="newsletter-footer-address" style="margin:0;font-size:12px;line-height:1.5;">
                        Stuttgart Live ist eine Marke der SKS Michael Russ GmbH<br>
                        Charlottenplatz 17, 70173 Stuttgart, Deutschland<br>
                        Telefon: <a href="tel:+497111635327" style="color:#596364;text-decoration:underline;">0711 - 16353-27</a>
                        &nbsp;&middot;&nbsp;
                        E-Mail: <a href="mailto:info@stuttgart-live.de" style="color:#596364;text-decoration:underline;">info@stuttgart-live.de</a>
                      </p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </footer>
      HTML
    end

    def footer_text
      <<~TEXT.strip
        Noch nicht genug?
        Auf unserer Website warten noch jede Menge Highlights auf dich.
        Mehr Events entdecken: #{website_url}

        Du erhältst diese E-Mail, weil du dich für den Stuttgart Live Newsletter angemeldet hast.
        Newsletter abbestellen: [[UNSUB_LINK_DE]]
        Datenschutz: #{datenschutz_url(**route_url_options)}
        Impressum: #{imprint_url(**route_url_options)}

        Dies ist eine automatisch generierte E-Mail.
        Bitte antworte nicht auf diese E-Mail, da uns deine Anfrage hier nicht erreicht.

        Stuttgart Live ist eine Marke der SKS Michael Russ GmbH
        Charlottenplatz 17, 70173 Stuttgart, Deutschland
        Telefon: 0711 - 16353-27
        E-Mail: info@stuttgart-live.de
      TEXT
    end

    def footer_social_icons_html
      SOCIAL_LINKS.map do |link|
        image_url = absolute_media_url(ActionController::Base.helpers.asset_path(link.fetch(:image_path)))
        next if image_url.blank?

        <<~HTML
          <a href="#{escape(link.fetch(:url))}" target="_blank" rel="noopener" style="display:inline-block;margin:0 7px;text-decoration:none;">
            <img src="#{escape(image_url)}" width="38" height="38" alt="#{escape(link.fetch(:name))}" style="display:block;width:38px;height:38px;border:0;outline:none;text-decoration:none;">
          </a>
        HTML
      end.compact.join
    end

    def website_url
      root_url(**route_url_options)
    end

    def item_label(item)
      item.item.is_a?(Event) ? event_label(item.item) : "News"
    end

    def genre_weekly_mix_news_items
      @genre_weekly_mix_news_items ||=
        issue.sort_weekly_mix_news_items(
          issue.newsletter_issue_items.includes(:item).select { |item| item.item.is_a?(BlogPost) }
        )
    end

    def genre_weekly_mix_sections
      @genre_weekly_mix_sections ||= begin
        items_by_genre_slug = issue.newsletter_issue_items.includes(:item).each_with_object({}) do |item, memo|
          next if item.item.is_a?(BlogPost)

          group = header_group_for(item)
          next if group.blank?

          memo[group.slug] ||= { group:, items: [] }
          memo[group.slug][:items] << item
        end

        Newsletter::HeaderGenreGroups.all.filter_map do |group|
          section = items_by_genre_slug[group.slug]
          next if section.blank?

          section.merge(items: issue.sort_weekly_mix_items(section[:items]))
        end
      end
    end

    def header_group_for(item)
      section_key = item.effective_section_key
      return Newsletter::HeaderGenreGroups.all.find { |group| group.slug == section_key } if section_key.present?

      return unless item.item.is_a?(Event)

      event_genre_slugs = item.item.genres.map(&:slug)
      Newsletter::HeaderGenreGroups.all.find { |group| event_genre_slugs.include?(group.slug) }
    end

    def genre_anchor(group)
      "genre-#{group.slug}"
    end

    def event_label(event)
      [ I18n.l(event.start_at, format: "%d.%m.%Y %H:%M Uhr"), event.venue ].compact_blank.join(", ")
    end

    def item_url(item)
      if item.item.is_a?(Event)
        event_url(item.item.slug, **route_url_options)
      else
        news_url(item.item.slug, **route_url_options)
      end
    end

    def item_image_url(item)
      if item.item.is_a?(Event)
        event_image_url(item.item)
      else
        blog_post_image_url(item.item)
      end
    end

    def event_image_url(event)
      if event.promotion_banner_image.attached?
        public_asset_url(processed_newsletter_card_variant(event.promotion_banner_image))
      elsif (image = event.event_image)&.file&.attached?
        public_asset_url(processed_newsletter_card_variant(image.file))
      else
        absolute_media_url(event.image_url_for(slot: :detail_hero, breakpoint: :desktop))
      end
    rescue Event::ProcessingError, EventImage::ProcessingError => error
      Rails.logger.warn("Newsletter event image skipped for ##{event.id}: #{error.class}: #{error.message}")
      nil
    end

    def blog_post_image_url(blog_post)
      return unless blog_post.cover_image.attached?

      public_asset_url(processed_newsletter_card_variant(blog_post.cover_image))
    rescue BlogPost::ProcessingError => error
      Rails.logger.warn("Newsletter news image skipped for ##{blog_post.id}: #{error.class}: #{error.message}")
      nil
    end

    def public_asset_url(record)
      PublicMediaUrl.url_for(record, url_options: route_url_options) ||
        rails_storage_proxy_url(record, **route_url_options)
    end

    def processed_newsletter_card_variant(attachment)
      attachment.variant(**newsletter_card_variant_transformations).processed
    rescue LoadError, MiniMagick::Error => error
      Rails.logger.warn("Newsletter card image optimization fallback: #{error.class}: #{error.message}")
      attachment
    rescue ActiveStorage::InvariableError, ImageProcessing::Error => error
      raise EventImage::ProcessingError, error.message
    rescue StandardError => error
      raise unless error.message.match?(/vips|Vips|libvips|heif|image/i)

      raise EventImage::ProcessingError, error.message
    end

    def newsletter_card_variant_transformations
      transformations = {
        format: :jpg,
        resize_to_fill: [ CARD_IMAGE_VARIANT_WIDTH, CARD_IMAGE_VARIANT_HEIGHT ]
      }

      if ActiveStorage.variant_processor == :vips
        transformations[:saver] = {
          strip: true,
          quality: IMAGE_QUALITY
        }
      end

      transformations
    end

    def absolute_media_url(value)
      return if value.blank?
      return value if URI.parse(value).absolute?

      URI::Generic.build(
        scheme: route_url_options.fetch(:protocol).delete_suffix("://"),
        host: route_url_options.fetch(:host),
        port: route_url_options[:port],
        path: value
      ).to_s
    rescue URI::InvalidURIError
      nil
    end

    def route_url_options
      @route_url_options ||= begin
        options = Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
        public_url = ENV["NEWSLETTER_PUBLIC_URL"].presence || ENV["NEWSLETTER_PUBLIC_HOST"].presence

        if public_url.present?
          uri = URI.parse(public_url.match?(%r{\Ahttps?://}) ? public_url : "https://#{public_url}")
          options[:host] = uri.host
          options[:protocol] = uri.scheme
          if standard_uri_port?(uri)
            options.delete(:port)
          else
            options[:port] = uri.port
          end
        end

        options[:host] = options.fetch(:host)
        options[:protocol] ||= options[:host].to_s.include?("localhost") ? "http" : "https"
        options
      end
    end

    def standard_uri_port?(uri)
      (uri.scheme == "http" && uri.port == 80) ||
        (uri.scheme == "https" && uri.port == 443)
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
