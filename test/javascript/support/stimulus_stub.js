// Minimal stand-in so controllers can be driven under node:test. Real Stimulus wiring is not covered here.
export class Controller {
  constructor(element = fakeElement()) {
    this.element = element
    this.events = []
    // As in real Stimulus, these instance properties shadow any method with the same name.
    this.context = {}
    this.application = {}
    this.scope = {}
  }

  dispatch(name, { detail } = {}) {
    this.events.push({ name, detail })
  }
}

export function fakeElement() {
  return { dataset: {}, isConnected: true }
}
