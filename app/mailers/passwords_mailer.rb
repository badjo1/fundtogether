class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail(
      subject: "Wachtwoord resetten - Fund Together",
      to: user.email_address
    )
  end
end
