# frozen_string_literal: true

module Jobs
  # Building the watch-only wallet talks to the RPC and can take a moment, so
  # the form returns immediately and this finishes the job. The owner sees the
  # status on the topic.
  class CreateMoneroCampaignWallet < ::Jobs::Base
    def execute(args)
      topic_id = args[:topic_id]
      wallet = DiscourseKunoNautas.get_wallet(topic_id)
      return if wallet.blank? || wallet["restore_height"].present?
      return unless DiscourseMoneroTips::MoneroWalletRpc.configured?
      if wallet["view_key"].blank?
        return DiscourseKunoNautas.set_wallet_error(topic_id, I18n.t("kuno_nautas.key_unreadable"))
      end

      rpc = DiscourseMoneroTips::MoneroWalletRpc.new

      DiscourseMoneroTips::MoneroWalletRpc.with_lock do
        rpc.close_wallet
        wallet["restore_height"] = DiscourseKunoNautas.restore_height_for(rpc, wallet["start_date"])
        rpc.create_wallet(
          filename: wallet["wallet"],
          address: wallet["address"],
          view_key: wallet["view_key"],
          restore_height: wallet["restore_height"],
        )
        rpc.close_wallet
      end

      DiscourseKunoNautas.store_wallet(topic_id, wallet.merge("status" => "ready", "error" => nil))
    rescue DiscourseMoneroTips::MoneroWalletRpc::Error => e
      DiscourseKunoNautas.set_wallet_error(topic_id, e.message)
    end
  end
end
