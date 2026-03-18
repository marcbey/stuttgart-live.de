module Backend::EventsHelper
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

    [
      event.artist_name.to_s.strip.presence,
      event.title.to_s.strip.presence,
      (event.start_at.present? ? l(event.start_at, format: "%d.%m.%Y %H:%M") : nil)
    ].compact.join(" · ")
  end

  def event_display_promoter_id(event)
    event_payload_presenter(event).display_promoter_id
  end

  def event_display_ticket_url(event)
    event.preferred_ticket_offer&.resolved_ticket_url.to_s.strip.presence
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

  def event_llm_badge_title(event)
    enrichment = event.llm_enrichment
    return if enrichment.blank?

    raw_response = enrichment.raw_response
    return if raw_response.blank?

    JSON.pretty_generate(raw_response)
  rescue JSON::GeneratorError
    raw_response.to_json
  end

  def preuploaded_blob_from_signed_id(signed_id)
    return if signed_id.blank?

    ActiveStorage::Blob.find_signed(signed_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    nil
  end

  private

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
