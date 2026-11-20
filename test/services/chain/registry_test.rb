require "test_helper"

class ChainRegistryTest < ActiveSupport::TestCase
  def with_chains(value)
    previous = ENV["FUNDTOGETHER_CHAINS"]
    ENV["FUNDTOGETHER_CHAINS"] = value
    yield
  ensure
    ENV["FUNDTOGETHER_CHAINS"] = previous
  end

  test "defaults to sepolia only" do
    with_chains(nil) do
      assert_equal [ "sepolia" ], Chain::Registry.enabled.map(&:key)
      assert_equal 11_155_111, Chain::Registry.default.chain_id
      assert_predicate Chain::Registry.default, :testnet?
    end
  end

  test "mainnet chains exist in the file but cannot be used unless enabled" do
    with_chains(nil) do
      assert_raises(Chain::Registry::ChainDisabled) { Chain::Registry.fetch(8453) }
      assert_raises(Chain::Registry::ChainDisabled) { Chain::Registry.fetch(100) }
      assert_raises(Chain::Registry::ChainDisabled) { Chain::Registry.fetch(1) }
      assert_raises(Chain::Registry::ChainDisabled) { Chain::Registry.fetch("11155111") }
    end
    assert_includes Chain::Registry.all.keys, "base"
  end

  test "opt in by environment" do
    with_chains("sepolia, gnosis") do
      assert_equal %w[sepolia gnosis], Chain::Registry.enabled.map(&:key)
      assert_equal "EURe", Chain::Registry.fetch(100).token.symbol
      assert_raises(Chain::Registry::ChainDisabled) { Chain::Registry.fetch(8453) }
    end
  end

  test "a typo in the environment fails loudly" do
    with_chains("sepolia,bsae") do
      assert_raises(Chain::Registry::ConfigError) { Chain::Registry.enabled }
    end
  end

  test "every chain has at least two https endpoints, canonical contracts and a token" do
    Chain::Registry.all.each_value do |chain|
      assert_operator chain.rpc_urls.length, :>=, 2, chain.key
      assert(chain.rpc_urls.all? { |url| url.start_with?("https://") }, chain.key)
      assert_equal vectors["constants"]["singleton_l2"], chain.singleton
      assert_equal vectors["constants"]["factory"], chain.factory
      assert_equal vectors["constants"]["fallback_handler"], chain.fallback_handler
      assert_match Chain::Address::LOWER, chain.token.address
    end
    assert_equal "0x08210f9170f89ab7658f0b5e3ff39b0e03c594d4", Chain::Registry.all["sepolia"].token.address
    assert_equal 6, Chain::Registry.all["base"].token.decimals
    assert_equal 18, Chain::Registry.all["gnosis"].token.decimals
  end
end
