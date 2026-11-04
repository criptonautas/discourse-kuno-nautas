# frozen_string_literal: true

module Jobs
  # Walks every live campaign wallet, asks it what came in, and records what is
  # new. Nothing here can spend: these are watch-only wallets built from a view
  # key. Closed campaigns have no wallet row any more, so they are not walked.
  class MoneroCampaignsSync < ::Jobs::Scheduled
    every 10.minutes

    def execute(_args)
      return unless SiteSetting.kuno_nautas_enabled
      return unless DiscourseMoneroTips::MoneroWalletRpc.configured?

      rpc = DiscourseMoneroTips::MoneroWalletRpc.new

      DiscourseKunoNautas.each_wallet do |topic_id, wallet|
        next if wallet["status"] == "pending"
        next unless Topic.exists?(topic_id)

        # A wallet that failed is tried again every run, so one RPC outage does
        # not stop a campaign for good: a failed build is rebuilt while the key
        # is still readable, a failed sync simply runs again.
        if wallet["restore_height"].nil?
          Jobs.enqueue(:create_monero_campaign_wallet, topic_id: topic_id) if wallet["view_key"]
          next
        end

        DiscourseMoneroTips::MoneroWalletRpc.with_lock do
          rpc.close_wallet
          rpc.open_wallet(wallet["wallet"])
          rpc.refresh
          record(topic_id, rpc.incoming_transfers)
          rpc.close_wallet
        end

        if wallet["status"] == "error"
          DiscourseKunoNautas.store_wallet(
            topic_id,
            wallet.merge("status" => "ready", "error" => nil),
          )
        end
      rescue DiscourseMoneroTips::MoneroWalletRpc::Error => e
        DiscourseKunoNautas.set_wallet_error(topic_id, e.message)
      end
    end

    private

    # Unlike tips, every transfer counts: the whole wallet is the campaign,
    # whether it was paid on the forum or on Kuno. A subaddress minted for a
    # donor additionally says who it was.
    def record(topic_id, transfers)
      minimum = (SiteSetting.monero_tips_min_amount.to_f * DiscourseKunoNautas::ATOMIC_UNITS).round
      required = SiteSetting.monero_tips_min_confirmations

      transfers.each do |transfer|
        amount = transfer["amount"].to_i
        next if amount < minimum

        mapping = MoneroCampaignAddress.find_by(topic_id: topic_id, address: transfer["address"])
        confirmations = transfer["confirmations"].to_i

        donation =
          MoneroCampaignDonation.find_or_initialize_by(
            topic_id: topic_id,
            txid: transfer["txid"],
            address: transfer["address"],
          )
        was_confirmed = donation.confirmed

        donation.donor_id = mapping&.donor_id
        donation.amount = amount
        donation.confirmations = confirmations
        donation.confirmed = confirmations >= required
        donation.received_at ||= Time.at(transfer["timestamp"].to_i).utc
        donation.save!

        next if !donation.confirmed || was_confirmed

        DiscourseEvent.trigger(:monero_campaign_donation_confirmed, donation)
      end
    end
  end
end
