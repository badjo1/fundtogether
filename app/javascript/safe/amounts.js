// Human amounts to and from base units through decimal strings. Never floats, and never rounding:
// more decimals than the token has is refused, not silently cut.
import { WalletError } from "wallet/errors"
import { UINT256_MAX } from "safe/constants"

const AMBIGUOUS = /^[1-9][0-9]{0,2}(\.[0-9]{3})+$/

export function parseAmount(input, decimals) {
  if (typeof input !== "string") throw new WalletError("invalid_amount")
  // Pages write thousands with a dot, so "1.000" could mean a thousand. It would parse as one.
  if (AMBIGUOUS.test(input.trim())) throw new WalletError("ambiguous_amount")
  const text = input.trim().replace(",", ".")
  if (!/^[0-9]+(\.[0-9]+)?$/.test(text)) throw new WalletError("invalid_amount")
  const [whole, fraction = ""] = text.split(".")
  if (fraction.replace(/0+$/, "").length > decimals) throw new WalletError("too_many_decimals")
  const units = BigInt(whole + fraction.slice(0, decimals).padEnd(decimals, "0"))
  if (units === 0n) throw new WalletError("invalid_amount")
  if (units > UINT256_MAX) throw new WalletError("amount_too_large")
  return units
}

export function formatAmount(units, decimals, { minimumFractionDigits = 2 } = {}) {
  const text = BigInt(units).toString().padStart(decimals + 1, "0")
  const whole = decimals === 0 ? text : text.slice(0, -decimals)
  const rawFraction = decimals === 0 ? "" : text.slice(-decimals)
  const trimmed = rawFraction.replace(/0+$/, "")
  const fraction = trimmed.padEnd(Math.min(minimumFractionDigits, decimals), "0")
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
  return fraction ? `${grouped},${fraction}` : grouped
}

// What the person typed, as we read it. Next to the field, before anything is sent or proposed.
export function echoAmount(input, { decimals, symbol }) {
  const text = String(input ?? "").trim()
  if (text === "") return { ok: false, text: "" }
  try {
    return { ok: true, text: `Dat is precies ${formatAmount(parseAmount(text, decimals), decimals)} ${symbol}.` }
  } catch (error) {
    return { ok: false, text: error.message }
  }
}
