class ApplicationMailer < ActionMailer::Base
  default from: "Fund Together <noreply@notifications.fundtogether.app>"
  layout "mailer"

  private

  # Never the request: a mail link is the one place a spoofed Host header reaches someone else.
  def default_url_options
    PublicUrl.options
  end
end
