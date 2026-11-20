// Device context for choosing the right "no wallet" route. Hints only, never a trust decision.

const SOCIAL_WEBVIEW = /FBAN|FBAV|FB_IAB|Instagram|WhatsApp|Telegram|TikTok|musical_ly|Snapchat|LinkedInApp|MicroMessenger|Twitter|\bLine\//i
const WALLET_BROWSER = /MetaMaskMobile|Trust(?:Wallet)?\/|TrustWallet|Rabby|CoinbaseWallet|imToken|Rainbow/i

export function detectEnvironment(userAgent = "") {
  const ios = /iPhone|iPad|iPod/i.test(userAgent)
  const android = /Android/i.test(userAgent)
  return {
    mobile: ios || android,
    ios,
    android,
    socialWebview: SOCIAL_WEBVIEW.test(userAgent),
    walletBrowser: WALLET_BROWSER.test(userAgent)
  }
}

export function noWalletCode(environment) {
  if (environment.socialWebview) return "in_app_browser"
  return environment.mobile ? "no_wallet_mobile" : "no_wallet_desktop"
}

// Links that open an https page inside a wallet's own browser. Only the MetaMask form has a
// current first-party doc. Trust is reported to fail on some iPhones, so treat it as best effort.
export function walletDeepLinks(url) {
  const parsed = new URL(url)
  if (parsed.protocol !== "https:") return {}
  const hostAndPath = `${parsed.host}${parsed.pathname}${parsed.search}`
  return {
    metamask: `https://link.metamask.io/dapp/${hostAndPath}`,
    trust: `https://link.trustwallet.com/open_url?coin_id=60&url=${encodeURIComponent(url)}`
  }
}
