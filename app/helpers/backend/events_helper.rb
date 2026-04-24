module Backend::EventsHelper
  GERMAN_DAY_NAMES = %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag].freeze

  def effective_backend_event_series_ids(events)
    series_ids =
      Array(events)
        .filter_map { |event| event.event_series_id }
        .uniq

    return [] if series_ids.empty?

    Event.where(event_series_id: series_ids)
      .group(:event_series_id)
      .having("COUNT(DISTINCT events.id) >= 2")
      .pluck(:event_series_id)
  end

  def backend_event_series_effective?(event, effective_series_ids: nil)
    return false if event.event_series_id.blank?

    if effective_series_ids.present?
      Array(effective_series_ids).include?(event.event_series_id)
    else
      Event.where(event_series_id: event.event_series_id).distinct.count(:id) >= 2
    end
  end

  def event_payload_presenter(event)
    unless defined?(Backend::Events::SourcePayloadPresenter)
      presenter_path = Rails.root.join("app/presenters/backend/events/source_payload_presenter.rb").to_s
      require_dependency presenter_path
      load presenter_path unless defined?(Backend::Events::SourcePayloadPresenter)
    end

    Backend::Events::SourcePayloadPresenter.new(event)
  end

  def backend_event_context(event)
    return if event.blank?

    context_parts = [
      event.artist_name.to_s.strip.presence,
      event.title.to_s.strip.presence,
      (event.start_at.present? ? l(event.start_at, format: "%d.%m.%Y %H:%M") : nil)
    ].compact
    return ([ "Neues Event anlegen" ] + context_parts).join(" · ") unless event.persisted?

    context_parts << "Event-Reihe (#{event_series_origin_label(event)})" if event.event_series?
    context_parts.join(" · ")
  end

  def event_display_promoter(event)
    event_payload_presenter(event).display_promoter
  end

  def event_display_ticket_url(event)
    event.editor_ticket_offer&.resolved_ticket_url.to_s.strip.presence
  end

  def event_display_ticket_sold_out(event)
    ActiveModel::Type::Boolean.new.cast(event.editor_ticket_offer&.sold_out?)
  end

  def event_display_ticket_availability_label(event)
    offer = event.editor_ticket_offer
    return "Ist abgesagt" if offer&.canceled?
    return "Ist ausverkauft" if ActiveModel::Type::Boolean.new.cast(offer&.sold_out?)

    "Ist nicht ausverkauft"
  end

  def event_editor_ticket_offer_source(event)
    event.editor_ticket_offer&.source.to_s.strip.presence
  end

  def event_status_label(status)
    case status.to_s
    when "imported" then "importiert"
    when "needs_review" then "Draft"
    when "ready_for_publish" then "Unpublished"
    when "published" then "Published"
    when "rejected" then "Rejected"
    else status.to_s
    end
  end

  def event_display_status_label(event)
    return "Unpublished/Geplant" if event&.scheduled?

    event_status_label(event&.status)
  end

  def event_display_status_badge_class(event)
    event_status_badge_class(event&.status)
  end

  def event_status_filter_label(status)
    return "Drafts" if status.to_s == "needs_review"

    event_status_label(status)
  end

  def event_status_select_label(status)
    event_status_label(status).upcase
  end

  def event_status_badge_class(status)
    case status.to_s
    when "published"
      "status-badge status-badge-published"
    when "ready_for_publish"
      "status-badge status-badge-ready"
    when "needs_review"
      "status-badge status-badge-review"
    when "rejected"
      "status-badge status-badge-rejected"
    else
      "status-badge status-badge-default"
    end
  end

  def event_import_change_badge(event, merge_run_id:)
    merge_run_id_value = merge_run_id.to_i
    return nil if merge_run_id_value <= 0

    actions = import_change_actions_for(event, merge_run_id_value)
    return nil if actions.empty?

    if actions.include?("merged_create")
      { label: "New", css_class: "status-badge status-badge-import-new" }
    else
      { label: "Updated", css_class: "status-badge status-badge-import-updated" }
    end
  end

  def merge_run_filter_option_label(run)
    timestamp = run.started_at || run.finished_at || run.created_at
    "Run ID ##{run.id}: #{timestamp.strftime("%d.%m.%Y %H:%M:%S")}"
  end

  def event_editor_errors(event)
    [
      *event.errors.full_messages,
      *event.llm_enrichment&.errors&.full_messages.to_a
    ].uniq
  end

  def event_llm_raw_response(event)
    enrichment = event.llm_enrichment
    return if enrichment.blank?

    raw_response = enrichment.raw_response
    return if raw_response.blank?

    JSON.pretty_generate(raw_response)
  rescue JSON::GeneratorError
    raw_response.to_json
  end

  def event_llm_last_successful_run_hint(event)
    run = event.llm_enrichment&.source_run
    return if run.blank? || run.status != "succeeded"

    timestamp = run.finished_at || run.started_at || run.created_at
    return if timestamp.blank?

    day_name = localized_day_name(timestamp.to_date)
    "Letzter LLM-Enrichment-Run: #{day_name}, #{l(timestamp, format: "%d.%m.%Y %H:%M")}"
  end

  def external_link_label_row(label_html:, url:, text:)
    content_tag(:div, class: "form-label-row") do
      parts = [ label_html ]

      if (external_url = url.to_s.strip.presence).present?
        parts << link_to(external_url,
                         class: "form-label-link",
                         target: "_blank",
                         rel: "noopener",
                         title: "#{text} öffnen",
                         aria: { label: "#{text} öffnen" }) do
          tag.svg(viewBox: "0 0 20 20", aria: { hidden: "true" }, focusable: "false") do
            safe_join([
              tag.path(
                d: "M11.75 4.25h4v4",
                fill: "none",
                stroke: "currentColor",
                "stroke-linecap": "round",
                "stroke-linejoin": "round",
                "stroke-width": "1.5"
              ),
              tag.path(
                d: "M15.75 4.25 8.5 11.5",
                fill: "none",
                stroke: "currentColor",
                "stroke-linecap": "round",
                "stroke-linejoin": "round",
                "stroke-width": "1.5"
              ),
              tag.path(
                d: "M9.25 5.25h-3.5A1.5 1.5 0 0 0 4.25 6.75v7.5a1.5 1.5 0 0 0 1.5 1.5h7.5a1.5 1.5 0 0 0 1.5-1.5v-3.5",
                fill: "none",
                stroke: "currentColor",
                "stroke-linecap": "round",
                "stroke-linejoin": "round",
                "stroke-width": "1.5"
              )
            ])
          end
        end
      end

      safe_join(parts)
    end
  end

  def form_external_link_label_row(form, attribute, text)
    external_link_label_row(
      label_html: form.label(attribute, text, class: "form-label"),
      url: form.object.public_send(attribute),
      text: text
    )
  end

  alias_method :llm_enrichment_link_label_row, :form_external_link_label_row

  def event_venue_link_label_row(form, event)
    external_link_label_row(
      label_html: form.label(:venue_name, "Venue", class: "form-label"),
      url: (backend_venues_path(venue_id: event.venue_record.id) if event.venue_record.present?),
      text: "Venue im Backend"
    )
  end

  def preuploaded_blob_from_signed_id(signed_id)
    return if signed_id.blank?

    ActiveStorage::Blob.find_signed(signed_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    nil
  end

  def event_presenter_reference_items(event:, all_presenters:, selected_presenter_ids: nil)
    selected_ids =
      if selected_presenter_ids.nil?
        event.ordered_presenters.map(&:id)
      else
        Array(selected_presenter_ids).reject(&:blank?).map(&:to_i)
      end
    selected_positions = selected_ids.each_with_index.to_h

    all_presenters.sort_by do |presenter|
      selection_index = selected_positions[presenter.id]
      [
        selection_index.nil? ? 1 : 0,
        selection_index || presenter.name.to_s.downcase,
        presenter.id
      ]
    end.map do |presenter|
      selection_index = selected_positions[presenter.id]

      {
        presenter: presenter,
        selected: selection_index.present?,
        selected_index: selection_index&.+(1)
      }
    end
  end

  def event_series_origin_label(event)
    case event.event_series_origin
    when "manual" then "manuell"
    when "imported" then "importiert"
    else "unbekannt"
    end
  end

  def event_social_post_platform_label(platform)
    case platform.to_s
    when "facebook" then "Facebook"
    when "instagram" then "Instagram"
    else platform.to_s.humanize
    end
  end

  def event_social_post_status_label(post)
    case post&.status.to_s
    when "draft" then "Draft"
    when "approved" then "Bereit"
    when "publishing" then "Wird gesendet"
    when "published" then "Veröffentlicht"
    when "failed" then "Fehlgeschlagen"
    else "Unbekannt"
    end
  end

  def event_social_post_status_badge_class(post)
    case post&.status.to_s
    when "approved"
      "status-badge status-badge-default"
    when "publishing"
      "status-badge status-badge-default"
    when "published"
      "status-badge status-badge-published"
    when "failed"
      "status-badge status-badge-rejected"
    else
      "status-badge status-badge-review"
    end
  end

  def meta_access_status_badge_class(status)
    case status&.state
    when :ok
      "status-badge status-badge-published"
    when :warning
      "status-badge status-badge-ready"
    when :error
      "status-badge status-badge-rejected"
    else
      "status-badge status-badge-default"
    end
  end

  def meta_access_status_label(status)
    case status&.state
    when :ok
      "Meta OK"
    when :warning
      "Meta Warnung"
    when :error
      "Meta Fehler"
    else
      "Meta Unbekannt"
    end
  end

  def social_connection_status_label(status)
    case status.to_s
    when "connected"
      "Verbunden"
    when "pending_selection"
      "Seite auswählen"
    when "expiring_soon"
      "Läuft bald ab"
    when "refresh_failed"
      "Refresh fehlgeschlagen"
    when "reauth_required"
      "Re-Auth nötig"
    when "revoked"
      "Widerrufen"
    when "error"
      "Fehler"
    else
      "Nicht verbunden"
    end
  end

  private

  def localized_day_name(date)
    translated_day_names = I18n.t("date.day_names", default: nil)
    if translated_day_names.is_a?(Array) && translated_day_names[date.wday].present?
      return translated_day_names[date.wday]
    end

    GERMAN_DAY_NAMES.fetch(date.wday)
  end

  def import_change_actions_for(event, merge_run_id)
    association = event.event_change_logs

    if association.loaded?
      association.filter_map do |change_log|
        next unless [ "merged_create", "merged_update" ].include?(change_log.action.to_s)
        next unless change_log_merge_run_id(change_log) == merge_run_id

        change_log.action.to_s
      end.uniq
    else
      association
        .where(action: [ "merged_create", "merged_update" ])
        .where("metadata ->> 'merge_run_id' = ?", merge_run_id.to_s)
        .pluck(:action)
        .uniq
    end
  end

  def change_log_merge_run_id(change_log)
    metadata = change_log.metadata.is_a?(Hash) ? change_log.metadata.deep_stringify_keys : {}
    Integer(metadata["merge_run_id"], exception: false)
  end
end
