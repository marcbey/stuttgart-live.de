if defined?(Bullet)
  bullet_enabled = Rails.env.development? || (Rails.env.test? && ENV["BULLET"].present?)

  if bullet_enabled
    Rails.application.configure do
      config.middleware.use Bullet::Rack

      config.after_initialize do
        Bullet.enable = true
        Bullet.raise = Rails.env.test?
        Bullet.bullet_logger = true
        Bullet.rails_logger = true
        Bullet.console = Rails.env.development?
        Bullet.add_footer = Rails.env.development?
        Bullet.skip_html_injection = !Rails.env.development?
        Bullet.skip_http_headers = Rails.env.test?
        Bullet.n_plus_one_query_enable = true
        Bullet.unused_eager_loading_enable = false
        Bullet.counter_cache_enable = false
      end
    end
  end
end
