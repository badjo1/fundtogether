module TransactionsHelper
  def status_badge_class(status)
    case status
    when "confirmed"
      "bg-green-100 text-green-800"
    when "pending"
      "bg-yellow-100 text-yellow-800"
    when "failed"
      "bg-red-100 text-red-800"
    when "cancelled"
      "bg-gray-100 text-gray-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def transaction_status_text(status)
    {
      "confirmed" => "Bevestigd",
      "pending" => "In behandeling",
      "failed" => "Mislukt",
      "cancelled" => "Geannuleerd"
    }[status] || status.capitalize
  end

  def transaction_type_text(type)
    {
      "deposit" => "Storting",
      "expense" => "Uitgave",
      "transfer" => "Overdracht"
    }[type] || type.capitalize
  end
end
