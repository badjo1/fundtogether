// Chain reads over an EIP-1193 provider: the user's wallet, or the RPC from the page's chain config.
// Server JSON is never a source for owners, threshold or nonce.
import { decodeFunctionResult, encodeFunctionData } from "viem"
import { parseChainId } from "wallet/chains"
import { WalletError, normalizeError } from "wallet/errors"
import { ERC20_ABI, SAFE_ABI } from "safe/abi"
import { GUARD_SLOT, FALLBACK_SLOT, SENTINEL_OWNERS, SINGLETON_SLOT } from "safe/constants"

function wordToAddress(word) {
  return `0x${String(word).slice(-40).toLowerCase()}`
}

export function createRpcProvider(urls, { fetch: fetchFn = globalThis.fetch?.bind(globalThis) } = {}) {
  let id = 0
  return {
    async request({ method, params = [] }) {
      let lastError = null
      for (const url of urls) {
        try {
          id += 1
          const response = await fetchFn(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            credentials: "omit",
            body: JSON.stringify({ jsonrpc: "2.0", id, method, params })
          })
          if (!response.ok) throw new Error(`RPC HTTP ${response.status}`)
          const payload = await response.json()
          if (payload.error) {
            // A revert is an answer, not an outage: another endpoint would say the same.
            const answer = Object.assign(new Error(payload.error.message), { code: payload.error.code, data: payload.error.data, rpcAnswer: true })
            throw answer
          }
          return payload.result
        } catch (error) {
          if (error.rpcAnswer) throw error
          lastError = error
        }
      }
      throw new WalletError("chain_read_failed", { cause: lastError })
    }
  }
}

export function createReader(provider) {
  async function rpc(method, params = []) {
    try {
      return await provider.request({ method, params })
    } catch (raw) {
      if (raw instanceof WalletError) throw raw
      throw new WalletError("chain_read_failed", { cause: raw, details: { method } })
    }
  }

  async function call(address, abi, functionName, args = [], overrides = {}) {
    const data = encodeFunctionData({ abi, functionName, args })
    const result = await rpc("eth_call", [{ to: address, data, ...overrides }, "latest"])
    try {
      return decodeFunctionResult({ abi, functionName, data: result })
    } catch (cause) {
      // An empty result means no contract there, or a contract without this function.
      throw new WalletError("chain_read_failed", { cause, details: { functionName, address } })
    }
  }

  return {
    rpc,
    call,

    async chainId() {
      return parseChainId(await rpc("eth_chainId"))
    },

    async assertChain(expected) {
      const actual = await this.chainId()
      if (actual !== expected) throw new WalletError("chain_read_mismatch", { details: { expected, actual } })
    },

    async hasCode(address) {
      const code = await rpc("eth_getCode", [address, "latest"])
      return typeof code === "string" && code !== "0x" && code !== "0x0" && code !== ""
    },

    async storageAddress(address, slot) {
      return wordToAddress(await rpc("eth_getStorageAt", [address, slot, "latest"]))
    },

    singleton(safe) {
      return this.storageAddress(safe, SINGLETON_SLOT)
    },

    guard(safe) {
      return this.storageAddress(safe, GUARD_SLOT)
    },

    fallbackHandler(safe) {
      return this.storageAddress(safe, FALLBACK_SLOT)
    },

    async owners(safe) {
      const owners = await call(safe, SAFE_ABI, "getOwners")
      return owners.map((owner) => owner.toLowerCase())
    },

    threshold(safe) {
      return call(safe, SAFE_ABI, "getThreshold")
    },

    nonce(safe) {
      return call(safe, SAFE_ABI, "nonce")
    },

    async modules(safe) {
      const [modules] = await call(safe, SAFE_ABI, "getModulesPaginated", [SENTINEL_OWNERS, 10n])
      return modules.map((module) => module.toLowerCase())
    },

    onChainTransactionHash(safe, tx) {
      return call(safe, SAFE_ABI, "getTransactionHash", [
        tx.to, tx.value, tx.data, tx.operation, tx.safeTxGas, tx.baseGas, tx.gasPrice, tx.gasToken, tx.refundReceiver, tx.nonce
      ])
    },

    async nativeBalance(address) {
      return BigInt(await rpc("eth_getBalance", [address, "latest"]))
    },

    tokenBalance(token, address) {
      return call(token, ERC20_ABI, "balanceOf", [address])
    },

    async tokenDecimals(token) {
      return Number(await call(token, ERC20_ABI, "decimals"))
    },

    async gasPrice() {
      return BigInt(await rpc("eth_gasPrice"))
    },

    receipt(hash) {
      return rpc("eth_getTransactionReceipt", [hash])
    },

    transaction(hash) {
      return rpc("eth_getTransactionByHash", [hash])
    },

    // Revert details matter here, so errors keep their original form for revertCode.
    async estimateGas(tx) {
      try {
        return BigInt(await provider.request({ method: "eth_estimateGas", params: [tx] }))
      } catch (raw) {
        throw normalizeError(raw)
      }
    }
  }
}
