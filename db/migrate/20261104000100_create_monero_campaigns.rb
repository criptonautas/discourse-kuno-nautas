# frozen_string_literal: true

class CreateMoneroCampaigns < ActiveRecord::Migration[7.2]
  def change
    create_table :monero_campaign_donations do |t|
      t.integer :topic_id, null: false
      t.integer :donor_id
      t.string :txid, null: false
      t.string :address, null: false
      # Atomic units (1 XMR = 1e12), kept as given by the wallet so nothing is
      # lost to floating point.
      t.bigint :amount, null: false
      t.integer :confirmations, null: false, default: 0
      t.boolean :confirmed, null: false, default: false
      t.datetime :received_at, null: false
      t.timestamps
    end

    add_index :monero_campaign_donations, %i[topic_id txid address], unique: true
    add_index :monero_campaign_donations, :donor_id

    create_table :monero_campaign_addresses do |t|
      t.integer :topic_id, null: false
      t.integer :donor_id, null: false
      t.string :address, null: false
      t.integer :address_index
      t.timestamps
    end

    add_index :monero_campaign_addresses, %i[topic_id donor_id], unique: true
    add_index :monero_campaign_addresses, :address, unique: true
  end
end
