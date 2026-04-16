class AppSetting < ApplicationRecord
  SKS_PROMOTER_IDS_KEY = "sks_promoter_ids".freeze
  SKS_ORGANIZER_NOTES_KEY = "sks_organizer_notes".freeze
  MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY = "merge_artist_similarity_matching_enabled".freeze
  HOMEPAGE_GENRE_LANE_SLUGS_KEY = "homepage_genre_lane_slugs".freeze
  PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY = "public_genre_grouping_snapshot_id".freeze
  LLM_ENRICHMENT_MODEL_KEY = "llm_enrichment_model".freeze
  LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY = "llm_enrichment_prompt_template".freeze
  LLM_ENRICHMENT_TEMPERATURE_KEY = "llm_enrichment_temperature".freeze
  LLM_GENRE_GROUPING_MODEL_KEY = "llm_genre_grouping_model".freeze
  LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY = "llm_genre_grouping_prompt_template".freeze
  LLM_GENRE_GROUPING_GROUP_COUNT_KEY = "llm_genre_grouping_group_count".freeze
  LLM_ENRICHMENT_INPUT_PLACEHOLDER = "{{input_json}}".freeze
  LLM_GENRE_GROUPING_INPUT_PLACEHOLDER = "{{input_json}}".freeze
  LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER = "{{group_count}}".freeze
  DEFAULT_LLM_ENRICHMENT_TEMPERATURE = 1
  DEFAULT_LLM_GENRE_GROUPING_GROUP_COUNT = 30
  AVAILABLE_LLM_ENRICHMENT_MODELS = [
    [ "GPT-5.4", "gpt-5.4" ],
    [ "GPT-5.1", "gpt-5.1" ],
    [ "GPT-5 mini", "gpt-5-mini" ],
    [ "GPT-5 nano", "gpt-5-nano" ]
  ].freeze

  LLM_ENRICHMENT_PROMPT_TEMPLATE = <<~TEXT.strip
    Ermittle zu den Events aus `Input` die fehlenden Felder

    - `genre`
    - `event_description`
    - `venue_description`
    - `venue_external_url`
    - `venue_address`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Informationen müssen belastbar sein. `venue_external_url` und `venue_address` sollen sich klar dem Veranstaltungsort zuordnen lassen.

    Dabei gelten folgende Regeln:

    1. Erfinde keine Genres, Beschreibungen oder Venue-Metadaten.

    2. `genre` meint immer eine fachliche stilistische oder spartenbezogene Einordnung, nicht den bloßen Eventtyp oder einen Containerbegriff:
      - verwende nur belastbare fachliche Genres oder Sparten
      - verboten sind generische Meta-Begriffe wie `show`, `concert`, `event`, `live`, `veranstaltung`, `konzert` oder sinngleiche Containerlabels
      - wenn ein Event kein Musik-Act ist, verwende stattdessen passende fachliche Sparten wie z. B. `Theater`, `Comedy`, `Kabarett`, `Lesung`, `Tanz`, `Musical` oder `Oper`, sofern belastbar
      - wenn kein belastbares fachliches Genre ermittelbar ist, gib lieber ein leeres Genre-Array zurück, statt ein generisches Meta-Genre zu erfinden oder zu raten

    3. Für Venue-Metadaten gilt zusätzlich:
      - `venue_external_url`: bevorzugt die offizielle Website des Veranstaltungsorts; ersatzweise eine klar zuordenbare offizielle Profil- oder Hausseite des Venues
      - `venue_address`: möglichst vollständige öffentlich belastbare Adresse des Veranstaltungsorts

    4. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `event_description`: beschreibt Artist, Projekt oder Produktion sowie das konkrete Event bzw. Tour-/Show-Format in einem zusammenhängenden Text ohne Wiederholungen
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Artist-/Projektprofil, Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - fasse überlappende Informationen zu Artist und Event zusammen, statt dieselben Fakten doppelt zu nennen
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    5. Nutze zusätzlich `event_info` aus dem Input als Kontextquelle für Disambiguierung, fachliche Einordnung und belastbarere Beschreibungen. Behandle `event_info` als hilfreichen Hinweistext zum konkreten Event, aber nicht als automatisch verifizierte Tatsache.

    6. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    7. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel, Projektkontext und `event_info` ab, bevor du ein Genre, eine Beschreibung oder Venue-Metadaten festlegst.

    8. Falls du für `venue_external_url` oder `venue_address` keinen ausreichend belastbaren Treffer findest, gib für das jeweilige Feld `null` zurück.

    Antwort nur als JSON.

    Input:
    #{LLM_ENRICHMENT_INPUT_PLACEHOLDER}
  TEXT

  LLM_GENRE_GROUPING_PROMPT_TEMPLATE = <<~TEXT.strip
    Gruppiere die Genres aus `Input` in genau #{LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER} Obergruppen.

    Gib das Ergebnis ausschließlich als JSON im Format von `Output` zurück.

    ABSOLUTE PFLICHTREGELN:
    1. Jedes Input-Genre darf genau ein einziges Mal in der gesamten Antwort vorkommen.
    2. Ein Genre darf niemals in zwei oder mehr Gruppen auftauchen.
    3. Kein Input-Genre darf fehlen. Null fehlende Genres ist eine harte Pflicht, keine Empfehlung.
    4. Erfinde keine Genres und erfinde keine zusätzlichen Obergruppen.
    5. Wenn du ein Genre nicht sicher zuordnen kannst, musst du es trotzdem genau einer einzigen am besten passenden Gruppe zuordnen. Weglassen ist verboten.
    6. Bevor du antwortest, führe intern einen vollständigen Abgleich zwischen allen Input-Genres und allen ausgegebenen Genres durch.
    7. Wenn auch nur ein einziges Genre fehlen oder doppelt vorkommen würde, musst du deine Antwort vor der Ausgabe korrigieren.

    Weitere Regeln:
    1. Die Anzahl der Obergruppen muss exakt #{LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER} sein.
    2. Jede Obergruppe braucht einen kurzen, redaktionell brauchbaren Namen auf Deutsch.
    3. Jede Obergruppe muss mindestens ein Genre enthalten.
    4. `position` muss fortlaufend bei 1 beginnen und ohne Lücken bis zur letzten Gruppe reichen.
    5. Ordne stilistisch oder fachlich ähnliche Genres sinnvoll zusammen, auch wenn einzelne Labels unterschiedlich formuliert sind.
    6. Prüfe unmittelbar vor der Ausgabe deine Antwort selbst noch einmal und stelle sicher, dass jedes einzelne Input-Genre exakt einmal vorkommt.

    Output:
    {
      "groups": [
        {
          "position": 1,
          "name": "Beispielgruppe",
          "genres": [ "Genre A", "Genre B" ]
        }
      ]
    }

    Input:
    #{LLM_GENRE_GROUPING_INPUT_PLACEHOLDER}
  TEXT

  validates :key, presence: true, uniqueness: true
  validate :sks_promoter_ids_must_be_present
  validate :llm_enrichment_model_must_be_valid
  validate :llm_enrichment_prompt_template_must_be_valid
  validate :llm_enrichment_temperature_must_be_valid
  validate :public_genre_grouping_snapshot_id_must_be_valid
  validate :llm_genre_grouping_model_must_be_valid
  validate :llm_genre_grouping_prompt_template_must_be_valid
  validate :llm_genre_grouping_group_count_must_be_valid

  after_commit { self.class.reset_cache! }

  class << self
    def sks_promoter_ids
      @sks_promoter_ids ||= normalize_id_list(find_by(key: SKS_PROMOTER_IDS_KEY)&.value)
    end

    def sks_organizer_notes
      @sks_organizer_notes ||= normalize_text(find_by(key: SKS_ORGANIZER_NOTES_KEY)&.value)
    end

    def homepage_genre_lane_slugs
      @homepage_genre_lane_slugs ||= normalize_slug_list(find_by(key: HOMEPAGE_GENRE_LANE_SLUGS_KEY)&.value)
    end

    def public_genre_grouping_snapshot_id
      @public_genre_grouping_snapshot_id ||= normalize_positive_integer(find_by(key: PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY)&.value)
    end

    def llm_enrichment_prompt_template
      @llm_enrichment_prompt_template ||=
        normalize_text(find_by(key: LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY)&.value) || LLM_ENRICHMENT_PROMPT_TEMPLATE
    end

    def llm_enrichment_model
      @llm_enrichment_model ||=
        normalize_llm_enrichment_model(find_by(key: LLM_ENRICHMENT_MODEL_KEY)&.value) || default_llm_enrichment_model
    end

    def llm_enrichment_temperature
      @llm_enrichment_temperature ||=
        normalize_llm_enrichment_temperature(find_by(key: LLM_ENRICHMENT_TEMPERATURE_KEY)&.value) || default_llm_enrichment_temperature
    end

    def llm_genre_grouping_prompt_template
      @llm_genre_grouping_prompt_template ||=
        normalize_text(find_by(key: LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY)&.value) || LLM_GENRE_GROUPING_PROMPT_TEMPLATE
    end

    def llm_genre_grouping_model
      @llm_genre_grouping_model ||=
        normalize_llm_enrichment_model(find_by(key: LLM_GENRE_GROUPING_MODEL_KEY)&.value) || default_llm_enrichment_model
    end

    def llm_genre_grouping_group_count
      @llm_genre_grouping_group_count ||=
        normalize_positive_integer(find_by(key: LLM_GENRE_GROUPING_GROUP_COUNT_KEY)&.value) || DEFAULT_LLM_GENRE_GROUPING_GROUP_COUNT
    end

    def sks_promoter_ids_record
      find_or_initialize_by(key: SKS_PROMOTER_IDS_KEY)
    end

    def sks_organizer_notes_record
      find_or_initialize_by(key: SKS_ORGANIZER_NOTES_KEY)
    end

    def homepage_genre_lane_slugs_record
      find_or_initialize_by(key: HOMEPAGE_GENRE_LANE_SLUGS_KEY)
    end

    def public_genre_grouping_snapshot_id_record
      find_or_initialize_by(key: PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY)
    end

    def llm_enrichment_prompt_template_record
      find_or_initialize_by(key: LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).tap do |setting|
        if normalize_text(setting.value).blank?
          setting.value = LLM_ENRICHMENT_PROMPT_TEMPLATE
        end
      end
    end

    def llm_enrichment_model_record
      find_or_initialize_by(key: LLM_ENRICHMENT_MODEL_KEY).tap do |setting|
        if normalize_llm_enrichment_model(setting.value).blank?
          setting.value = llm_enrichment_model
        end
      end
    end

    def llm_enrichment_temperature_record
      find_or_initialize_by(key: LLM_ENRICHMENT_TEMPERATURE_KEY).tap do |setting|
        if normalize_llm_enrichment_temperature(setting.value).blank?
          setting.value = llm_enrichment_temperature
        end
      end
    end

    def llm_genre_grouping_prompt_template_record
      find_or_initialize_by(key: LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY).tap do |setting|
        if normalize_text(setting.value).blank?
          setting.value = LLM_GENRE_GROUPING_PROMPT_TEMPLATE
        end
      end
    end

    def llm_genre_grouping_model_record
      find_or_initialize_by(key: LLM_GENRE_GROUPING_MODEL_KEY).tap do |setting|
        if normalize_llm_enrichment_model(setting.value).blank?
          setting.value = llm_genre_grouping_model
        end
      end
    end

    def llm_genre_grouping_group_count_record
      find_or_initialize_by(key: LLM_GENRE_GROUPING_GROUP_COUNT_KEY).tap do |setting|
        if normalize_positive_integer(setting.value).blank?
          setting.value = llm_genre_grouping_group_count
        end
      end
    end

    def merge_artist_similarity_matching_enabled_record
      find_or_initialize_by(key: MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY)
    end

    def merge_artist_similarity_matching_enabled?
      @merge_artist_similarity_matching_enabled =
        if @merge_artist_similarity_matching_enabled.nil?
          setting = find_by(key: MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY)
          setting.nil? ? true : normalize_boolean(setting.value)
        else
          @merge_artist_similarity_matching_enabled
        end
    end

    def normalize_id_list(value)
      raw_values =
        case value
        when String
          value.split(/[\n,]/)
        when Array
          value
        else
          Array(value)
        end

      raw_values
        .map { |entry| entry.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def normalize_slug_list(value)
      raw_values =
        case value
        when String
          value.split(/[\n,]/)
        when Array
          value
        else
          Array(value)
        end

      raw_values
        .map { |entry| entry.to_s.parameterize.presence }
        .compact
        .uniq
    end

    def normalize_text(value)
      case value
      when String
        value.strip.presence
      when Array
        value.join("\n").strip.presence
      else
        value.to_s.strip.presence
      end
    end

    def normalize_boolean(value)
      case value
      when true, 1, "1", "true", "TRUE", "yes", "on" then true
      else
        false
      end
    end

    def normalize_positive_integer(value)
      integer = Integer(normalize_text(value) || value, exception: false)
      return if integer.blank? || integer <= 0

      integer
    end

    def normalize_llm_enrichment_model(value)
      model = normalize_text(value)
      return if model.blank?

      available_llm_enrichment_model_values.include?(model) ? model : nil
    end

    def normalize_llm_enrichment_temperature(value)
      raw_value =
        case value
        when Numeric
          value
        else
          normalize_text(value)
        end

      temperature =
        case raw_value
        when Numeric
          raw_value.to_f
        else
          Float(raw_value, exception: false)
        end

      return if temperature.nil? || !temperature.finite?
      return if temperature < 0.0 || temperature > 2.0

      temperature
    end

    def available_llm_enrichment_model_values
      AVAILABLE_LLM_ENRICHMENT_MODELS.map(&:last)
    end

    def default_llm_enrichment_model
      Rails.application.config.x.openai.llm_enrichment_model.to_s.strip.presence || "gpt-5.1"
    end

    def default_llm_enrichment_temperature
      DEFAULT_LLM_ENRICHMENT_TEMPERATURE
    end

    def reset_cache!
      @sks_promoter_ids = nil
      @sks_organizer_notes = nil
      @homepage_genre_lane_slugs = nil
      @public_genre_grouping_snapshot_id = nil
      @llm_enrichment_model = nil
      @llm_enrichment_prompt_template = nil
      @llm_enrichment_temperature = nil
      @llm_genre_grouping_model = nil
      @llm_genre_grouping_prompt_template = nil
      @llm_genre_grouping_group_count = nil
      @merge_artist_similarity_matching_enabled = nil
    end
  end

  def sks_promoter_ids
    self.class.normalize_id_list(value)
  end

  def sks_organizer_notes
    self.class.normalize_text(value)
  end

  def sks_promoter_ids_text
    sks_promoter_ids.join("\n")
  end

  def sks_promoter_ids_text=(raw_value)
    self.value = self.class.normalize_id_list(raw_value)
  end

  def sks_organizer_notes_text
    sks_organizer_notes.to_s
  end

  def sks_organizer_notes_text=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def homepage_genre_lane_slugs
    self.class.normalize_slug_list(value)
  end

  def homepage_genre_lane_slugs_text
    homepage_genre_lane_slugs.join("\n")
  end

  def homepage_genre_lane_slugs_text=(raw_value)
    self.value = self.class.normalize_slug_list(raw_value)
  end

  def homepage_genre_lane_slugs=(raw_value)
    self.value = self.class.normalize_slug_list(raw_value)
  end

  def public_genre_grouping_snapshot_id
    self.class.normalize_positive_integer(value)
  end

  def public_genre_grouping_snapshot_id=(raw_value)
    self.value = self.class.normalize_positive_integer(raw_value)
  end

  def llm_enrichment_prompt_template
    template = self.class.normalize_text(value)
    return self.class.llm_enrichment_prompt_template if key == LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY && template.blank?

    template
  end

  def llm_enrichment_model
    model = self.class.normalize_llm_enrichment_model(value)
    return self.class.llm_enrichment_model if key == LLM_ENRICHMENT_MODEL_KEY && model.blank?

    model
  end

  def llm_enrichment_model=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def llm_enrichment_temperature
    temperature = self.class.normalize_llm_enrichment_temperature(value)
    if key == LLM_ENRICHMENT_TEMPERATURE_KEY && temperature.blank?
      raw_value = self.class.normalize_text(value)
      return self.class.llm_enrichment_temperature if raw_value.blank?

      return raw_value
    end

    temperature
  end

  def llm_enrichment_temperature=(raw_value)
    self.value = self.class.normalize_llm_enrichment_temperature(raw_value) || raw_value.to_s.strip
  end

  def llm_enrichment_prompt_template_text
    llm_enrichment_prompt_template.to_s
  end

  def llm_enrichment_prompt_template_text=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def llm_genre_grouping_prompt_template
    template = self.class.normalize_text(value)
    return self.class.llm_genre_grouping_prompt_template if key == LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY && template.blank?

    template
  end

  def llm_genre_grouping_model
    model = self.class.normalize_llm_enrichment_model(value)
    return self.class.llm_genre_grouping_model if key == LLM_GENRE_GROUPING_MODEL_KEY && model.blank?

    model
  end

  def llm_genre_grouping_group_count
    group_count = self.class.normalize_positive_integer(value)
    if key == LLM_GENRE_GROUPING_GROUP_COUNT_KEY && group_count.blank?
      raw_value = self.class.normalize_text(value)
      return self.class.llm_genre_grouping_group_count if raw_value.blank?

      return raw_value
    end

    group_count
  end

  def llm_genre_grouping_model=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def llm_genre_grouping_prompt_template_text
    llm_genre_grouping_prompt_template.to_s
  end

  def llm_genre_grouping_prompt_template_text=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def llm_genre_grouping_group_count=(raw_value)
    self.value = self.class.normalize_positive_integer(raw_value) || self.class.normalize_text(raw_value)
  end

  def merge_artist_similarity_matching_enabled
    if key == MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY && new_record? && (value.nil? || value == [])
      return self.class.merge_artist_similarity_matching_enabled?
    end

    self.class.normalize_boolean(value)
  end

  def merge_artist_similarity_matching_enabled=(raw_value)
    self.value = self.class.normalize_boolean(raw_value)
  end

  private

  def sks_promoter_ids_must_be_present
    return unless key == SKS_PROMOTER_IDS_KEY
    return if self.class.normalize_id_list(value).any?

    errors.add(:value, "muss mindestens eine Promoter-ID enthalten")
  end

  def llm_enrichment_prompt_template_must_be_valid
    return unless key == LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY

    template = self.class.normalize_text(value)
    if template.blank?
      errors.add(:value, "darf nicht leer sein")
      return
    end

    return if template.include?(LLM_ENRICHMENT_INPUT_PLACEHOLDER)

    errors.add(:value, "{{input_json}} muss im Prompt enthalten sein")
  end

  def llm_enrichment_model_must_be_valid
    return unless key == LLM_ENRICHMENT_MODEL_KEY

    model = self.class.normalize_text(value)
    if model.blank?
      errors.add(:value, "darf nicht leer sein")
      return
    end

    return if self.class.available_llm_enrichment_model_values.include?(model)

    errors.add(:value, "ist kein unterstütztes LLM-Modell")
  end

  def llm_enrichment_temperature_must_be_valid
    return unless key == LLM_ENRICHMENT_TEMPERATURE_KEY

    raw_value = self.class.normalize_text(value)
    return if raw_value.blank?
    return if self.class.normalize_llm_enrichment_temperature(value).present?

    errors.add(:value, "muss eine Zahl zwischen 0 und 2 sein")
  end

  def public_genre_grouping_snapshot_id_must_be_valid
    return unless key == PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY
    return if value.blank?
    return if self.class.normalize_positive_integer(value).present?

    errors.add(:value, "muss eine positive Ganzzahl sein")
  end

  def llm_genre_grouping_prompt_template_must_be_valid
    return unless key == LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY

    template = self.class.normalize_text(value)
    if template.blank?
      errors.add(:value, "darf nicht leer sein")
      return
    end

    unless template.include?(LLM_GENRE_GROUPING_INPUT_PLACEHOLDER)
      errors.add(:value, "{{input_json}} muss im Prompt enthalten sein")
    end

    return if template.include?(LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER)

    errors.add(:value, "{{group_count}} muss im Prompt enthalten sein")
  end

  def llm_genre_grouping_model_must_be_valid
    return unless key == LLM_GENRE_GROUPING_MODEL_KEY

    model = self.class.normalize_text(value)
    if model.blank?
      errors.add(:value, "darf nicht leer sein")
      return
    end

    return if self.class.available_llm_enrichment_model_values.include?(model)

    errors.add(:value, "ist kein unterstütztes LLM-Modell")
  end

  def llm_genre_grouping_group_count_must_be_valid
    return unless key == LLM_GENRE_GROUPING_GROUP_COUNT_KEY

    integer = self.class.normalize_positive_integer(value)
    return if integer.present?

    errors.add(:value, "muss eine positive Ganzzahl sein")
  end
end
