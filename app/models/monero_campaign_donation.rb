# frozen_string_literal: true

# Every confirmed incoming transfer to a campaign wallet, whatever address it
# was paid to. Rows without a donor were paid to the primary address (or on
# Kuno) and count towards the total without being attributed to anyone.
class MoneroCampaignDonation < ActiveRecord::Base
  belongs_to :topic
  belongs_to :donor, class_name: "User", optional: true

  scope :confirmed, -> { where(confirmed: true) }

  def amount_xmr
    amount.to_d / DiscourseKunoNautas::ATOMIC_UNITS
  end
end

# == Schema Information
#
# Table name: monero_campaign_donations
#
#  id            :bigint           not null, primary key
#  address       :string           not null
#  amount        :bigint           not null
#  confirmations :integer          default(0), not null
#  confirmed     :boolean          default(FALSE), not null
#  received_at   :datetime         not null
#  txid          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  donor_id      :integer
#  topic_id      :integer          not null
#
# Indexes
#
#  index_monero_campaign_donations_on_donor_id            (donor_id)
#  index_monero_campaign_donations_on_topic_txid_address  (topic_id,txid,address) UNIQUE
#
