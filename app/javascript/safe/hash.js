// SafeTx EIP-712. The domain has no name or version. The hash is computed twice, through viem's
// typed-data path and by hand from the Safe's own formula, and any difference blocks signing.
import { concat, encodeAbiParameters, hashTypedData, keccak256 } from "viem"
import { refuse } from "wallet/errors"
import { DOMAIN_TYPEHASH, SAFE_TX_TYPEHASH } from "safe/constants"

const SAFE_TX_TYPES = {
  EIP712Domain: [
    { name: "chainId", type: "uint256" },
    { name: "verifyingContract", type: "address" }
  ],
  SafeTx: [
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "data", type: "bytes" },
    { name: "operation", type: "uint8" },
    { name: "safeTxGas", type: "uint256" },
    { name: "baseGas", type: "uint256" },
    { name: "gasPrice", type: "uint256" },
    { name: "gasToken", type: "address" },
    { name: "refundReceiver", type: "address" },
    { name: "nonce", type: "uint256" }
  ]
}

export function domainHash({ chainId, safe }) {
  return keccak256(encodeAbiParameters(
    [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }],
    [DOMAIN_TYPEHASH, BigInt(chainId), safe]
  ))
}

export function messageHash(tx) {
  return keccak256(encodeAbiParameters(
    [
      { type: "bytes32" }, { type: "address" }, { type: "uint256" }, { type: "bytes32" }, { type: "uint8" }, { type: "uint256" },
      { type: "uint256" }, { type: "uint256" }, { type: "address" }, { type: "address" }, { type: "uint256" }
    ],
    [
      SAFE_TX_TYPEHASH, tx.to, tx.value, keccak256(tx.data), tx.operation, tx.safeTxGas,
      tx.baseGas, tx.gasPrice, tx.gasToken, tx.refundReceiver, tx.nonce
    ]
  ))
}

function typedMessage(tx) {
  return {
    to: tx.to,
    value: tx.value,
    data: tx.data,
    operation: tx.operation,
    safeTxGas: tx.safeTxGas,
    baseGas: tx.baseGas,
    gasPrice: tx.gasPrice,
    gasToken: tx.gasToken,
    refundReceiver: tx.refundReceiver,
    nonce: tx.nonce
  }
}

export function safeTxHash({ chainId, safe, tx }) {
  const viaFormula = keccak256(concat(["0x1901", domainHash({ chainId, safe }), messageHash(tx)]))
  const viaTypedData = hashTypedData({
    domain: { chainId: BigInt(chainId), verifyingContract: safe },
    types: SAFE_TX_TYPES,
    primaryType: "SafeTx",
    message: typedMessage(tx)
  })
  if (viaFormula !== viaTypedData) throw refuse("hash_self_check_failed")
  return viaFormula
}

// The JSON the wallet signs. Numbers are decimal strings, chainId is a number (MetaMask #11830).
export function typedDataPayload({ chainId, safe, tx }) {
  return JSON.stringify({
    types: SAFE_TX_TYPES,
    domain: { chainId: Number(chainId), verifyingContract: safe },
    primaryType: "SafeTx",
    message: {
      to: tx.to,
      value: tx.value.toString(),
      data: tx.data,
      operation: tx.operation,
      safeTxGas: tx.safeTxGas.toString(),
      baseGas: tx.baseGas.toString(),
      gasPrice: tx.gasPrice.toString(),
      gasToken: tx.gasToken,
      refundReceiver: tx.refundReceiver,
      nonce: tx.nonce.toString()
    }
  })
}
