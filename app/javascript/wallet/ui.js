// Small helpers shared by the thin Stimulus controllers. No business logic and no HTML.
import { STEP_MESSAGES, normalizeError } from "wallet/errors"

export function publishStep(controller, step, detail = {}) {
  const message = STEP_MESSAGES[step] || ""
  controller.element.dataset.flowState = step
  if (controller.hasMessageTarget) {
    controller.messageTarget.textContent = message
    delete controller.messageTarget.dataset.tone
  }
  controller.dispatch("step", { detail: { step, message, ...detail } })
}

export function publishError(controller, raw) {
  const error = normalizeError(raw)
  const detail = error.toDetail()
  // The Dutch message is for the person. The raw cause is what a support question needs.
  if (!detail.neutral) console.warn(`[wallet] ${detail.code}`, error.cause ?? error)
  controller.element.dataset.flowState = "error"
  if (controller.hasMessageTarget) {
    controller.messageTarget.textContent = detail.message
    controller.messageTarget.dataset.tone = detail.neutral ? "neutral" : detail.refusal ? "refusal" : "error"
  }
  controller.dispatch("error", { detail })
  return detail
}

export function clearFlowUi(controller) {
  delete controller.element.dataset.flowState
  if (controller.hasMessageTarget) {
    controller.messageTarget.textContent = ""
    delete controller.messageTarget.dataset.tone
  }
}

// Turbo snapshots the page before leaving, so a restored page must not show an old result or hash.
export function resetOnTurboCache(controller, reset) {
  const handler = () => reset()
  document.addEventListener("turbo:before-cache", handler)
  return () => document.removeEventListener("turbo:before-cache", handler)
}

export function fillFields(fieldTargets, values) {
  fieldTargets.forEach((target) => {
    const value = values[target.dataset.field]
    target.textContent = value === undefined || value === null ? "" : String(value)
  })
}

// Runs one flow at a time per controller, so a double click cannot send twice. `work` may return a
// function that dispatches the final event: it runs after release, so a listener can start the next flow.
export async function runExclusive(controller, work) {
  if (controller.flowRunning) return
  controller.flowRunning = true
  let announce = null
  try {
    announce = await work()
  } catch (raw) {
    if (controller.element.isConnected !== false) publishError(controller, raw)
  } finally {
    controller.flowRunning = false
  }
  if (typeof announce === "function") announce()
}
