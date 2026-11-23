class ApplicationController < ActionController::Base
  include Authentication

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Nothing in Flatline belongs in a search engine.
  after_action { response.set_header("X-Robots-Tag", "noindex, nofollow") }
end
