module Public
  module NewsletterSubscribersHelper
    SIGNUP_CONTEXTS = {
      "events_index" => {
        frame_id: "events-newsletter-signup",
        form_class: "newsletter-signup-form",
        label: "E-Mail-Adresse",
        placeholder: "Email-Adresse eingeben",
        submit_label: "Newsletter abonnieren",
        source: "homepage"
      },
      "news_index" => {
        frame_id: "news-index-newsletter-signup",
        form_class: "newsletter-signup-form news-index-subscribe-form",
        label: "E-Mail-Adresse für News-Updates",
        placeholder: "E-Mail-Adresse für News-Updates",
        submit_label: "News abonnieren",
        source: "news_index"
      }
    }.freeze

    def newsletter_signup_config(context, return_to: nil, source: nil)
      resolved_context = SIGNUP_CONTEXTS.key?(context.to_s) ? context.to_s : "events_index"
      config = SIGNUP_CONTEXTS.fetch(resolved_context)

      {
        context: resolved_context,
        frame_id: config.fetch(:frame_id),
        form_class: config.fetch(:form_class),
        label: config.fetch(:label),
        placeholder: config.fetch(:placeholder),
        submit_label: config.fetch(:submit_label),
        return_to: return_to.presence || default_newsletter_return_to(resolved_context),
        source: source.presence || config.fetch(:source)
      }
    end

    private

    def default_newsletter_return_to(context)
      case context
      when "news_index"
        news_index_path
      else
        events_path
      end
    end
  end
end
