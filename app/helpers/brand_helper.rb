module BrandHelper
  def stuttgart_live_brand_text(text = "STUTTGART LIVE")
    safe_join(text.to_s.split(/(STUTTGART LIVE)/).map do |part|
      if part == "STUTTGART LIVE"
        tag.span(style: "font-weight: 400; white-space: nowrap;") do
          safe_join([ tag.strong("STUTTGART", style: "font-weight: 700;"), "LIVE" ])
        end
      else
        part
      end
    end)
  end
end
