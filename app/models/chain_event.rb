class ChainEvent < ApplicationRecord
  KINDS = %w[token_in token_out native_in execution_success execution_failure owner_added owner_removed
             threshold_changed].freeze
  CONTRIBUTION_KINDS = %w[token_in native_in].freeze
  EXECUTION_KINDS = %w[execution_success execution_failure].freeze
  LABELS = { "token_in" => "Inleg", "token_out" => "Uitbetaling", "native_in" => "Inleg (gas-token)",
             "execution_success" => "Uitgevoerd", "execution_failure" => "Mislukt",
             "owner_added" => "Eigenaar toegevoegd", "owner_removed" => "Eigenaar verwijderd",
             "threshold_changed" => "Drempel gewijzigd" }.freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :safe_proposal, optional: true

  validates :kind, inclusion: { in: KINDS }

  # Below this from a sender we cannot name, a row is most likely noise or address poisoning. Hidden behind a
  # toggle on screen, never dropped: the data, totals and CSV keep it.
  DUST_FRACTION_DIGITS = { token: 2, native: 5 }.freeze

  scope :unfinalized, -> { where(finalized: false) }
  scope :unknown_dust, ->(chain) {
    where("(kind = 'token_in' AND user_id IS NULL AND amount < :token) OR (kind = 'native_in' AND user_id IS NULL AND amount < :native)",
          token: 10**[ chain.token.decimals - DUST_FRACTION_DIGITS[:token], 0 ].max, native: 10**(18 - DUST_FRACTION_DIGITS[:native]))
  }
  scope :without_unknown_dust, ->(chain) { where.not(id: unknown_dust(chain).select(:id)) }
  scope :recent_first, -> { order(block_number: :desc, log_index: :desc, id: :desc) }

  def status_label
    finalized ? "definitief" : "in behandeling"
  end
end
