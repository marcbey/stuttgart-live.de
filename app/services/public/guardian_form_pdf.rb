require "prawn"

module Public
  class GuardianFormPdf
    MARGIN = 42
    FIELD_HEIGHT = 26
    INK = "182B2D"
    GREY = "F2F2F2"
    BORDER = "B5B5B5"

    def initialize(event: nil, venue: nil, date: nil)
      @event = clean_text(event)
      @venue = clean_text(venue)
      @date = formatted_date(date)
    end

    def render
      @pdf = Prawn::Document.new(page_size: "A4", margin: MARGIN,
        info: { Title: "Begleitformular", Author: "STUTTGART LIVE / RUSS Live" })
      configure_fonts
      @fields = []
      @field_font = @pdf.ref!(Type: :Font, Subtype: :Type1, BaseFont: :Helvetica, Encoding: :WinAnsiEncoding)
      form_page
      @pdf.start_new_page
      information_page
      @pdf.state.store.root.data[:AcroForm] = @pdf.ref!(
        Fields: @fields, NeedAppearances: false,
        DR: { Font: { Helv: @field_font } }, DA: "/Helv 11 Tf 0 g"
      )
      @pdf.render
    end

    private

    def clean_text(value)
      value.is_a?(String) ? value.gsub(/[[:cntrl:]]/, " ").squish.first(300) : ""
    end

    def formatted_date(value)
      Date.iso8601(clean_text(value)).strftime("%d.%m.%Y")
    rescue ArgumentError
      ""
    end

    def configure_fonts
      @pdf.font_families.update(
        "Archivo" => {
          normal: Rails.root.join("vendor/fonts/runtime/ArchivoNarrow-Regular.ttf").to_s,
          bold: Rails.root.join("vendor/fonts/runtime/ArchivoNarrow-Bold.ttf").to_s
        },
        "Oswald" => { normal: Rails.root.join("vendor/fonts/runtime/Oswald-400.ttf").to_s }
      )
      @pdf.font "Archivo"
      @pdf.fill_color INK
    end

    def width
      @pdf.bounds.width
    end

    def half_width
      (width - 18) / 2
    end

    def logo
      @pdf.image Rails.root.join("app/assets/images/documents/russ-live-logo.png"),
        at: [ width - 105, 758 ], width: 105
    end

    def title(text, top:, size: 28)
      @pdf.font("Oswald") { @pdf.text_box text, at: [ 0, top ], width: width, height: 100, size: size }
    end

    def label(text, x:, top:, width:)
      @pdf.text_box text, at: [ x, top ], width: width, height: 38, size: 10
    end

    def section(text, top:)
      @pdf.font("Archivo", style: :bold) do
        @pdf.text_box text, at: [ 0, top ], width: width, height: 18, size: 12
      end
      @pdf.stroke_color BORDER
      @pdf.line_width 0.5
      @pdf.stroke_horizontal_line 0, width, at: top - 18
    end

    def form_page
      logo
      label("STUTTGART LIVE / SERVICE", x: 0, top: 757, width: 300)
      title("BEGLEITFORMULAR", top: 735)
      @pdf.text_box "Formular für die Begleitung minderjähriger Besucherinnen und Besucher.\nBitte vollständig ausfüllen und unterschrieben zur Veranstaltung mitbringen.",
        at: [ 0, 691 ], width: width, height: 33, size: 11, leading: 3

      section("01  Veranstaltung", top: 650)
      field("event", "Veranstaltung", top: 622, value: @event)
      field("date", "Datum", top: 575, width: half_width, value: @date)
      field("venue", "Spielstätte", x: half_width + 18, top: 575, width: half_width, value: @venue)

      person_section("02  Minderjährige Person", prefix: "minor", top: 512, second_label: "Geburtsdatum")
      person_section("03  Erziehungsberechtigte Person", prefix: "guardian", top: 380, second_label: "Telefon")
      person_section("04  Begleitperson", prefix: "companion", top: 248, second_label: "Geburtsdatum")

      signature_width = (width - 36) / 3
      input("place_date", "Ort, Datum", x: 0, top: 90, width: signature_width)
      label("Ort, Datum", x: 0, top: 54, width: signature_width)
      [ "Erziehungsberechtigte Person", "Begleitperson" ].each_with_index do |person, index|
        x = (signature_width + 18) * (index + 1)
        @pdf.stroke_color "777777"
        @pdf.stroke_horizontal_line x, x + signature_width, at: 64
        label("Unterschrift\n#{person}", x: x, top: 54, width: signature_width)
      end
      footer("Bitte auch die Hinweise auf Seite 2 beachten.", page: 1)
    end

    def person_section(heading, prefix:, top:, second_label:)
      section(heading, top: top)
      field("#{prefix}_name", "Vor- und Nachname", top: top - 28, width: half_width)
      field("#{prefix}_#{prefix == 'guardian' ? 'phone' : 'birthdate'}", second_label,
        x: half_width + 18, top: top - 28, width: half_width)
      field("#{prefix}_address", "Anschrift (Straße, Hausnummer, PLZ, Ort)", top: top - 77)
    end

    def field(name, caption, x: 0, top:, width: self.width, value: "")
      label(caption, x: x, top: top, width: width)
      input(name, caption, x: x, top: top - 14, width: width, value: value)
    end

    def input(name, caption, x:, top:, width:, value: "")
      @pdf.fill_color GREY
      @pdf.fill_rectangle [ x, top ], width, FIELD_HEIGHT
      @pdf.stroke_color BORDER
      @pdf.line_width 0.5
      @pdf.stroke_rectangle [ x, top ], width, FIELD_HEIGHT
      @pdf.fill_color INK
      if value.present?
        @pdf.text_box value, at: [ x + 6, top - 4 ], width: width - 12, height: FIELD_HEIGHT - 8,
          size: 11, min_font_size: 6, overflow: :shrink_to_fit, valign: :center
      else
        add_text_field(name, caption, x: x, top: top, width: width)
      end
    end

    # The same object belongs to both the page and AcroForm, so values entered in
    # a PDF viewer remain editable and printable when the document is saved.
    def add_text_field(name, caption, x:, top:, width:)
      appearance = @pdf.ref!(Type: :XObject, Subtype: :Form, BBox: [ 0, 0, width, FIELD_HEIGHT ], Resources: {})
      appearance.stream << "q 0.949 g 0 0 #{width} #{FIELD_HEIGHT} re f 0.71 G 0.5 w 0.25 0.25 #{width - 0.5} #{FIELD_HEIGHT - 0.5} re S Q"
      widget = @pdf.ref!(
        Type: :Annot, Subtype: :Widget, FT: :Tx, T: name, TU: caption, V: "",
        Rect: [ x + MARGIN, top + MARGIN - FIELD_HEIGHT, x + MARGIN + width, top + MARGIN ],
        P: @pdf.state.page.dictionary, F: 4, Ff: 0,
        DA: "/Helv 11 Tf 0 g", MK: { BG: [ 0.949 ], BC: [ 0.71 ] },
        BS: { W: 0.5, S: :S }, AP: { N: appearance }
      )
      (@pdf.state.page.dictionary.data[:Annots] ||= []) << widget
      @fields << widget
    end

    def information_page
      logo
      label("STUTTGART LIVE / HINWEISE", x: 0, top: 757, width: 300)
      title("Jugendschutz durch\nErziehungsbeauftragte", top: 714, size: 26)
      @pdf.move_cursor_to 630
      paragraph("Hinweise für Eltern, Begleitpersonen und Veranstaltungsbesuche von Minderjährigen.", bold: true)
      paragraph("Liebe Eltern,")
      paragraph("nach dem Jugendschutzgesetz haben Sie die Möglichkeit, für die Begleitung Ihres Kindes eine „erziehungsbeauftragte Person” zu benennen. In Begleitung dieser Person, die Sie ausdrücklich beauftragen müssen, sind gestattet:")
      bullets([
        "der Kinobesuch von Kindern unter 6 Jahren",
        "der Besuch von Tanzveranstaltungen durch Kinder und Jugendliche unter 16 Jahren",
        "der Besuch von Gaststätten durch Kinder und Jugendliche unter 16 Jahren",
        "der Besuch dieser Angebote durch ältere Kinder bzw. Jugendliche außerhalb der gesetzlichen Zeitgrenzen"
      ])
      paragraph("Das Gesetz schreibt für die Benennung keine bestimmte Form vor; Sie können gerne das oben abgedruckte Formular verwenden, in das Sie alle wichtigen Informationen eintragen können.")
      paragraph("Bitte bedenken Sie beim Erteilen des Erziehungsauftrages:", bold: true)
      bullets([
        "Die/der Erziehungsbeauftragte muss volljährig sein und sich gegenüber anderen ausweisen können.",
        "Sie/er muss reif genug sein und in der Lage, Ihrem Kind verantwortungsvoll die notwendige Unterstützung zu bieten."
      ])
      paragraph("Prinzipiell gilt: Die/der Erziehungsbeauftragte übernimmt auch in rechtlicher Hinsicht die Verantwortung für Ihr Kind, z. B. die Aufsichtspflicht.")
      paragraph("Überzeugen Sie sich, ob sie/er dieser Aufgabe gewachsen ist:", bold: true)
      bullets([
        "Stellen Sie beim Besuch abendlicher Veranstaltungen sicher, dass Ihr Kind sicher heimfährt.",
        "Stellen Sie sicher, dass die/der Erziehungsbeauftragte während der Begleitung nicht unter Einfluss von Alkohol oder anderen Drogen steht.",
        "Stellen Sie sicher, dass die/der Erziehungsbeauftragte über die Regelungen des Jugendschutzgesetzes Bescheid weiß."
      ])
      paragraph("Wenn Ihr Kind an Veranstaltungen der Kinder- und Jugendhilfe teilnimmt (Kindertageseinrichtungen, Jugendzentren, Jugendgruppen, Sportvereine usw.) sind die jeweiligen Veranstalter Erziehungsbeauftragte im Sinne des Gesetzes, wenn es sich um spezielle Veranstaltungen für Kinder oder Jugendliche handelt. Eine gesonderte Beauftragung ist dann nicht notwendig.")
      paragraph("Dieses Formular dient als Begleitnachweis für minderjährige Besucherinnen und Besucher. Bitte vollständig ausfüllen, ausdrucken und unterschrieben zur Veranstaltung mitbringen.")
      footer("STUTTGART LIVE / RUSS Live", page: 2)
    end

    def paragraph(text, bold: false)
      @pdf.text text, size: 11, leading: 3, style: bold ? :bold : :normal
      @pdf.move_down 9
    end

    def bullets(items)
      items.each do |item|
        @pdf.indent(12) { @pdf.text "•  #{item}", size: 11, leading: 3 }
        @pdf.move_down 4
      end
      @pdf.move_down 5
    end

    def footer(text, page:)
      @pdf.fill_color "666666"
      @pdf.text_box text, at: [ 0, 13 ], width: width - 65, size: 8, height: 13
      @pdf.text_box "#{page} / 2", at: [ width - 50, 13 ], width: 50, align: :right, size: 8, height: 13
      @pdf.fill_color INK
    end
  end
end
