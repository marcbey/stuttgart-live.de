class AppSetting < ApplicationRecord
  SKS_PROMOTER_IDS_KEY = "sks_promoter_ids".freeze
  SKS_ORGANIZER_NOTES_KEY = "sks_organizer_notes".freeze
  MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY = "merge_artist_similarity_matching_enabled".freeze
  LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY = "llm_enrichment_prompt_template".freeze
  LLM_ENRICHMENT_INPUT_PLACEHOLDER = "{{input_json}}".freeze

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

  validates :key, presence: true, uniqueness: true
  validate :sks_promoter_ids_must_be_present
  validate :llm_enrichment_prompt_template_must_be_valid

  after_commit { self.class.reset_cache! }

  class << self
    def sks_promoter_ids
      @sks_promoter_ids ||= normalize_id_list(find_by(key: SKS_PROMOTER_IDS_KEY)&.value)
    end

    def sks_organizer_notes
      @sks_organizer_notes ||= normalize_text(find_by(key: SKS_ORGANIZER_NOTES_KEY)&.value)
    end

    def llm_enrichment_prompt_template
      @llm_enrichment_prompt_template ||=
        normalize_text(find_by(key: LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY)&.value) || LLM_ENRICHMENT_PROMPT_TEMPLATE
    end

    def sks_promoter_ids_record
      find_or_initialize_by(key: SKS_PROMOTER_IDS_KEY)
    end

    def sks_organizer_notes_record
      find_or_initialize_by(key: SKS_ORGANIZER_NOTES_KEY)
    end

    def llm_enrichment_prompt_template_record
      find_or_initialize_by(key: LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).tap do |setting|
        if normalize_text(setting.value).blank?
          setting.value = LLM_ENRICHMENT_PROMPT_TEMPLATE
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

    def reset_cache!
      @sks_promoter_ids = nil
      @sks_organizer_notes = nil
      @llm_enrichment_prompt_template = nil
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

  def llm_enrichment_prompt_template
    template = self.class.normalize_text(value)
    return self.class.llm_enrichment_prompt_template if key == LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY && template.blank?

    template
  end

  def llm_enrichment_prompt_template_text
    llm_enrichment_prompt_template.to_s
  end

  def llm_enrichment_prompt_template_text=(raw_value)
    self.value = self.class.normalize_text(raw_value)
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
end
