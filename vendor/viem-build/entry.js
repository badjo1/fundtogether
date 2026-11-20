// The only viem surface the browser may use. Adding an export here widens what ships on signing
// pages, so add it deliberately and rebuild with vendor/viem-build/build.sh.
export {
  concat,
  decodeEventLog,
  decodeFunctionData,
  decodeFunctionResult,
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  getCreate2Address,
  hashMessage,
  hashTypedData,
  isAddress,
  keccak256,
  pad,
  parseAbi,
  recoverAddress,
  toHex,
} from "viem"
