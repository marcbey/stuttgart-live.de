Rails.application.config.to_prepare do
  [ Event, EventOffer, EventSeries, BlogPost, StaticPage, Genre, Venue,
    EventImage, ActiveStorage::Attachment, ActiveStorage::Blob, ActionText::RichText ].each do |model|
    model.include(LegacyRedirects::Invalidation::ContentChanges) unless model < LegacyRedirects::Invalidation::ContentChanges
  end
end
