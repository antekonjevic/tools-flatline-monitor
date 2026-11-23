# One owner, one password. The password's bcrypt hash comes from the
# FLATLINE_PASSWORD_DIGEST environment variable, never from the database.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_sign_in
    helper_method :signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_sign_in, **options
    end
  end

  # Tied to the current password, so changing it signs out every session.
  def self.session_fingerprint
    digest = Flatline.password_digest
    digest && OpenSSL::Digest::SHA256.hexdigest("flatline-session:#{digest}")
  end

  def self.password_matches?(password)
    digest = Flatline.password_digest
    return false if digest.blank? || password.blank?

    BCrypt::Password.new(digest).is_password?(password)
  rescue BCrypt::Errors::InvalidHash
    Rails.logger.error("FLATLINE_PASSWORD_DIGEST is not a valid bcrypt hash; run bin/rails flatline:password")
    false
  end

  private
    def signed_in?
      fingerprint = Authentication.session_fingerprint
      fingerprint.present? && session[:owner].present? &&
        ActiveSupport::SecurityUtils.secure_compare(session[:owner].to_s, fingerprint)
    end

    def require_sign_in
      return if signed_in?

      session[:return_to] = request.fullpath if request.get? || request.head?
      redirect_to new_session_path
    end

    def sign_in
      return_to = session[:return_to]
      reset_session
      session[:owner] = Authentication.session_fingerprint
      return_to
    end

    def sign_out
      reset_session
    end
end
