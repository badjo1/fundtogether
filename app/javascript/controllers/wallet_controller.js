import { Controller } from "@hotwired/stimulus"
import { normalizeChain } from "wallet/chains"
import { MESSAGES, WALLET_TEXT } from "wallet/errors"
import { deriveStatus, getSession } from "wallet/session"
import { fillFields, publishError, resetOnTurboCache } from "wallet/ui"

// Thin view on the wallet session. Targets, values and events: docs/FRONTEND_CONTRACT.md.
export default class extends Controller {
  static targets = ["message", "field", "providerList", "providerTemplate"]
  static values = {
    userId: String,
    linkedAddresses: Array,
    checksums: Object,
    chain: Object,
    requiresChain: Boolean
  }

  connect() {
    this.session = getSession()
    this.session.init({ userId: this.hasUserIdValue ? this.userIdValue : null })
    this.unsubscribe = this.session.subscribe((snapshot) => this.render(snapshot))
    this.stopCacheReset = resetOnTurboCache(this, () => this.clearForCache())
  }

  disconnect() {
    this.unsubscribe?.()
    this.stopCacheReset?.()
  }

  linkedAddressesValueChanged() {
    if (this.session) this.render(this.session.snapshot())
  }

  // data-action="wallet#connectWallet", optionally with data-wallet-key-param on a picker entry.
  async connectWallet(event) {
    event?.preventDefault?.()
    try {
      await this.session.connect(event?.params?.key || null)
    } catch (raw) {
      publishError(this, raw)
    }
  }

  disconnectWallet(event) {
    event?.preventDefault?.()
    this.session.disconnect()
  }

  async switchChain(event) {
    event?.preventDefault?.()
    try {
      await this.session.switchChain(normalizeChain(this.chainValue))
    } catch (raw) {
      publishError(this, raw)
    }
  }

  reset(event) {
    event?.preventDefault?.()
    this.session.resetPending()
  }

  render(snapshot) {
    const chain = this.hasChainValue && Object.keys(this.chainValue).length > 0 ? normalizeChain(this.chainValue) : null
    const status = deriveStatus(snapshot, {
      linked: this.linkedAddressesValue,
      requiredChainId: chain?.chainId ?? null,
      requiresChain: this.requiresChainValue
    })

    this.element.dataset.walletState = snapshot.state
    this.element.dataset.walletStatus = status
    if (snapshot.banner) this.element.dataset.walletBanner = snapshot.banner
    else delete this.element.dataset.walletBanner

    fillFields(this.fieldTargets, {
      // From the server for wallets it knows, so this panel needs no viem. An unknown wallet stays lowercase.
      address: this.checksumsValue?.[snapshot.address] ?? snapshot.address,
      walletName: snapshot.wallet?.name,
      status
    })
    this.renderWallets(snapshot.wallets)

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = this.messageFor(snapshot, status)
      if (snapshot.notice) this.messageTarget.dataset.tone = snapshot.notice.neutral ? "neutral" : "error"
      else delete this.messageTarget.dataset.tone
    }

    this.dispatch("state", {
      detail: { ...snapshot, status, message: this.messageFor(snapshot, status) }
    })
  }

  messageFor(snapshot, status) {
    if (snapshot.banner) return WALLET_TEXT[snapshot.banner]
    if (snapshot.notice) return snapshot.notice.message
    if (status === "unlinked") return WALLET_TEXT.unlinked
    if (status === "wrong_network") return MESSAGES.wrong_network
    if (status === "address_mismatch") return MESSAGES.address_not_linked
    if (status === "wallet_busy") return MESSAGES.wallet_busy
    if (status === "no_wallet") return snapshot.environment.socialWebview
      ? MESSAGES.in_app_browser
      : snapshot.environment.mobile ? MESSAGES.no_wallet_mobile : MESSAGES.no_wallet_desktop
    return ""
  }

  // Name and icon are self-attested by the extension, so textContent and data: images only.
  renderWallets(wallets) {
    if (!this.hasProviderListTarget || !this.hasProviderTemplateTarget) return
    // Only when the set changes, so a state update cannot remove a button mid-click or take focus.
    const keys = wallets.map((wallet) => wallet.key).join()
    if (keys === this.renderedWalletKeys) return
    this.renderedWalletKeys = keys
    this.providerListTarget.replaceChildren(...wallets.map((wallet) => {
      const entry = this.providerTemplateTarget.content.cloneNode(true)
      const button = entry.querySelector("button")
      if (button) button.dataset.walletKeyParam = wallet.key
      const name = entry.querySelector("[data-wallet-name]")
      if (name) name.textContent = wallet.name
      const icon = entry.querySelector("img[data-wallet-icon]")
      if (icon && wallet.icon) icon.src = wallet.icon
      else icon?.remove()
      return entry
    }))
  }

  clearForCache() {
    if (this.hasProviderListTarget) this.providerListTarget.replaceChildren()
    this.renderedWalletKeys = null
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = ""
      delete this.messageTarget.dataset.tone
    }
    fillFields(this.fieldTargets, {})
    delete this.element.dataset.walletState
    delete this.element.dataset.walletStatus
    delete this.element.dataset.walletBanner
  }
}
