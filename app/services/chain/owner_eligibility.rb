module Chain
  # App rule on top of the chain's: an owner is an active verified wallet of an active member
  # who can sign in this app, and one person holds one owner key per Safe, because the chain
  # cannot see that two addresses belong to one person.
  class OwnerEligibility
    def initialize(account)
      @account = account
    end

    def user_of!(address)
      wallet = Wallet.active.find_by(address: address)
      membership = wallet && @account.account_memberships.active.find_by(user_id: wallet.user_id)
      raise Refusal.new("owner_not_verified") unless membership
      raise Refusal.new("owner_is_viewer") if membership.viewer?
      raise Refusal.new("owner_email_unconfirmed") unless membership.user.email_confirmed?

      wallet.user_id
    end

    def check_all!(addresses)
      users = addresses.map { |address| user_of!(address) }
      raise Refusal.new("owner_duplicate_member") if users.uniq.length != users.length
    end

    # An addition must not give someone a second key. other_owners excludes a swapped-out address.
    def check_new_owner!(address, other_owners:)
      user_id = user_of!(address)
      # Revoked wallets too: unlinking does not take a key out of the Safe, so that person still holds one.
      others = Wallet.where(address: other_owners).pluck(:user_id)
      raise Refusal.new("owner_duplicate_member") if others.include?(user_id)
    end
  end
end
