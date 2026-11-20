module Chain
  # Human amounts to and from base units through decimal strings, as app/javascript/safe/amounts.js.
  # Never floats and never rounding: more decimals than the token has is refused, not cut.
  module Amount
    class Invalid < ArgumentError; end

    AMBIGUOUS_FORMAT = /\A[1-9][0-9]{0,2}(\.[0-9]{3})+\z/
    AMBIGUOUS = "Bedoel je met de punt duizendtallen of decimalen? Bedoel je 1 euro, schrijf dan 1,00. Bedoel je duizend, schrijf dan 1000.".freeze

    module_function

    def parse(input, decimals)
      raw = input.to_s.strip
      # Pages write thousands with a dot, so "1.000" could mean a thousand. It would parse as one.
      raise Invalid, AMBIGUOUS if raw.match?(AMBIGUOUS_FORMAT)

      text = raw.sub(",", ".")
      raise Invalid, "Vul een geldig bedrag in, bijvoorbeeld 12,50." unless text.match?(/\A[0-9]{1,60}(\.[0-9]{1,78})?\z/)

      whole, fraction = text.split(".")
      fraction = fraction.to_s
      raise Invalid, "Dit bedrag heeft te veel cijfers achter de komma." if fraction.sub(/0+\z/, "").length > decimals

      units = "#{whole}#{fraction[0, decimals].to_s.ljust(decimals, "0")}".to_i
      raise Invalid, "Vul een bedrag groter dan nul in." if units.zero?
      raise Invalid, "Dit bedrag is te groot." if units > Abi::UINT256_MAX

      units
    end

    # 1234500000, 6 => "1.234,50". Keeps every significant decimal: money is never rounded for display.
    def format(units, decimals, minimum_fraction: 2)
      text = units.to_i.to_s.rjust(decimals + 1, "0")
      whole = decimals.zero? ? text : text[0...-decimals]
      fraction = decimals.zero? ? "" : text[-decimals..].sub(/0+\z/, "")
      fraction = fraction.ljust([ minimum_fraction, decimals ].min, "0")
      grouped = whole.reverse.scan(/\d{1,3}/).join(".").reverse
      fraction.empty? ? grouped : "#{grouped},#{fraction}"
    end
  end
end
