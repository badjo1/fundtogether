class ActivityPagesController < FundPagesController
  PAGE_SIZE = 25
  FILTERS = { "in" => ChainEvent::CONTRIBUTION_KINDS, "out" => %w[token_out],
              "owners" => %w[owner_added owner_removed threshold_changed], "executions" => ChainEvent::EXECUTION_KINDS }.freeze

  def show
    @chain = @account.chain
    @filter = FILTERS.key?(params[:filter]) ? params[:filter] : "all"
    @member_filter = params[:member].is_a?(String) ? params[:member].presence : nil
    @page = params[:page].to_s.to_i.clamp(1, 100_000)
    @show_dust = params[:dust] == "1"
    @members = @account.active_users.order(:name)
    @dust_count = @chain ? filtered_events.unknown_dust(@chain).count : 0
    scoped = @chain && !@show_dust ? filtered_events.without_unknown_dust(@chain) : filtered_events
    @events = scoped.includes(:user, :safe_proposal, :account).recent_first.limit(PAGE_SIZE + 1).offset((@page - 1) * PAGE_SIZE).to_a
    @next_page = @events.length > PAGE_SIZE
    @events = @events.first(PAGE_SIZE)
    @totals = totals
    @has_any_event = @account.chain_events.exists?
  end

  private

  def filtered_events
    events = @account.chain_events
    events = events.where(kind: FILTERS.fetch(@filter)) unless @filter == "all"
    case @member_filter
    when nil then events
    when "unknown" then events.where(user_id: nil, kind: ChainEvent::CONTRIBUTION_KINDS)
    else events.where(user_id: @account.active_users.where(id: @member_filter.to_i).select(:id))
    end
  end

  # Token inflows per member, final and pending apart. user_id nil means an unknown sender.
  def totals
    rows = @account.chain_events.where(kind: "token_in").group(:user_id, :finalized).sum(:amount)
    names = User.where(id: rows.keys.map(&:first).compact).index_by(&:id)
    rows.group_by { |(user_id, _), _| user_id }.map do |user_id, entries|
      amounts = entries.to_h { |(_, finalized), amount| [ finalized, amount.to_i ] }
      { user: names[user_id], final: amounts.fetch(true, 0), pending: amounts.fetch(false, 0) }
    end.sort_by { |row| [ row[:user] ? 0 : 1, -(row[:final] + row[:pending]) ] }
  end
end
