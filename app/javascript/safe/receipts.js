// A receipt's status alone is not success: status 1 can still carry ExecutionFailure, which burns
// the nonce. Nothing is shown as done until these functions say so.
import { WalletError } from "wallet/errors"
import { TOPICS } from "safe/constants"

const POLL_MS = 3_000
const TIMEOUT_MS = 10 * 60_000

function isStatusOk(receipt) {
  return receipt.status === "0x1" || receipt.status === 1 || receipt.status === "success"
}

function sameTopic(left, right) {
  return String(left).toLowerCase() === String(right).toLowerCase()
}

function logsFrom(receipt, address) {
  return (receipt.logs || []).filter((log) => String(log.address).toLowerCase() === address)
}

function topicAddress(topic) {
  return `0x${String(topic).slice(-40).toLowerCase()}`
}

export async function waitForReceipt(reader, hash, { intervalMs = POLL_MS, timeoutMs = TIMEOUT_MS, sleep = defaultSleep, now = Date.now } = {}) {
  const deadline = now() + timeoutMs
  while (true) {
    let receipt = null
    try {
      receipt = await reader.receipt(hash)
    } catch (error) {
      // An RPC hiccup during polling is not a transaction result. Keep polling until the deadline.
      if (now() >= deadline) throw error
    }
    if (receipt) return receipt
    if (now() >= deadline) throw new WalletError("receipt_timeout", { details: { hash } })
    await sleep(intervalMs)
  }
}

function defaultSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// "success" | "failure" (nonce burned) | "reverted" (nothing consumed) | "unconfirmed" (no matching event)
export function interpretExecution(receipt, { safe, safeTxHash }) {
  if (!isStatusOk(receipt)) return "reverted"
  const logs = logsFrom(receipt, safe)
  const matches = (topic) => logs.some((log) => sameTopic(log.topics?.[0], topic) && sameTopic(log.topics?.[1], safeTxHash))
  if (matches(TOPICS.executionSuccess)) return "success"
  if (matches(TOPICS.executionFailure)) return "failure"
  return "unconfirmed"
}

export function interpretTransfer(receipt, { token, from, to, amount }) {
  if (!isStatusOk(receipt)) return "reverted"
  const found = logsFrom(receipt, token).some((log) => (
    sameTopic(log.topics?.[0], TOPICS.transfer) &&
    topicAddress(log.topics?.[1]) === from &&
    topicAddress(log.topics?.[2]) === to &&
    BigInt(log.data) === amount
  ))
  return found ? "success" : "unconfirmed"
}

export function proxyCreatedAt(receipt, { factory, proxy }) {
  if (!isStatusOk(receipt)) return false
  return logsFrom(receipt, factory).some((log) => (
    sameTopic(log.topics?.[0], TOPICS.proxyCreation) && topicAddress(log.topics?.[1]) === proxy
  ))
}

export function receiptSucceeded(receipt) {
  return isStatusOk(receipt)
}
