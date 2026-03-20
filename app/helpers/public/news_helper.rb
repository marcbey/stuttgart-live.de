module Public::NewsHelper
  def public_news_show_presenter(blog_post)
    unless defined?(Public::News::ShowPresenter)
      presenter_path = Rails.root.join("app/presenters/public/news/show_presenter.rb").to_s
      require_dependency presenter_path
      load presenter_path unless defined?(Public::News::ShowPresenter)
    end

    Public::News::ShowPresenter.new(blog_post, view_context: self)
  end
end
