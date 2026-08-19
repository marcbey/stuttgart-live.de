module Newsletter
  class PopulateIssueFromInterest
    LIMIT = 10

    def self.call(issue, limit: LIMIT)
      new(issue, limit:).call
    end

    def initialize(issue, limit: LIMIT)
      @issue = issue
      @limit = limit
    end

    def call
      return 0 if issue.newsletter_interest.blank?

      added_count = 0
      candidate_events.each do |event|
        next if existing_event_ids.include?(event.id)

        issue.newsletter_issue_items.create!(item: event, position: next_position + added_count, cta_label: "Zum Event")
        added_count += 1
      end
      added_count
    end

    private

    attr_reader :issue, :limit

    def candidate_events
      Event
        .published_live
        .joins(:genres)
        .where(genres: { id: issue.newsletter_interest.genre_id })
        .where("events.start_at >= ?", Time.zone.today.beginning_of_day)
        .where.not(id: existing_event_ids)
        .distinct
        .reorder(Arel.sql(Event.sks_first_order_sql), :start_at, :id)
        .limit(limit)
    end

    def existing_event_ids
      @existing_event_ids ||= issue.newsletter_issue_items.where(item_type: "Event").pluck(:item_id)
    end

    def next_position
      @next_position ||= issue.newsletter_issue_items.maximum(:position).to_i + 1
    end
  end
end
