// Signature handling: v normalisation, local recovery, dedupe by signer, ascending-owner encoding.
import { concat, recoverAddress } from "viem"
import { WalletError, refuse } from "wallet/errors"

const CURVE_ORDER = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n

function invalid(reason) {
  return new WalletError("invalid_signature_format", { details: { reason } })
}

// Same rules and reasons as Chain::Signature in Ruby: 65 bytes, r and s in range, low-s only, v 27/28.
// v 0/1 from some hardware paths becomes 27/28, because the Safe would read a raw 0/1 as a contract
// signature or a pre-approved hash. v 31/32 is refused: we never sign a Safe hash with eth_sign.
export function normalizeSignature(signature) {
  if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) throw invalid("malformed")
  const hex = signature.toLowerCase()
  const r = BigInt(`0x${hex.slice(2, 66)}`)
  const s = BigInt(`0x${hex.slice(66, 130)}`)
  let v = parseInt(hex.slice(130), 16)
  if (v < 2) v += 27
  if (v !== 27 && v !== 28) throw invalid("bad_v")
  if (r < 1n || r >= CURVE_ORDER) throw invalid("bad_r")
  if (s < 1n || s >= CURVE_ORDER) throw invalid("bad_s")
  if (s > CURVE_ORDER / 2n) throw invalid("high_s")
  return `${hex.slice(0, 130)}${v.toString(16)}`
}

export async function recoverSigner(hash, signature) {
  const normalized = normalizeSignature(signature)
  try {
    return (await recoverAddress({ hash, signature: normalized })).toLowerCase()
  } catch (cause) {
    throw new WalletError("invalid_signature_format", { cause, details: { reason: "bad_r" } })
  }
}

// Dedupes by recovered signer, not bytes. Rows from the server that do not recover to an owner are dropped.
export async function validSignatures(stored, hash, owners) {
  const bySigner = new Map()
  const rejected = []
  for (const row of stored) {
    try {
      const signer = await recoverSigner(hash, row.signature)
      if (!owners.includes(signer)) rejected.push({ signer, reason: "not_owner" })
      else if (!bySigner.has(signer)) bySigner.set(signer, normalizeSignature(row.signature))
    } catch {
      rejected.push({ signer: row.signer ?? null, reason: "invalid" })
    }
  }
  const valid = [...bySigner].map(([signer, signature]) => ({ signer, signature }))
  return { valid: sortBySigner(valid), rejected }
}

// Numeric comparison, never string order on checksummed text.
export function sortBySigner(entries) {
  return [...entries].sort((left, right) => {
    const a = BigInt(left.signer)
    const b = BigInt(right.signer)
    return a < b ? -1 : a > b ? 1 : 0
  })
}

// Exactly `threshold` entries, strictly ascending. The contract reads only the first threshold anyway.
export function encodeSignatures(entries, threshold) {
  const count = Number(threshold)
  if (entries.length < count) throw refuse("not_enough_signatures", { have: entries.length, need: count })
  return concat(sortBySigner(entries).slice(0, count).map((entry) => entry.signature))
}
