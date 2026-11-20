// Gas preflight: the wallet pays, and a clear Dutch message beats a wallet's raw error.
import { MESSAGES, WalletError } from "wallet/errors"
import { formatAmount } from "safe/amounts"

const BUFFER_PERCENT = 130n

export function gasMessage(chain) {
  return `${MESSAGES.insufficient_gas} Nodig: ${chain.nativeCurrency.symbol} op ${chain.name}.`
}

// Returns the buffered gas limit as hex. A too-low limit only gives a retryable GS013, so 30% is a
// judgement call. L2 data fees are not in eth_gasPrice; the wallet's own check still applies.
export async function preflightGas(reader, { from, to, data, value = 0n, chain }) {
  const balance = await reader.nativeBalance(from)
  if (balance === 0n) throw new WalletError("insufficient_gas", { message: gasMessage(chain), details: { balance: "0" } })

  const tx = { from, to, data, value: `0x${value.toString(16)}` }
  let gas
  try {
    gas = await reader.estimateGas(tx)
  } catch (error) {
    if (error.code === "insufficient_gas") {
      throw new WalletError("insufficient_gas", { message: gasMessage(chain), cause: error })
    }
    throw error
  }

  const limit = (gas * BUFFER_PERCENT) / 100n
  const cost = limit * await reader.gasPrice() + value
  if (balance < cost) {
    const { symbol, decimals } = chain.nativeCurrency
    throw new WalletError("insufficient_gas", {
      message: `${gasMessage(chain)} Schatting: ${formatAmount(cost, decimals, { minimumFractionDigits: 0 })} ${symbol}.`,
      details: { balance: balance.toString(), cost: cost.toString() }
    })
  }
  return `0x${limit.toString(16)}`
}
