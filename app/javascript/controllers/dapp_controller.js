import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay", "walletAddress", "userBalance"]

  connect() {
    console.log("DApp controller connected")
    this.checkWalletConnection()
  }

  toggleSidebar() {
    this.sidebarTarget.classList.toggle("-translate-x-full")
    this.overlayTarget.classList.toggle("hidden")
  }

  async connectWallet() {
    if (typeof window.ethereum !== 'undefined') {
      try {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
        const account = accounts[0]
        this.walletAddressTarget.textContent = `${account.slice(0, 6)}...${account.slice(-4)}`
        this.loadUserBalance(account)
      } catch (error) {
        console.error("Error connecting wallet:", error)
      }
    } else {
      alert("Please install MetaMask!")
    }
  }

  disconnectWallet() {
    this.walletAddressTarget.textContent = "Niet verbonden"
    this.userBalanceTarget.textContent = "€0.00"
  }

  async loadUserBalance(account) {
    // Hier zou je de balance van de blockchain ophalen
    // Voor nu een placeholder
    this.userBalanceTarget.textContent = "€150.25"
  }

  async checkWalletConnection() {
    if (typeof window.ethereum !== 'undefined') {
      const accounts = await window.ethereum.request({ method: 'eth_accounts' })
      if (accounts.length > 0) {
        const account = accounts[0]
        this.walletAddressTarget.textContent = `${account.slice(0, 6)}...${account.slice(-4)}`
        this.loadUserBalance(account)
      }
    }
  }
}