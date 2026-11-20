class ChainEventsController < ChainApiController
  PAGE_SIZE = 50
  CSV_LIMIT = 10_000

  before_action :set_fund

  def index
    events = @account.chain_events.includes(:user, :safe_proposal).recent_first
    if request.format.csv?
      export(events)
    else
      render json: index_json(events)
    end
  end

  private

  def export(events)
    return render_error("safe_not_active", Chain::Refusal::MESSAGES.fetch("safe_not_active"), status: :conflict) unless @account.chain

    send_data Chain::CsvExport.events(@account, events.limit(CSV_LIMIT)), type: "text/csv; charset=utf-8",
              filename: "fundtogether-#{@account.id}-activiteit.csv"
  end

  def index_json(events)
    page = page_param
    { events: events.limit(PAGE_SIZE).offset((page - 1) * PAGE_SIZE).map { |event| event_json(event) }, page: page,
      synced_block: @account.synced_block&.to_s, synced_at: @account.synced_at&.utc&.iso8601 }
  end

  def event_json(event)
    { id: event.id, kind: event.kind, label: ChainEvent::LABELS.fetch(event.kind), status: event.status_label,
      finalized: event.finalized, tx_hash: event.tx_hash, log_index: event.log_index, block_number: event.block_number.to_s,
      from: event.from_address, to: event.to_address, token_address: event.token_address, amount: event.amount&.to_i&.to_s,
      occurred_at: event.occurred_at.utc.iso8601, member: event.user && { id: event.user_id, name: event.user.display_name },
      safe_tx_hash: event.safe_tx_hash, safe_proposal_id: event.safe_proposal_id }
  end
end
