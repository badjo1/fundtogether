import "./support/register.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, test } from "node:test"

const vectors = JSON.parse(readFileSync(new URL("../fixtures/safe_vectors.json", import.meta.url)))
const { getAddress, keccak256, recoverAddress, hashMessage } = await import("viem")
const constants = await import("safe/constants")
const { safeTxHash, domainHash, messageHash } = await import("safe/hash")
const { buildInitializer, predictSafeAddress, buildDeployCalldata } = await import("safe/deploy")
const { buildAction, prevOwnerOf } = await import("safe/calldata")
const { assertPolicy, assertThresholdRules } = await import("safe/policy")
const { normalizeSignature, recoverSigner, sortBySigner } = await import("safe/signatures")

function txOf(row) {
  return {
    to: row.to,
    value: BigInt(row.value),
    data: row.data,
    operation: Number(row.operation),
    safeTxGas: BigInt(row.safe_tx_gas),
    baseGas: BigInt(row.base_gas),
    gasPrice: BigInt(row.gas_price),
    gasToken: row.gas_token,
    refundReceiver: row.refund_receiver,
    nonce: BigInt(row.nonce)
  }
}

function contextOf(context) {
  return {
    safe: context.safe,
    token: context.token,
    owners: context.owners ?? [],
    threshold: context.threshold ?? null,
    currentNonce: context.current_nonce === undefined ? null : BigInt(context.current_nonce)
  }
}

function codeOf(fn) {
  try {
    fn()
    return null
  } catch (error) {
    return error.code ?? `unexpected: ${error.message}`
  }
}

describe("constants match the shared vectors", () => {
  const shared = vectors.constants
  test("addresses and slots", () => {
    assert.equal(constants.SAFE_L2_SINGLETON, shared.singleton_l2)
    assert.equal(constants.SAFE_PROXY_FACTORY, shared.factory)
    assert.equal(constants.FALLBACK_HANDLER, shared.fallback_handler)
    assert.equal(constants.ZERO_ADDRESS, shared.zero_address)
    assert.equal(constants.SENTINEL_OWNERS, shared.sentinel)
    assert.equal(constants.GUARD_SLOT, shared.guard_slot)
    assert.equal(constants.FALLBACK_SLOT, shared.fallback_slot)
    assert.equal(constants.DOMAIN_TYPEHASH, shared.domain_typehash)
    assert.equal(constants.SAFE_TX_TYPEHASH, shared.safe_tx_typehash)
  })
  test("proxy creation code and its keccak", () => {
    assert.equal(constants.PROXY_CREATION_CODE, shared.proxy_creation_code)
    assert.equal(keccak256(constants.PROXY_CREATION_CODE), shared.proxy_creation_code_keccak)
  })
  test("event topics", () => {
    assert.equal(constants.TOPICS.executionSuccess, shared.topics.ExecutionSuccess.topic)
    assert.equal(constants.TOPICS.executionFailure, shared.topics.ExecutionFailure.topic)
    assert.equal(constants.TOPICS.proxyCreation, shared.topics.ProxyCreation.topic)
    assert.equal(constants.TOPICS.transfer, shared.topics.Transfer.topic)
  })
  test("recomputed selectors and topics", async () => {
    const { toHex } = await import("viem")
    for (const entry of Object.values(shared.selectors)) {
      assert.equal(keccak256(toHex(entry.signature)).slice(0, 10), entry.selector, entry.signature)
    }
    for (const entry of Object.values(shared.topics)) {
      assert.equal(keccak256(toHex(entry.signature)), entry.topic, entry.signature)
    }
  })
})

describe("safe tx hashes", () => {
  for (const row of vectors.safe_tx_hashes) {
    test(row.name, () => {
      const tx = txOf(row)
      assert.equal(domainHash({ chainId: row.chain_id, safe: row.safe }), row.domain_separator)
      assert.equal(messageHash(tx), row.struct_hash)
      assert.equal(safeTxHash({ chainId: row.chain_id, safe: row.safe, tx }), row.safe_tx_hash)
    })
  }
})

describe("create2", () => {
  for (const row of vectors.create2) {
    test(row.name, () => {
      const threshold = BigInt(row.threshold)
      const rebuilt = buildInitializer({ owners: row.owners, threshold, fallbackHandler: row.fallback_handler })
      // One real row sets a delegatecall in setup. We never build that, so it must not match ours.
      const usesSetupDelegatecall = BigInt(`0x${row.initializer.slice(10 + 64 * 2, 10 + 64 * 3)}`) !== 0n
      if (usesSetupDelegatecall) assert.notEqual(rebuilt, row.initializer)
      else assert.equal(rebuilt, row.initializer)
      const saltNonce = BigInt(row.salt_nonce)
      assert.equal(predictSafeAddress({ initializer: row.initializer, saltNonce, singleton: row.singleton, factory: row.factory }), row.predicted_address)
    })
  }
  test("deploy calldata has the factory selector", () => {
    const row = vectors.create2[2]
    const data = buildDeployCalldata({ initializer: row.initializer, saltNonce: BigInt(row.salt_nonce) })
    assert.equal(data.slice(0, 10), vectors.constants.selectors.create_proxy_with_nonce.selector)
  })
})

