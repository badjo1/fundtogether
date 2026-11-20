class ApplicationController < ActionController::Base
  include Authentication
  include FundAuthorization

  # PostgreSQL refuses NUL, so without this it surfaces as a 500 in whatever query comes first.
  prepend_before_action :refuse_null_bytes
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def refuse_null_bytes
    head :bad_request if null_byte_in?(request.path_parameters) || null_byte_in?(request.query_parameters) || null_byte_in?(request.request_parameters)
  end

  def null_byte_in?(value)
    case value
    when Hash then value.any? { |key, entry| null_byte_in?(key) || null_byte_in?(entry) }
    when Array then value.any? { |entry| null_byte_in?(entry) }
    when String then value.include?("\u0000")
    else false
    end
  end
end
