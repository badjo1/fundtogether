# app/models/invitation.rb (update methods)
class Invitation < ApplicationRecord
  belongs_to :account
  
  validates :email, presence: true, 
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, presence: true, 
            inclusion: { in: %w[pending accepted rejected expired] }
  validates :token, presence: true, uniqueness: true
  
  enum :status, [:pending, :accepted, :rejected, :expired]
   
  before_validation :generate_token, on: :create
  
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('created_at < ?', 7.days.ago).where(status: 'pending') }
  
  def accept!(user_params = {})
    return false if expired?
    
    user = User.find_or_create_by!(wallet_address: user_params[:wallet_address]) do |u|
      u.name = user_params[:name]
    end
    
    account.add_user(user, role: 'member')
    update!(status: 'accepted')
    user
  end
  
  def reject!
    update!(status: 'rejected')
  end
  
  def expired?
    created_at < 7.days.ago && pending?
  end
  
  private
  
  def generate_token
    self.token ||= SecureRandom.hex(32)
  end
end