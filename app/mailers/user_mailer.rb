class UserMailer < ApplicationMailer
  def email_confirmation(user)
    @user = user
    @url = email_confirmation_url(user.generate_token_for(:email_confirmation))
    mail(subject: "Bevestig je e-mailadres - FundTogether", to: user.email_address)
  end

  # Wallet changes decide who signs. A stolen session must not be able to change them unnoticed (M5).
  def wallet_linked(user, address)
    @user = user
    @address = Chain::Address.checksum(address)
    mail(subject: "Er is een wallet gekoppeld aan je FundTogether-account", to: user.email_address)
  end

  def wallet_unlinked(user, address)
    @user = user
    @address = Chain::Address.checksum(address)
    mail(subject: "Er is een wallet ontkoppeld van je FundTogether-account", to: user.email_address)
  end
end
