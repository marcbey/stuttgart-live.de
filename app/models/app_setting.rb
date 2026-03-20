class AppSetting < ApplicationRecord
  SKS_PROMOTER_IDS_KEY = "sks_promoter_ids".freeze
  SKS_ORGANIZER_NOTES_KEY = "sks_organizer_notes".freeze
  MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY = "merge_artist_similarity_matching_enabled".freeze
  HOMEPAGE_GENRE_LANE_SLUGS_KEY = "homepage_genre_lane_slugs".freeze
  LLM_ENRICHMENT_MODEL_KEY = "llm_enrichment_model".freeze
  LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY = "llm_enrichment_prompt_template".freeze
  LLM_GENRE_GROUPING_MODEL_KEY = "llm_genre_grouping_model".freeze
  LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY = "llm_genre_grouping_prompt_template".freeze
  LLM_GENRE_GROUPING_GROUP_COUNT_KEY = "llm_genre_grouping_group_count".freeze
  LLM_ENRICHMENT_INPUT_PLACEHOLDER = "{{input_json}}".freeze
  LLM_GENRE_GROUPING_INPUT_PLACEHOLDER = "{{input_json}}".freeze
  LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER = "{{group_count}}".freeze
  DEFAULT_LLM_GENRE_GROUPING_GROUP_COUNT = 30
  AVAILABLE_LLM_ENRICHMENT_MODELS = [
    [ "GPT-5.1", "gpt-5.1" ],
    [ "GPT-5 mini", "gpt-5-mini" ],
    [ "GPT-5 nano", "gpt-5-nano" ]
  ].freeze

  LLM_ENRICHMENT_PROMPT_TEMPLATE = <<~TEXT.strip
    Ermittle zu den Events aus `Input` die fehlenden Felder

    - `genre`
    - `youtube_link`
    - `instagram_link`
    - `homepage_link`
    - `facebook_link`
    - `artist_description`
    - `event_description`
    - `venue_description`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Links und Informationen müssen für das Zielmodell „offiziell oder belastbar genug“ sein.
    Ziel ist ausdrücklich, möglichst viele korrekt zuordenbare Links für `youtube_link`, `instagram_link`, `homepage_link` und `facebook_link` zu finden. Sei deshalb bei der Recherche breit und beharrlich, aber nicht erfinderisch.

    Dabei gelten folgende Regeln:

    1. Bevorzuge für Links in dieser Reihenfolge:
      - `official`: offizielle Website oder offiziell wirkender verifizierbarer Künstler-/Projekt-/Venue-Account
      - `promoter`: offizielle Projekt-, Veranstalter- oder Tour-Seite eines bekannten Promoters / Managements / Veranstalters
      - `event_listing`: belastbare Event-Seite eines bekannten Ticketing- oder Venue-Portals
      - `social_post`: einzelner konkreter Social-Media-Post, wenn kein offizieller Account oder keine bessere Quelle verfügbar ist

    2. Suche für jeden der vier Link-Typen aktiv nach mehreren plausiblen Kandidaten und entscheide dich dann für den besten belastbaren Treffer. Prüfe insbesondere:
      - offizielle Artist-Website
      - offizielle Venue-Website
      - offizielle Tour- oder Projektseite
      - offizielle oder klar zuordenbare Social-Media-Profile
      - YouTube-Kanal oder offizieller Artist-/Venue-Channel
      - bekannte Veranstalter-, Management- oder Promoter-Seiten
      - bekannte Ticketing-, Venue- oder Festival-Listings

    3. Verwende einen Link nur dann, wenn er eindeutig dem Artist, Projekt, Event oder Venue zugeordnet werden kann. Bevorzuge dabei lieber einen schwächeren, aber noch belastbaren Treffer aus `promoter` oder `event_listing`, statt vorschnell `null` zu setzen.

    4. Wenn kein ausreichend belastbarer Link gefunden wird, setze das Feld auf `null`.

    5. Erfinde keine Links, Genres oder Beschreibungen.

    6. Wenn ein Event kein Musik-Act ist, sondern z. B. Theater, Schauspiel, Show oder Lesung, dann modelliere es fachlich korrekt und verwende passende Genres statt Musikgenres.

    7. Bei Projekt- oder Tour-Formaten wie z. B. Ensemble-, Tribute-, Jubiläums- oder Mehrkünstler-Events dürfen auch projektbezogene oder promoterbezogene Links verwendet werden, wenn keine klaren offiziellen Artist-Accounts existieren.

    8. Für Linkfelder gilt zusätzlich:
      - `homepage_link`: bevorzugt offizielle Artist-, Projekt- oder Venue-Website; ersatzweise offizielle Tour-/Promoter-Seite
      - `instagram_link`: bevorzugt offizielles Profil von Artist, Projekt oder Venue; wenn nicht vorhanden, ein klar zuordenbares Projekt-, Tour- oder Promoter-Profil
      - `facebook_link`: bevorzugt offizielle Facebook-Seite von Artist, Projekt, Venue oder Tour; ersatzweise belastbare Veranstalter-/Promoter-Seite
      - `youtube_link`: bevorzugt offizieller Kanal; ersatzweise klar zuordenbarer Topic-/Projekt-/Venue-Kanal oder ein belastbares einzelnes Video, wenn kein besserer Kanal auffindbar ist

    9. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `artist_description`: beschreibt Artist, Projekt oder Produktion
      - `event_description`: beschreibt das konkrete Event bzw. Tour-/Show-Format
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    10. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    11. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel oder Projektkontext ab, bevor du einen Link wählst.

    12. Falls du für einen Link keinen ausreichend belastbaren Treffer findest, gib für das Linkfeld `null` zurück.

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

    def llm_enrichment_prompt_template
      @llm_enrichment_prompt_template ||=
        normalize_text(find_by(key: LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY)&.value) || LLM_ENRICHMENT_PROMPT_TEMPLATE
    end

    def llm_enrichment_model
      @llm_enrichment_model ||=
        normalize_llm_enrichment_model(find_by(key: LLM_ENRICHMENT_MODEL_KEY)&.value) || default_llm_enrichment_model
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

    def available_llm_enrichment_model_values
      AVAILABLE_LLM_ENRICHMENT_MODELS.map(&:last)
    end

    def default_llm_enrichment_model
      Rails.application.config.x.openai.llm_enrichment_model.to_s.strip.presence || "gpt-5.1"
    end

    def reset_cache!
      @sks_promoter_ids = nil
      @sks_organizer_notes = nil
      @homepage_genre_lane_slugs = nil
      @llm_enrichment_model = nil
      @llm_enrichment_prompt_template = nil
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
