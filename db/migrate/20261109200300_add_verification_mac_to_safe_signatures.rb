# Elliptic curve recovery in pure Ruby costs about 80 ms. It runs once, at receipt; this keyed MAC says
# "the server recovered this signer from this signature over this hash". Empty rows are recovered once.
class AddVerificationMacToSafeSignatures < ActiveRecord::Migration[8.1]
  def change
    add_column :safe_signatures, :verification_mac, :string
  end
end