describe("calldata rebuild", () => {
  for (const row of vectors.calldata) {
    test(row.name, () => {
      const action = buildAction({ kind: row.kind, params: row.params, nonce: BigInt(row.nonce) }, contextOf(row.context))
      assert.equal(action.to, row.expected.to)
      assert.equal(action.value.toString(), row.expected.value)
      assert.equal(action.data, row.expected.data)
      assert.equal(action.operation, row.expected.operation)
      const tx = { ...txOf({ ...row.expected, nonce: row.nonce }), to: action.to }
      assert.equal(safeTxHash({ chainId: row.context.chain_id, safe: row.context.safe, tx }), row.expected.safe_tx_hash)
    })
  }
})

describe("build refusals", () => {
  for (const row of vectors.build_refusals) {
    test(`${row.name}: ${row.code}`, () => {
      assert.equal(codeOf(() => buildAction({ kind: row.kind, params: row.params }, contextOf(row.context))), row.code)
    })
  }
})

describe("threshold rules", () => {
  for (const row of vectors.threshold_rules) {
    test(`${row.threshold} of ${row.owner_count}, ack ${row.acknowledge_risk}: ${row.code}`, () => {
      const code = codeOf(() => assertThresholdRules({ ownerCount: row.owner_count, threshold: row.threshold, acknowledged: row.acknowledge_risk }))
      assert.equal(code, row.code)
    })
  }
})

describe("policy refusals", () => {
  for (const row of vectors.policy_refusals) {
    test(`${row.name}: ${row.code}`, () => {
      assert.equal(codeOf(() => assertPolicy(row.tx, contextOf(row.context))), row.code)
    })
  }
})

describe("policy allowed", () => {
  for (const row of vectors.policy_allowed) {
    test(row.name, () => {
      assert.equal(codeOf(() => assertPolicy(row.tx, contextOf(row.context))), null)
    })
  }
})

describe("signatures", () => {
  for (const row of vectors.signatures.recover) {
    test(`recover: ${row.name}`, async () => {
      if (row.kind === "safe_eth_sign") {
        // Real on-chain form that FundTogether itself refuses to produce or accept.
        assert.equal(normalizeThrows(row.signature), "bad_v")
        const v = parseInt(row.signature.slice(-2), 16) - 4
        const lowered = `${row.signature.slice(0, 130)}${v.toString(16)}`
        const signer = await recoverAddress({ hash: hashMessage({ raw: row.hash }), signature: lowered })
        assert.equal(signer.toLowerCase(), row.signer)
        return
      }
      if (row.normalized) assert.equal(normalizeSignature(row.signature), row.normalized)
      const hash = row.kind === "personal" ? hashMessage(row.message) : row.hash
      assert.equal(await recoverSigner(hash, row.signature), row.signer)
    })
  }

  for (const row of vectors.signatures.rejected) {
    test(`reject: ${row.name}: ${row.code}`, async () => {
      await assert.rejects(recoverSigner(row.hash, row.signature), (error) => {
        assert.equal(error.code, "invalid_signature_format")
        assert.equal(error.details.reason, row.code)
        return true
      })
    })
  }

  for (const row of vectors.signatures.wrong_hash) {
    test(row.name, async () => {
      assert.notEqual(await recoverSigner(row.hash, row.signature), row.must_not_recover)
    })
  }

  test("order is numeric", () => {
    const order = vectors.signatures.order
    const entries = order.signers.map((signer) => ({ signer, signature: "0x" }))
    assert.deepEqual(sortBySigner(entries).map((entry) => entry.signer), order.sorted_ascending)
  })
})

function normalizeThrows(signature) {
  try {
    normalizeSignature(signature)
    return null
  } catch (error) {
    return error.details.reason
  }
}

describe("prevOwner", () => {
  for (const row of vectors.prev_owner) {
    test(`${row.owner} in ${row.owners.length}`, () => {
      assert.equal(prevOwnerOf(row.owners, row.owner), row.prev_owner)
    })
  }
})

describe("checksums", () => {
  for (const row of vectors.checksums) {
    test(row.lower, () => assert.equal(getAddress(row.lower), row.checksummed))
  }
})
