# An address someone typed but never proved, with nothing attached, should not stay taken.
class UnconfirmedUserCleanupJob < ApplicationJob
  queue_as :default

  def perform
    User.abandoned_unconfirmed.find_each(&:destroy)
  end
end
