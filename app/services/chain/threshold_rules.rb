module Chain
  # At least 1, at most the owner count. n-of-n and 1-of-n (n > 1) need an explicit "I understand":
  # one lost key locks the fund, or one key controls it.
  module ThresholdRules
    module_function

    def check!(owner_count:, threshold:, acknowledge_risk: false)
      raise Refusal.new("threshold_out_of_range") unless threshold.is_a?(Integer) && threshold.between?(1, owner_count)
      raise Refusal.new("risk_not_acknowledged") if risky?(owner_count, threshold) && acknowledge_risk != true
    end

    def risky?(owner_count, threshold)
      owner_count > 1 && (threshold == 1 || threshold == owner_count)
    end

    # Accepts a JSON integer or a decimal string. Anything else is out of range.
    def parse(value)
      return value if value.is_a?(Integer)

      value.to_i if value.is_a?(String) && value.match?(/\A\d{1,6}\z/)
    end
  end
end
