module Public::PagesHelper
  def public_page_body(page)
    fragment = Nokogiri::HTML::DocumentFragment.parse(page.body.to_s)
    fragment.css("h1").each { |heading| heading.name = "h2" }
    fragment.to_html.html_safe
  end
end
