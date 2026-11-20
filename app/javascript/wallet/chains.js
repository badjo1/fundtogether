// The page's chain config, passed through a data-*-chain-value attribute. See docs/FRONTEND_CONTRACT.md.
import { WalletError } from "wallet/errors"

export function parseChainId(value) {
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return value
  if (typeof value === "string" && /^(0x[0-9a-fA-F]+|[1-9][0-9]*)$/.test(value)) {
    const parsed = Number(value)
    if (Number.isSafeInteger(parsed) && parsed > 0) return parsed
  }
  return null
}

// Takes the shape of an entry in config/chains.yml, as rendered by Chain::Registry.
export function normalizeChain(config) {
  const chainId = parseChainId(config?.chain_id)
  if (!chainId) throw new WalletError("chain_read_mismatch", { details: { reason: "no chain_id" } })
  const symbol = String(config.native_symbol || "ETH")
  const rpcUrls = (config.rpc_urls || []).filter((url) => /^https:\/\//.test(url) || /^http:\/\/(localhost|127\.0\.0\.1)[:/]/.test(url))
  const explorer = /^https:\/\//.test(config.explorer_url || "") ? [config.explorer_url] : []
  const tokens = config.token ? [config.token] : []
  return Object.freeze({
    chainId,
    name: String(config.name || `Netwerk ${chainId}`),
    nativeCurrency: Object.freeze({ name: symbol, symbol, decimals: 18 }),
    rpcUrls: Object.freeze(rpcUrls),
    blockExplorerUrls: Object.freeze(explorer),
    tokens: Object.freeze(tokens.map((token) => Object.freeze({
      address: String(token.address).toLowerCase(),
      symbol: String(token.symbol),
      decimals: Number(token.decimals)
    })))
  })
}

export function chainIdHex(chainId) {
  return `0x${chainId.toString(16)}`
}

export function addChainParams(chain) {
  const params = {
    chainId: chainIdHex(chain.chainId),
    chainName: chain.name,
    nativeCurrency: { ...chain.nativeCurrency },
    rpcUrls: [...chain.rpcUrls]
  }
  if (chain.blockExplorerUrls.length > 0) params.blockExplorerUrls = [...chain.blockExplorerUrls]
  return params
}
