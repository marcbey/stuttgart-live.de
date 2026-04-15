require "cgi"
require "fileutils"
require "net/http"

module Meta
  class SocialCardRenderer
    RenderedCard = Data.define(:binary, :content_type, :filename, :width, :height, :artist_lines, :title_lines, :venue_text)
    TextLayer = Data.define(:image, :x, :y)
    ARTIST_FONT_NAME = "DejaVu Sans Bold".freeze
    BODY_FONT_NAME = "DejaVu Sans".freeze
    Variant = Data.define(
      :key,
      :width,
      :height,
      :frame_inset,
      :content_left,
      :content_right,
      :bottom_padding,
      :artist_font_size,
      :artist_line_height,
      :artist_max_lines,
      :title_font_size,
      :title_line_height,
      :title_max_lines,
      :meta_font_size,
      :meta_gap,
      :title_gap
    )

    VARIANTS = {
      preview: Variant.new(
        key: :preview,
        width: 1080,
        height: 1080,
        frame_inset: 58,
        content_left: 94,
        content_right: 120,
        bottom_padding: 88,
        artist_font_size: 126,
        artist_line_height: 0.86,
        artist_max_lines: 3,
        title_font_size: 58,
        title_line_height: 1.0,
        title_max_lines: 1,
        meta_font_size: 52,
        meta_gap: 30,
        title_gap: 24
      ),
      facebook: Variant.new(
        key: :facebook,
        width: 1080,
        height: 1080,
        frame_inset: 58,
        content_left: 94,
        content_right: 120,
        bottom_padding: 88,
        artist_font_size: 126,
        artist_line_height: 0.86,
        artist_max_lines: 3,
        title_font_size: 58,
        title_line_height: 1.0,
        title_max_lines: 1,
        meta_font_size: 52,
        meta_gap: 30,
        title_gap: 24
      ),
      instagram: Variant.new(
        key: :instagram,
        width: 1080,
        height: 1350,
        frame_inset: 58,
        content_left: 94,
        content_right: 120,
        bottom_padding: 104,
        artist_font_size: 126,
        artist_line_height: 0.86,
        artist_max_lines: 4,
        title_font_size: 58,
        title_line_height: 1.0,
        title_max_lines: 1,
        meta_font_size: 52,
        meta_gap: 30,
        title_gap: 24
      )
    }.freeze
    FONT_CONFIG_MUTEX = Mutex.new
    FONT_CONFIG_PATH = Rails.root.join("tmp", "meta-social-card-fonts.conf").freeze
    FONT_CACHE_PATH = Rails.root.join("tmp", "fontconfig-cache").freeze
    SYSTEM_FONT_CONFIG_PATH = "/etc/fonts/fonts.conf".freeze
    SYSTEM_FONT_DIRECTORIES = [
      "/usr/share/fonts",
      "/usr/local/share/fonts"
    ].freeze
    DEFAULT_ZOOM = 100.0
    BACKGROUND_DIMMER_ALPHA = 0.18

    def initialize(remote_image_fetcher: nil)
      @remote_image_fetcher = remote_image_fetcher || method(:fetch_remote_image)
    end

    def render_set(background_source:, card_payload:, slug:)
      return {} if background_source.blank?

      VARIANTS.transform_values do |variant|
        render_variant(
          variant:,
          background_source:,
          card_payload:,
          slug:
        )
      end
    end

    private

    attr_reader :remote_image_fetcher

    def render_variant(variant:, background_source:, card_payload:, slug:)
      ensure_font_config!

      background = prepared_background(background_source:, variant:)
      artist_lines = wrap_lines(
        card_payload.fetch(:artist_name),
        font_name: ARTIST_FONT_NAME,
        font_size: variant.artist_font_size,
        max_width: text_width_for(variant),
        max_lines: variant.artist_max_lines,
        uppercase: true
      )
      title_lines = wrap_lines(
        card_payload.fetch(:title),
        font_name: BODY_FONT_NAME,
        font_size: variant.title_font_size,
        max_width: text_width_for(variant),
        max_lines: variant.title_max_lines
      )
      date_text = card_payload.fetch(:date_label).to_s.strip
      venue_text = fitted_meta_venue_text(card_payload.fetch(:venue_label), date_text:, variant:)

      overlay = Vips::Image.new_from_buffer(
        overlay_svg(variant:),
        "",
        access: :sequential
      )
      card = background.composite2(overlay, :over)
      card = composite_text_layers(
        card,
        text_layers_for(
          variant:,
          artist_lines:,
          title_lines:,
          date_text:,
          venue_text:
        )
      )

      RenderedCard.new(
        binary: card.write_to_buffer(".png"),
        content_type: "image/png",
        filename: "#{slug}-#{variant.key}-social-card.png",
        width: variant.width,
        height: variant.height,
        artist_lines:,
        title_lines:,
        venue_text:
      )
    end

    def prepared_background(background_source:, variant:)
      image = load_background_image(background_source)
      image = image.autorot
      image = image.flatten(background: [ 0, 0, 0 ]) if image.has_alpha?
      image = image.colourspace(:srgb)
      image = image.extract_band(0, n: 3) if image.bands > 3

      scale = [
        variant.width.to_f / image.width,
        variant.height.to_f / image.height
      ].max * zoom_factor(background_source.zoom)
      resized = image.resize(scale, kernel: :lanczos3)

      left = crop_offset(
        focus: background_source.focus_x,
        target_size: variant.width,
        scaled_size: resized.width
      )
      top = crop_offset(
        focus: background_source.focus_y,
        target_size: variant.height,
        scaled_size: resized.height
      )

      cropped = resized.extract_area(left, top, variant.width, variant.height)
      cropped.linear(1 - BACKGROUND_DIMMER_ALPHA, 0).bandjoin(255)
    end

    def load_background_image(background_source)
      buffer =
        case background_source.source_type
        when :attachment
          background_source.attachment.download
        when :remote_url
          remote_image_fetcher.call(background_source.remote_url)
        else
          raise Error, "Unbekannte Bildquelle für Social Card."
        end

      Vips::Image.new_from_buffer(buffer, "", access: :sequential)
    rescue ActiveStorage::FileNotFoundError, URI::InvalidURIError, Vips::Error => error
      raise Error, "Social-Post-Bild konnte nicht gerendert werden: #{error.message}"
    end

    def overlay_svg(variant:)
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="#{variant.width}" height="#{variant.height}" viewBox="0 0 #{variant.width} #{variant.height}">
          <defs>
            <linearGradient id="social-card-shade" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="rgba(0,0,0,0.10)" />
              <stop offset="42%" stop-color="rgba(0,0,0,0.24)" />
              <stop offset="68%" stop-color="rgba(0,0,0,0.58)" />
              <stop offset="100%" stop-color="rgba(0,0,0,0.88)" />
            </linearGradient>
          </defs>
          <rect x="0" y="0" width="#{variant.width}" height="#{variant.height}" fill="url(#social-card-shade)" />
          <rect x="#{variant.frame_inset}" y="#{variant.frame_inset}" width="#{variant.width - (variant.frame_inset * 2)}" height="#{variant.height - (variant.frame_inset * 2)}" fill="none" stroke="rgba(255,255,255,0.98)" stroke-width="3" />
        </svg>
      SVG
    end

    def text_layers_for(variant:, artist_lines:, title_lines:, date_text:, venue_text:)
      artist_step = line_step(variant.artist_font_size, variant.artist_line_height)
      title_step = line_step(variant.title_font_size, variant.title_line_height)
      artist_block_height = block_height(artist_lines.size, variant.artist_font_size, artist_step)
      title_block_height = block_height(title_lines.size, variant.title_font_size, title_step)
      total_height = artist_block_height + variant.meta_font_size + variant.meta_gap
      total_height += variant.title_gap + title_block_height if title_lines.any?
      top = variant.height - variant.bottom_padding - total_height
      current_y = top
      layers = []

      artist_lines.each do |line|
        layers << text_layer(
          text: line,
          x: variant.content_left,
          y: current_y,
          font_family: ARTIST_FONT_NAME,
          font_size: variant.artist_font_size,
          color: [ 255, 255, 255 ],
          opacity: 0.98
        )
        current_y += artist_step
      end

      if title_lines.any?
        current_y += variant.title_gap
        title_lines.each do |line|
          layers << text_layer(
            text: line,
            x: variant.content_left,
            y: current_y,
            font_family: BODY_FONT_NAME,
            font_size: variant.title_font_size,
            color: [ 255, 255, 255 ],
            opacity: 0.92
          )
          current_y += title_step
        end
      end

      current_y += variant.meta_gap
      date_width = measure_text(date_text, font_name: BODY_FONT_NAME, font_size: variant.meta_font_size)
      venue_x = variant.content_left + date_width + 26

      layers << text_layer(
        text: date_text,
        x: variant.content_left,
        y: current_y,
        font_family: BODY_FONT_NAME,
        font_size: variant.meta_font_size,
        color: [ 255, 255, 255 ],
        opacity: 0.98
      )

      if venue_text.present?
        layers << text_layer(
          text: venue_text,
          x: venue_x,
          y: current_y,
          font_family: BODY_FONT_NAME,
          font_size: variant.meta_font_size,
          color: [ 255, 255, 255 ],
          opacity: 0.98
        )
      end

      layers
    end

    def fitted_meta_venue_text(venue_text, date_text:, variant:)
      normalized = venue_text.to_s.strip.upcase
      return "" if normalized.blank?

      available_width = [ text_width_for(variant) - measure_text(date_text, font_name: BODY_FONT_NAME, font_size: variant.meta_font_size) - 26, 0 ].max
      fit_text(normalized, font_name: BODY_FONT_NAME, font_size: variant.meta_font_size, max_width: available_width)
    end

    def wrap_lines(text, font_name:, font_size:, max_width:, max_lines:, uppercase: false)
      normalized = normalized_text(text, uppercase:)
      return [] if normalized.blank?
      return [ fit_text(normalized, font_name:, font_size:, max_width:) ] if max_lines <= 1

      words = normalized.split(/\s+/)
      lines = []
      current_line = +""

      until words.empty?
        candidate_word = words.first
        candidate_line = current_line.present? ? "#{current_line} #{candidate_word}" : candidate_word

        if measure_text(candidate_line, font_name:, font_size:) <= max_width
          current_line = candidate_line
          words.shift
          next
        end

        if current_line.blank?
          fitted_word, remainder = split_word(candidate_word, font_name:, font_size:, max_width:)
          lines << fitted_word
          words[0] = remainder if remainder.present?
          words.shift if remainder.blank?
        else
          lines << current_line
          current_line = +""
        end

        break if lines.size >= max_lines
      end

      lines << current_line if current_line.present? && lines.size < max_lines
      return lines if words.empty? && lines.size <= max_lines

      visible_lines = lines.first(max_lines)
      overflow_text = ([ visible_lines.pop ] + words).compact.join(" ")
      visible_lines << fit_text("#{overflow_text}...", font_name:, font_size:, max_width:)
      visible_lines
    end

    def fit_text(text, font_name:, font_size:, max_width:)
      normalized = normalized_text(text)
      return "" if normalized.blank? || max_width <= 0
      return normalized if measure_text(normalized, font_name:, font_size:) <= max_width

      trimmed = normalized.delete_suffix("...")

      while trimmed.present?
        candidate = "#{trimmed.rstrip}..."
        return candidate if measure_text(candidate, font_name:, font_size:) <= max_width

        trimmed = trimmed[0...-1]
      end

      "..."
    end

    def split_word(word, font_name:, font_size:, max_width:)
      fitted = +""

      word.each_char do |character|
        candidate = "#{fitted}#{character}"
        break if fitted.present? && measure_text(candidate, font_name:, font_size:) > max_width

        fitted = candidate
      end

      fitted = word[0] if fitted.blank?
      remainder = word.delete_prefix(fitted)
      [ fitted, remainder.presence ]
    end

    def normalized_text(text, uppercase: false)
      value = text.to_s.gsub(/\s+/, " ").strip
      uppercase ? value.upcase : value
    end

    def text_width_for(variant)
      variant.width - variant.content_left - variant.content_right
    end

    def measure_text(text, font_name:, font_size:)
      return 0 if text.blank?

      Vips::Image.text(CGI.escapeHTML(text.to_s), font: "#{font_name} #{font_size}", rgba: true).width
    end

    def composite_text_layers(base_image, layers)
      return base_image if layers.empty?

      positioned_layers = layers.map do |layer|
        layer.image.embed(
          layer.x,
          layer.y,
          base_image.width,
          base_image.height,
          extend: :background,
          background: [ 0, 0, 0, 0 ]
        ).copy(interpretation: :srgb)
      end

      base_image.composite(positioned_layers, Array.new(positioned_layers.size, "over"))
    end

    def text_layer(text:, x:, y:, font_family:, font_size:, color:, opacity:)
      rendered_text = Vips::Image.text(
        CGI.escapeHTML(text.to_s),
        font: "#{font_family} #{font_size}",
        rgba: true
      )
      alpha = rendered_text.extract_band(3).linear(opacity, 0)
      rgb = rendered_text.new_from_image(color)
      rgba = rgb.bandjoin(alpha).copy(interpretation: :srgb)

      TextLayer.new(image: rgba, x:, y:)
    end

    def line_step(font_size, line_height)
      (font_size * line_height).round
    end

    def block_height(line_count, font_size, step)
      return 0 if line_count <= 0

      font_size + ((line_count - 1) * step)
    end

    def crop_offset(focus:, target_size:, scaled_size:)
      max_offset = [ scaled_size - target_size, 0 ].max
      return 0 if max_offset.zero?

      focus_ratio = [ [ focus.to_f, 0.0 ].max, 100.0 ].min / 100.0
      desired = (scaled_size * focus_ratio) - (target_size / 2.0)
      [ [ desired.round, 0 ].max, max_offset ].min
    end

    def zoom_factor(zoom)
      value = zoom.to_f
      value = DEFAULT_ZOOM if value <= 0
      value / 100.0
    end

    def ensure_font_config!
      FONT_CONFIG_MUTEX.synchronize do
        config_xml = font_config_xml
        FileUtils.mkdir_p(FONT_CACHE_PATH)
        existing_config = File.exist?(FONT_CONFIG_PATH) ? File.read(FONT_CONFIG_PATH) : nil
        File.write(FONT_CONFIG_PATH, config_xml) if existing_config != config_xml
        ENV["FONTCONFIG_FILE"] = FONT_CONFIG_PATH.to_s
      end
    end

    def font_config_xml
      <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
        <fontconfig>
          <include ignore_missing="yes">#{SYSTEM_FONT_CONFIG_PATH}</include>
          <dir>#{Rails.root.join("app/assets/fonts")}</dir>
          #{SYSTEM_FONT_DIRECTORIES.map { |directory| "<dir>#{directory}</dir>" }.join("\n  ")}
          <cachedir>#{FONT_CACHE_PATH}</cachedir>
          <config></config>
        </fontconfig>
      XML
    end

    def fetch_remote_image(url, limit: 3)
      raise Error, "Ungültige Bild-URL für Social Card." if limit <= 0

      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        redirect_url = response["location"].to_s
        raise Error, "Social-Post-Bild konnte nicht geladen werden." if redirect_url.blank?

        fetch_remote_image(redirect_url, limit: limit - 1)
      else
        raise Error, "Social-Post-Bild konnte nicht geladen werden (HTTP #{response.code})."
      end
    end
  end
end
