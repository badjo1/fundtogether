module Chain
  # A deliberate "no": code for the browser, Dutch text for the person.
  class Refusal < StandardError
    MESSAGES = {
      "unknown_kind" => "Dit soort voorstel bestaat niet.",
      "unexpected_param" => "Het voorstel bevat een veld dat niet is toegestaan.",
      "invalid_address" => "Dit is geen geldig adres.",
      "invalid_amount" => "Het bedrag moet een positief geheel getal in de kleinste eenheid zijn.",
      "invalid_nonce" => "Dit is geen geldig volgnummer.",
      "invalid_title" => "Geef het voorstel een korte titel.",
      "invalid_tx_hash" => "Dit is geen geldige transactie-hash.",
      "recipient_forbidden" => "Naar dit adres kan niet worden betaald.",
      "owner_forbidden" => "Dit adres kan geen eigenaar van de Safe zijn.",
      "owner_exists" => "Dit adres is al eigenaar van de Safe.",
      "owner_unknown" => "Dit adres is geen eigenaar van de Safe.",
      "last_owner" => "De laatste eigenaar kan niet worden verwijderd.",
      "threshold_out_of_range" => "De drempel moet minstens 1 zijn en mag niet hoger zijn dan het aantal eigenaren.",
      "threshold_unchanged" => "De drempel heeft deze waarde al.",
      "risk_not_acknowledged" => "Bevestig eerst dat je de risico's van deze drempel begrijpt.",
      "operation_not_call" => "Alleen gewone transacties zijn toegestaan.",
      "safe_tx_gas_nonzero" => "Gasvelden moeten nul zijn.",
      "base_gas_nonzero" => "Gasvelden moeten nul zijn.",
      "gas_price_nonzero" => "Gasvelden moeten nul zijn.",
      "gas_token_nonzero" => "Betalen uit de Safe voor gas is niet toegestaan.",
      "refund_receiver_nonzero" => "Betalen uit de Safe voor gas is niet toegestaan.",
      "nonce_too_low" => "Dit volgnummer is al gebruikt op de blockchain.",
      "self_call_forbidden" => "Deze aanroep van de Safe zelf is niet toegestaan.",
      "self_call_value" => "Een aanroep van de Safe zelf mag geen geld meesturen.",
      "token_call_forbidden" => "Alleen een gewone tokenoverboeking is toegestaan.",
      "token_call_value" => "Een tokenoverboeking mag geen gas-token meesturen.",
      "malformed_calldata" => "De transactiegegevens zijn ongeldig.",
      "unknown_target_data" => "Transactiegegevens naar een onbekend contract zijn niet toegestaan.",
      "empty_call" => "Deze transactie doet niets.",
      "to_forbidden" => "Naar dit adres kan niet worden verstuurd.",
      "chain_not_enabled" => "Dit netwerk is niet beschikbaar.",
      "token_not_allowed" => "Deze munt is niet beschikbaar op dit netwerk.",
      "owners_invalid" => "Geef minstens een geldig eigenaar-adres op, zonder dubbele adressen.",
      "owner_not_verified" => "Elke eigenaar moet een geverifieerde wallet van een actief lid zijn.",
      "owner_is_viewer" => "Een lid met alleen leesrechten kan geen eigenaar zijn.",
      "owner_duplicate_member" => "Een lid kan maar met een wallet eigenaar zijn.",
      "safe_locked" => "De Safe is al aangemaakt of wordt aangemaakt. De instellingen liggen vast.",
      "safe_not_configured" => "Stel eerst de Safe in.",
      "safe_not_active" => "De Safe is nog niet actief.",
      "challenge_invalid" => "Deze aanvraag is onbekend. Begin opnieuw.",
      "challenge_expired" => "Deze aanvraag is verlopen. Begin opnieuw.",
      "challenge_consumed" => "Deze aanvraag is al gebruikt. Begin opnieuw.",
      "challenge_address_mismatch" => "Dit adres hoort niet bij deze aanvraag.",
      "invalid_purpose" => "Dit soort aanvraag is niet toegestaan.",
      "invalid_signature" => "De handtekening is ongeldig.",
      "wrong_signer" => "De handtekening komt niet van dit adres.",
      "contract_wallet_refused" => "Contract-wallets worden nog niet ondersteund. Gebruik een gewone wallet.",
      "wallet_taken" => "Deze wallet is al gekoppeld aan een ander account.",
      "deploy_tx_mismatch" => "Deze transactie is niet de aanmaak van de Safe van dit fonds.",
      "email_not_confirmed" => "Bevestig eerst je e-mailadres. Daarna kun je een wallet koppelen.",
      "owner_email_unconfirmed" => "Deze persoon moet eerst het e-mailadres bevestigen voordat de wallet ondertekenaar kan worden.",
      "handoff_invalid" => "Deze link is ongeldig of al gebruikt.",
      "proposal_not_found" => "Niet gevonden.",
      "proposal_not_open" => "Dit voorstel staat niet meer open.",
      "proposal_tampered" => "Dit voorstel is gewijzigd en kan niet worden ondertekend.",
      "proposal_stale" => "Dit volgnummer is al gebruikt. Dit voorstel kan niet meer worden uitgevoerd.",
      "proposal_duplicate" => "Er bestaat al een identiek voorstel.",
      "too_many_open_proposals" => "Je hebt te veel open voorstellen. Trek er eerst een in, of wacht tot er een is afgehandeld.",
      "fund_queue_full" => "Er staan te veel voorstellen open in dit fonds. Een admin kan voorstellen intrekken; een ondertekenaar kan wel nog voorstellen doen.",
      "cancel_forbidden" => "Alleen de indiener of een admin kan dit voorstel intrekken.",
      "cancel_signed_needs_admin" => "Anderen hebben dit voorstel al ondertekend. Alleen een admin kan het nu nog intrekken.",
      "renumber_not_needed" => "Dit voorstel hoeft niet opnieuw te worden gemaakt.",
      "rejection_without_target" => "Er staat geen voorstel open met dit volgnummer.",
      "signer_not_your_wallet" => "Deze handtekening komt niet van een wallet die aan jouw account is gekoppeld.",
      "signer_not_owner" => "Deze wallet is geen eigenaar van de Safe.",
      "already_signed" => "Deze wallet heeft dit voorstel al ondertekend."
    }.freeze

    attr_reader :code, :status

    def initialize(code, status: :unprocessable_entity)
      @code = code
      @status = status
      super(MESSAGES.fetch(code))
    end
  end
end
