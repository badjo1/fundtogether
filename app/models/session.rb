class Session < ApplicationRecord
  # A stolen session can propose but never sign, so these are about limiting exposure rather than the last line
  # of defence. A person who uses the app every week stays logged in for a month.
  IDLE_LIMIT = 7.days
  ABSOLUTE_LIMIT = 30.days
  LAST_SEEN_PRECISION = 5.minutes

  belongs_to :user

  scope :expired, -> { where(created_at: ...ABSOLUTE_LIMIT.ago).or(where("COALESCE(last_seen_at, created_at) < ?", IDLE_LIMIT.ago)) }

  def usable?
    created_at > ABSOLUTE_LIMIT.ago && (last_seen_at || created_at) > IDLE_LIMIT.ago
  end

  # At most one write every few minutes, not one per request.
  def seen!
    return if last_seen_at && last_seen_at > LAST_SEEN_PRECISION.ago

    update_column(:last_seen_at, Time.current)
  end
end
