module Chain
  # Hand-written CSV (Ruby 3.4 no longer bundles the csv gem by default and no gem may be added).
  # Spreadsheets execute cells starting with these characters, and member names are user input.
  module CsvExport
    FORMULA_START = /\A[[:space:]]*[=+\-@\t\r]/
    # Dutch Excel splits on ";", so a formula can start after a separator inside a quoted cell.
    FORMULA_AFTER_SEPARATOR = /[;,\t][[:space:]]*[=+\-@]/
    HEADERS = %w[datum soort status van naar lid bedrag_basiseenheden token tx_hash log_index blok].freeze

    module_function

    def events(account, events)
      rows = events.map do |event|
        to, amount, symbol = figures(account, event)
        [ event.occurred_at.utc.iso8601, ChainEvent::LABELS.fetch(event.kind), event.status_label, event.from_address,
          to, event.user&.display_name, amount, symbol, event.tx_hash, event.log_index, event.block_number ]
      end
      ([ HEADERS ] + rows).map { |row| row.map { |cell| cell(cell) }.join(",") }.join("\r\n") + "\r\n"
    end

    # A native transfer emits no event of its own: recipient and amount come from the proposal the chain named.
    def figures(account, event)
      proposal = event.safe_proposal if event.kind == "execution_success"
      if proposal&.kind == "transfer_native"
        [ proposal.params["recipient"], proposal.params["amount"], account.chain.native_symbol ]
      elsif proposal&.kind == "transfer_token"
        [ proposal.params["recipient"], proposal.params["amount"], account.chain.token.symbol ]
      else
        [ event.to_address, event.amount&.to_i&.to_s, event.token_address ? account.chain.token.symbol : nil ]
      end
    end

    def cell(value)
      text = value.to_s
      text = "'#{text}" if text.match?(FORMULA_START) || text.match?(FORMULA_AFTER_SEPARATOR)
      %("#{text.gsub('"', '""')}")
    end
  end
end
