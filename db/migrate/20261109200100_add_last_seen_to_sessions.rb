class AddLastSeenToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_seen_at, :datetime
    add_index :sessions, :last_seen_at
  end
end
