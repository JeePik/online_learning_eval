class ApplicationController < ActionController::Base

  before_action :force_uk_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

   private
  
  def force_uk_locale
    I18n.locale = :uk
  end

end
