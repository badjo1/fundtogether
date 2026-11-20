require "test_helper"

class ChainAbiTest < ActiveSupport::TestCase
  ALICE = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf".freeze

  test "encodes dynamic values after the static head" do
    encoded = Chain::Hex.from_bin(Chain::Abi.encode(%w[address[] uint256 bytes], [ [ ALICE ], 7, "0xab" ]))
    expected = "0x" \
      "0000000000000000000000000000000000000000000000000000000000000060" \
      "0000000000000000000000000000000000000000000000000000000000000007" \
      "00000000000000000000000000000000000000000000000000000000000000a0" \
      "0000000000000000000000000000000000000000000000000000000000000001" \
      "0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf" \
      "0000000000000000000000000000000000000000000000000000000000000001" \
      "ab00000000000000000000000000000000000000000000000000000000000000"
    assert_equal expected, encoded
  end

  test "round trips the shapes in use" do
    hex = Chain::Hex.from_bin(Chain::Abi.encode(%w[address[] address], [ [ ALICE ], Chain::Address::SENTINEL ]))
    assert_equal [ [ ALICE ], Chain::Address::SENTINEL ], Chain::Abi.decode(%w[address[] address], hex)
    assert_equal "0xab", Chain::Abi.decode_one("bytes", Chain::Hex.from_bin(Chain::Abi.encode(%w[bytes], [ "0xab" ])))
    assert_equal "1.4.1", Chain::Abi.decode_one("string", Chain::Hex.from_bin(Chain::Abi.encode(%w[string], [ "1.4.1" ])))
  end

  test "refuses out of range and non-canonical values when encoding" do
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[uint256], [ -1 ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[uint256], [ 2**256 ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[uint8], [ 256 ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[uint256], [ "1" ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[address], [ "0x12" ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[address uint256], [ ALICE ]) }
    assert_raises(Chain::Abi::EncodeError) { Chain::Abi.encode(%w[tuple], [ 1 ]) }
  end

  test "empty return data never decodes to zero" do
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("uint256", "0x") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("address[]", "0x") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("uint256", nil) }
  end

  test "refuses malformed return data" do
    word = ->(n) { n.to_s(16).rjust(64, "0") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("address[]", "0x#{word.(0x4000)}") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("address[]", "0x#{word.(32)}#{word.(5)}") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("address", "0x#{'f' * 64}") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("bool", "0x#{word.(2)}") }
    assert_raises(Chain::Abi::DecodeError) { Chain::Abi.decode_one("bytes", "0x#{word.(32)}#{word.(64)}") }
  end
end
