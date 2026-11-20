// viem helpers tests need beyond the app's surface, in the test-only bundle or written out here.
import { decodeFunctionData, encodeAbiParameters, encodeFunctionData, getAddress } from "viem"

export { decodeFunctionData, encodeFunctionData, getAddress }

// encodeFunctionResult is not in the app bundle, on purpose. The doubles only return simple shapes.
export function encodeFunctionResult({ abi, functionName, result }) {
  const fn = abi.find((item) => item.type === "function" && item.name === functionName)
  const values = fn.outputs.length === 1 ? [result] : result
  return encodeAbiParameters(fn.outputs, values)
}
