// Seam only. WalletConnect is off unless a project ID is configured, and the package is not vendored:
// its licence and relay need a decision first (docs/research/wallet-onboarding.md, section 2.4).
// To enable: vendor the bundle, pin it, and return an EIP-1193 provider from loadWalletConnect.
import { WalletError } from "wallet/errors"

export function walletConnectEnabled(projectId) {
  return typeof projectId === "string" && projectId.trim() !== ""
}

export async function loadWalletConnect(projectId) {
  throw new WalletError("walletconnect_unavailable", { details: { configured: walletConnectEnabled(projectId) } })
}
