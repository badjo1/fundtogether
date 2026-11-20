// Strict parsing of values that arrive as JSON. No floats anywhere: a JS number only ever passes for
// small integer fields, and amounts and nonces must be decimal strings as the contract says.
import { isAddress } from "viem"
import { refuse } from "wallet/errors"
import { UINT256_MAX } from "safe/constants"

export function parseAddress(value, code = "proposal_malformed") {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value)) throw refuse(code, { value })
  // Mixed case must carry a valid checksum. All-lowercase is what our server sends.
  if (!isAddress(value, { strict: true })) throw refuse(code, { value })
  return value.toLowerCase()
}

export function parseUintString(value, code = "proposal_malformed") {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value)) throw refuse(code, { value })
  const parsed = BigInt(value)
  if (parsed > UINT256_MAX) throw refuse(code, { value })
  return parsed
}

export function parseSmallUint(value, code = "proposal_malformed") {
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || value < 0) throw refuse(code, { value })
    return BigInt(value)
  }
  return parseUintString(value, code)
}

export function parseHexData(value, code = "proposal_malformed") {
  if (typeof value !== "string" || !/^0x([0-9a-fA-F]{2})*$/.test(value)) throw refuse(code, { value })
  return value.toLowerCase()
}

export function parseBytes32(value, code = "proposal_malformed") {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) throw refuse(code, { value })
  return value.toLowerCase()
}

// Same rule as SafeText on the server: text that can make a line read as something it does not say.
const CONTROLS = /[\p{Cc}\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFE00-\uFE0F\uFEFF\uFFF9-\uFFFB]/gu

export function cleanText(value) {
  return typeof value === "string" ? value.replace(CONTROLS, "").trim() : ""
}
