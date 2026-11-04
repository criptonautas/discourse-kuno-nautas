# frozen_string_literal: true

# One subaddress per (topic, donor) pair, minted only for donors who asked to be
# shown as supporters of a community Kuno.
class MoneroCampaignAddress < ActiveRecord::Base
  belongs_to :topic
  belongs_to :donor, class_name: "User"
end

# == Schema Information
#
# Table name: monero_campaign_addresses
#
#  id            :bigint           not null, primary key
#  address       :string           not null
#  address_index :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  donor_id      :integer          not null
#  topic_id      :integer          not null
#
# Indexes
#
#  index_monero_campaign_addresses_on_address                (address) UNIQUE
#  index_monero_campaign_addresses_on_topic_id_and_donor_id  (topic_id,donor_id) UNIQUE
#
