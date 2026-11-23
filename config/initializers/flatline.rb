# Settings that come from the environment. Everything is configured through
# environment variables (see README), so the public repo holds no secrets.
module Flatline
  VERSION = "1.0.0"

  # Linked from the User-Agent header that every check sends, so website
  # owners can see what is visiting them.
  REPOSITORY_URL = ENV.fetch("FLATLINE_REPOSITORY_URL", "https://github.com/antekonjevic/flatline")

  USER_AGENT = "Flatline/#{VERSION} (uptime monitor; +#{REPOSITORY_URL})"

  # Password "flatline", used only in development when no digest is set.
  DEVELOPMENT_PASSWORD = "flatline"

  def self.password_digest
    ENV["FLATLINE_PASSWORD_DIGEST"].presence ||
      (Rails.env.local? ? development_password_digest : nil)
  end

  def self.development_password_digest
    @development_password_digest ||= BCrypt::Password.create(DEVELOPMENT_PASSWORD, cost: BCrypt::Engine::MIN_COST)
  end
end
