module RampsHelper
  VERIFICATION_LABELS = {
    "documentation_read" => "Documentatie gelezen, flow niet gebruikt",
    "partial" => "Deels gecontroleerd, flow niet gebruikt",
    "unverified" => "Niet gecontroleerd"
  }.freeze

  # Every link that leaves FundTogether goes through here.
  def ramp_external_link(*args, **options, &)
    link_to(*args, target: "_blank", rel: "noopener noreferrer", **options, &)
  end

  def ramp_date(date)
    date.strftime("%d-%m-%Y")
  end

  def ramp_verification_label(route)
    VERIFICATION_LABELS.fetch(route.verification_status)
  end

  def ramp_display_address(wallet)
    Chain::Address.checksum(wallet.address)
  end

  # Only ever called with the current user's own active wallet. The form is a prefill: nothing is proposed
  # until the member submits it (docs/FRONTEND_CONTRACT.md, Ramp page).
  def ramp_payout_path(account, wallet)
    new_account_proposal_page_path(account, kind: "transfer_token", recipient: wallet.address)
  end
end
