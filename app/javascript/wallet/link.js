// Link flow: challenge, personal_sign, post. The server composes the message and verifies the
// signature; a wallet counts as linked only when the server has said so.
import { WalletError, refuse } from "wallet/errors"
import { walletDeepLinks } from "wallet/environment"

export function utf8ToHex(text) {
  const bytes = new TextEncoder().encode(text)
  return `0x${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`
}

export async function linkWallet({ session, http, urls, onStep = () => {} }) {
  const address = session.snapshot().address
  if (session.snapshot().state !== "connected" || !address) throw new WalletError("not_connected")

  onStep("challenge")
  const challenge = await http.post(urls.challenges, { address, purpose: "link" })
  const message = challenge?.message
  const nonce = challenge?.nonce
  if (typeof message !== "string" || typeof nonce !== "string" || nonce === "") throw refuse("challenge_mismatch")
  if (!message.toLowerCase().includes(address) || !message.includes(nonce)) throw refuse("challenge_mismatch")
  // The first line says who is asking. A server handing over a message for another site is refused here.
  const host = globalThis.location?.host
  if (host && !message.startsWith(`${host} wants you`)) throw refuse("challenge_mismatch", { host })

  onStep("sign_message")
  const signature = await session.request("personal_sign", [utf8ToHex(message), address], {
    expected: { address },
    keepSubmitting: true
  })

  onStep("saving_link")
  const wallet = await session.submit(() => http.post(urls.wallets, { address, nonce, signature }))
  if (String(wallet?.address).toLowerCase() !== address) throw refuse("link_mismatch")
  return wallet
}

export async function createHandoff({ http, url }) {
  const handoff = await http.post(url)
  return { url: handoff.url, expiresAt: handoff.expires_at, deepLinks: walletDeepLinks(handoff.url) }
}
