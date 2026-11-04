# frozen_string_literal: true

# name: discourse-kuno-nautas
# about: Monero fundraisers published as topics, with a progress bar fed by a watch-only wallet
# version: 0.1.0
# authors: Criptonautas
# url: https://github.com/criptonautas/discourse-kuno-nautas
# required_version: 3.4.0

enabled_site_setting :kuno_nautas_enabled

register_asset "stylesheets/kuno-nautas.scss"

module ::DiscourseKunoNautas
  PLUGIN_NAME = "discourse-kuno-nautas"
  GOAL_FIELD = "monero_campaign_goal"
  KUNO_URL_FIELD = "monero_campaign_kuno_url"
  STATUS_FIELD = "monero_campaign_status"
  ATOMIC_UNITS = 1_000_000_000_000
  BLOCKS_PER_DAY = 720
end

after_initialize do
  # Built on discourse-monero-tips: its wallet RPC, lock, settings and address
  # formats. Its classes are referenced lazily because it loads after this plugin.
  if !defined?(::DiscourseMoneroTips)
    Rails.logger.warn("[kuno-nautas] discourse-monero-tips is not installed; campaigns are off")
    next
  end

  module ::DiscourseKunoNautas
    CAMPAIGN_PREFIX = "campaign:"

    # The view key lives here rather than in a topic custom field: custom fields
    # are serialized, searched and exported in ways a secret must never be. It is
    # encrypted at rest with a key derived from the site secret.
    def self.store_wallet(topic_id, data)
      ::PluginStore.set(
        PLUGIN_NAME,
        "#{CAMPAIGN_PREFIX}#{topic_id}",
        data.merge("view_key" => encryptor.encrypt_and_sign(data["view_key"].to_s)),
      )
    end

    # The key is only needed to build the wallet; once built, the RPC opens it by
    # name, so a key that no longer decrypts (new site secret) is reported, not
    # raised from a serializer.
    def self.get_wallet(topic_id)
      data = ::PluginStore.get(PLUGIN_NAME, "#{CAMPAIGN_PREFIX}#{topic_id}")
      return nil if data.nil?

      data.merge("view_key" => encryptor.decrypt_and_verify(data["view_key"].to_s))
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      data.merge("view_key" => nil)
    end

    def self.remove_wallet(topic_id)
      ::PluginStore.remove(PLUGIN_NAME, "#{CAMPAIGN_PREFIX}#{topic_id}")
    end

    def self.encryptor
      @encryptor ||=
        ActiveSupport::MessageEncryptor.new(
          ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(
            "kuno-nautas-view-key",
            32,
          ),
        )
    end

    def self.each_wallet
      ::PluginStoreRow
        .where(plugin_name: PLUGIN_NAME)
        .where("key LIKE ?", "#{CAMPAIGN_PREFIX}%")
        .order(:key)
        .each do |row|
          topic_id = row.key.delete_prefix(CAMPAIGN_PREFIX).to_i
          wallet = get_wallet(topic_id)
          yield topic_id, wallet if wallet
        end
    end

    def self.set_wallet_error(topic_id, message)
      wallet = get_wallet(topic_id)
      return if wallet.blank?

      store_wallet(topic_id, wallet.merge("status" => "error", "error" => message))
    end

    # A plugin whose migrations have not run yet must not take the forum down
    # from inside a serializer, so the table is checked once per process.
    def self.table_ready?
      @table_ready = ::MoneroCampaignDonation.table_exists? if @table_ready.nil?
      @table_ready
    end

    def self.campaign_category?(category_id)
      SiteSetting.kuno_nautas_categories.to_s.split("|").map(&:to_i).include?(category_id)
    end

    def self.campaign?(topic)
      topic.custom_fields[STATUS_FIELD].present?
    end

    def self.owner?(topic, user)
      user.present? && (user.id == topic.user_id || user.admin?)
    end

    # What the topic and the topic list carry. Amounts leave as XMR. The wallet
    # status is only told to the owner, and never the key itself.
    def self.campaign_json(topic, user = nil)
      donations = ::MoneroCampaignDonation.confirmed.where(topic_id: topic.id)
      supporters = ::User.where(id: donations.where.not(donor_id: nil).select(:donor_id))

      json = {
        goal: topic.custom_fields[GOAL_FIELD].to_i.to_f / ATOMIC_UNITS,
        raised: donations.sum(:amount).to_f / ATOMIC_UNITS,
        donations: donations.count,
        kuno_url: topic.custom_fields[KUNO_URL_FIELD].presence,
        status: topic.custom_fields[STATUS_FIELD],
        supporters:
          supporters.map { |u| { username: u.username, avatar_template: u.avatar_template } },
      }
      if owner?(topic, user)
        # The RPC's error text can name its host, so only admins get it verbatim.
        json[:wallet] = get_wallet(topic.id)&.slice("status", "error")
        json[:wallet]&.delete("error") unless user.admin?
      end
      json
    end

    # wallet-rpc has no height-by-date and only reports the chain height through
    # an open, synced wallet, so any ready wallet is borrowed for the reading.
    # Before the first one exists, the floor setting is all there is. One day of
    # margin: scanning a day too early is harmless, too late loses donations.
    def self.restore_height_for(rpc, start_date)
      floor = SiteSetting.monero_tips_restore_height
      height = chain_height(rpc)
      return floor if height.nil?

      days = [(Date.current - Date.parse(start_date)).to_i, 0].max
      [height - (days + 1) * BLOCKS_PER_DAY, floor].max
    end

    def self.first_ready_wallet
      each_wallet { |_, w| return w["wallet"] if w["status"] == "ready" }
      ::DiscourseMoneroTips.each_wallet { |_, w| return w["wallet"] if w["status"] == "ready" }
      nil
    end

    def self.chain_height(rpc)
      filename = first_ready_wallet
      return nil if filename.nil?

      rpc.open_wallet(filename)
      rpc.refresh
      # get_height is not wrapped by monero-tips' client, whose call is private.
      height = rpc.send(:call, "get_height")["height"].to_i
      rpc.close_wallet
      height
    rescue StandardError
      # A borrowed wallet that will not open, or a client without get_height,
      # must not block the campaign: the floor only means more chain to scan.
      rpc.close_wallet
      nil
    end

    # The address a donor should pay when they want to be shown as a supporter:
    # a subaddress of the campaign wallet minted for (topic, donor). Monero
    # transfers carry no sender, so this is the only way to attribute one.
    def self.donor_address_for(topic, donor, wallet)
      existing = ::MoneroCampaignAddress.find_by(topic_id: topic.id, donor_id: donor.id)
      return existing.address if existing

      rpc = ::DiscourseMoneroTips::MoneroWalletRpc.new

      result, primary =
        ::DiscourseMoneroTips::MoneroWalletRpc.with_lock do
          rpc.close_wallet
          rpc.open_wallet(wallet["wallet"])
          [rpc.create_address("donation from #{donor.username}"), rpc.primary_address]
        end

      # The RPC holds one open wallet for every client it has, so make sure the
      # subaddress came from this campaign's wallet before donations go to it.
      address = result["address"].to_s
      if primary != wallet["address"] || !address.start_with?("8") ||
           !address.match?(::DiscourseMoneroTips::ADDRESS_FORMAT)
        raise ::DiscourseMoneroTips::MoneroWalletRpc::Error,
              "the wallet RPC answered for a different wallet"
      end

      ::MoneroCampaignAddress.create!(
        topic_id: topic.id,
        donor_id: donor.id,
        address: address,
        address_index: result["address_index"],
      ).address
    rescue ActiveRecord::RecordNotUnique
      # Two requests from the same donor raced; the first one's address wins.
      ::MoneroCampaignAddress.find_by(topic_id: topic.id, donor_id: donor.id)&.address
    rescue ::DiscourseMoneroTips::MoneroWalletRpc::Error => e
      set_wallet_error(topic.id, e.message)
      nil
    end
  end

  # Keeps the key out of error logs should a request ever fail mid-way.
  Rails.application.config.filter_parameters << :view_key

  require_relative "app/models/monero_campaign_donation"
  require_relative "app/models/monero_campaign_address"
  require_relative "app/controllers/campaigns_controller"
  require_relative "app/jobs/regular/create_monero_campaign_wallet"
  require_relative "app/jobs/scheduled/monero_campaigns_sync"

  register_topic_custom_field_type(DiscourseKunoNautas::GOAL_FIELD, :integer)
  register_topic_custom_field_type(DiscourseKunoNautas::KUNO_URL_FIELD, :string)
  register_topic_custom_field_type(DiscourseKunoNautas::STATUS_FIELD, :string)
  [
    DiscourseKunoNautas::GOAL_FIELD,
    DiscourseKunoNautas::KUNO_URL_FIELD,
    DiscourseKunoNautas::STATUS_FIELD,
  ].each { |field| add_preloaded_topic_list_custom_field(field) }

  add_to_serializer(
    :topic_view,
    :monero_campaign,
    include_condition: -> do
      SiteSetting.kuno_nautas_enabled && DiscourseKunoNautas.table_ready? &&
        DiscourseKunoNautas.campaign?(object.topic)
    end,
  ) { DiscourseKunoNautas.campaign_json(object.topic, scope.user) }

  # shortcut: one SUM per campaign topic on a list page; a list is 30 topics and
  # campaigns are few. Preload per list if a campaign category ever fills a page.
  add_to_serializer(
    :topic_list_item,
    :monero_campaign,
    include_condition: -> do
      SiteSetting.kuno_nautas_enabled && DiscourseKunoNautas.table_ready? &&
        DiscourseKunoNautas.campaign?(object)
    end,
  ) { DiscourseKunoNautas.campaign_json(object) }

  # Trashing keeps the campaign (the topic can come back); only a hard delete
  # forgets the key. Donations stay as the record of what was received.
  add_model_callback(:topic, :after_destroy) do
    DiscourseKunoNautas.remove_wallet(id)
    ::MoneroCampaignAddress.where(topic_id: id).delete_all
  end

  on(:user_destroyed) do |user|
    ::MoneroCampaignAddress.where(donor_id: user.id).delete_all
    ::MoneroCampaignDonation.where(donor_id: user.id).update_all(donor_id: nil)
  end

  Discourse::Application.routes.append do
    put "/kuno-nautas/campaigns/:topic_id" => "discourse_kuno_nautas/campaigns#update",
        :constraints => {
          topic_id: /\d+/,
        }
    delete "/kuno-nautas/campaigns/:topic_id/wallet" => "discourse_kuno_nautas/campaigns#close",
           :constraints => {
             topic_id: /\d+/,
           }
    get "/kuno-nautas/campaigns/:topic_id/donate" => "discourse_kuno_nautas/campaigns#donate",
        :constraints => {
          topic_id: /\d+/,
        },
        :defaults => {
          format: :json,
        }
  end
end
