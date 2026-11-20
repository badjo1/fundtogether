require "test_helper"

class ChainAddressTest < ActiveSupport::TestCase
  CHECKSUMMED = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf".freeze

  test "normalises lowercase, uppercase and correctly checksummed input" do
    lower = CHECKSUMMED.downcase
    assert_equal lower, Chain::Address.normalize(lower)
    assert_equal lower, Chain::Address.normalize("0x#{lower.delete_prefix('0x').upcase}")
    assert_equal lower, Chain::Address.normalize(CHECKSUMMED)
  end

  test "refuses a wrong checksum and malformed input" do
    [ CHECKSUMMED.sub("7E5F", "7e5F"), "0x1234", "7e5f4552091a69125d5dfcb7b8c2659029395bdf", nil, 7, [],
      "0x7e5f4552091a69125d5dfcb7b8c2659029395bdfff", "0xzz5f4552091a69125d5dfcb7b8c2659029395bdf",
      "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf\n" ].each do |bad|
      assert_raises(Chain::Address::Invalid, bad.inspect) { Chain::Address.normalize(bad) }
    end
  end
end
