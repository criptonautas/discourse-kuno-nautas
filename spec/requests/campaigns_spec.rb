# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseKunoNautas::CampaignsController do
  fab!(:category)
  fab!(:owner, :user)
  fab!(:donor, :user)
  fab!(:topic) { Fabricate(:topic, user: owner, category: category) }

  let(:address) { "4#{"8" * 94}" }
  let(:view_key) { "a" * 64 }
  let(:rpc_url) { "http://monero-wallet-rpc.test/json_rpc" }

  before do
    SiteSetting.kuno_nautas_enabled = true
    SiteSetting.kuno_nautas_categories = category.id.to_s
    SiteSetting.monero_tips_enabled = true
    SiteSetting.monero_tips_verified_enabled = true
    SiteSetting.monero_wallet_rpc_url = rpc_url
  end

  def rpc_returns(results)
    stub_request(:post, rpc_url).to_return do |request|
      result = results.fetch(JSON.parse(request.body)["method"], {})
      {
        status: 200,
        body: { jsonrpc: "2.0", id: "0", result: result }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      }
    end
  end

  def set_up(params = {})
    put "/kuno-nautas/campaigns/#{topic.id}.json",
        params: {
          address: address,
          view_key: view_key,
          goal: "2.5",
          kuno_url: "",
        }.merge(params)
  end

  def ready_wallet(kuno_url: nil)
    topic.custom_fields[DiscourseKunoNautas::GOAL_FIELD] = 2 * DiscourseKunoNautas::ATOMIC_UNITS
    topic.custom_fields[DiscourseKunoNautas::KUNO_URL_FIELD] = kuno_url
    topic.custom_fields[DiscourseKunoNautas::STATUS_FIELD] = "active"
    topic.save_custom_fields
    DiscourseKunoNautas.store_wallet(
      topic.id,
      { "address" => address, "view_key" => view_key, "wallet" => "w", "status" => "ready" },
    )
  end

  describe "#update" do
    it "lets the owner set the campaign up and queues the wallet" do
      sign_in(owner)

      expect_enqueued_with(job: :create_monero_campaign_wallet, args: { topic_id: topic.id }) do
        set_up
      end

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("monero_campaign", "goal")).to eq(2.5)
      expect(response.parsed_body.dig("monero_campaign", "status")).to eq("active")
      expect(response.parsed_body.dig("monero_campaign", "wallet", "status")).to eq("pending")
      stored = DiscourseKunoNautas.get_wallet(topic.id)
      expect(stored["view_key"]).to eq(view_key)
      expect(PluginStoreRow.find_by(plugin_name: "discourse-kuno-nautas").value).not_to include(
        view_key,
      )
      expect(topic.reload.custom_fields.keys).not_to include("view_key")
    end

    it "lets an admin set it up on someone else's topic, and logs it" do
      sign_in(Fabricate(:admin))

      set_up

      expect(response.status).to eq(200)
      expect(UserHistory.find_by(custom_type: "monero_campaign_set_up").details).to include(
        owner.username,
      )
    end

    it "refuses anyone else" do
      sign_in(donor)

      set_up

      expect(response.status).to eq(403)
      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
    end

    it "refuses outside a campaign category" do
      SiteSetting.kuno_nautas_categories = ""
      sign_in(owner)

      set_up

      expect(response.status).to eq(422)
    end

    it "refuses the address the owner's tips go to" do
      owner.custom_fields[DiscourseMoneroTips::ADDRESS_FIELD] = address
      owner.save_custom_fields
      sign_in(owner)

      set_up

      expect(response.status).to eq(422)
      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
    end

    it "refuses a subaddress, a bad key, a non-https Kuno link and a negative goal" do
      sign_in(owner)

      set_up(address: "8#{"8" * 94}")
      expect(response.status).to eq(422)

      set_up(view_key: "nope")
      expect(response.status).to eq(422)

      set_up(kuno_url: "http://kuno.example/f/1")
      expect(response.status).to eq(422)

      set_up(goal: "-1")
      expect(response.status).to eq(422)

      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
    end

    it "refuses a second set-up, active or closed" do
      ready_wallet
      sign_in(owner)

      set_up
      expect(response.status).to eq(422)

      delete "/kuno-nautas/campaigns/#{topic.id}/wallet.json"
      set_up
      expect(response.status).to eq(422)
      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
    end

    it "refuses a goal that is not a finite number" do
      sign_in(owner)

      set_up(goal: "Infinity")

      expect(response.status).to eq(422)
    end
  end

  describe "#close" do
    it "forgets the key, drops the subaddresses and freezes the bar" do
      ready_wallet
      MoneroCampaignAddress.create!(topic_id: topic.id, donor_id: donor.id, address: "8#{"9" * 94}")
      MoneroCampaignDonation.create!(
        topic_id: topic.id,
        txid: "t",
        address: address,
        amount: DiscourseKunoNautas::ATOMIC_UNITS,
        confirmed: true,
        received_at: Time.zone.now,
      )
      sign_in(owner)

      delete "/kuno-nautas/campaigns/#{topic.id}/wallet.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("monero_campaign", "status")).to eq("closed")
      expect(response.parsed_body.dig("monero_campaign", "raised")).to eq(1.0)
      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
      expect(MoneroCampaignAddress.where(topic_id: topic.id)).to be_empty
      expect(MoneroCampaignDonation.where(topic_id: topic.id).count).to eq(1)
    end

    it "is the owner's alone" do
      ready_wallet
      sign_in(donor)

      delete "/kuno-nautas/campaigns/#{topic.id}/wallet.json"

      expect(response.status).to eq(403)
      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_present
    end
  end

  describe "#donate" do
    it "gives the primary address to an anonymous visitor" do
      ready_wallet

      get "/kuno-nautas/campaigns/#{topic.id}/donate.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["address"]).to eq(address)
      expect(response.parsed_body["attributed"]).to eq(false)
      expect(response.parsed_body["qr"]).to start_with("data:image/png;base64,")
    end

    it "mints a subaddress for a member who wants to be shown, on a community Kuno" do
      ready_wallet
      subaddress = "8#{"5" * 94}"
      rpc_returns(
        "create_address" => {
          "address" => subaddress,
          "address_index" => 3,
        },
        "get_address" => {
          "address" => address,
        },
      )
      sign_in(donor)

      get "/kuno-nautas/campaigns/#{topic.id}/donate.json", params: { attributed: true }

      expect(response.parsed_body["address"]).to eq(subaddress)
      expect(response.parsed_body["attributed"]).to eq(true)
      expect(MoneroCampaignAddress.find_by(topic_id: topic.id, donor_id: donor.id).address).to eq(
        subaddress,
      )
    end

    it "never mints one on a linked Kuno" do
      ready_wallet(kuno_url: "https://kuno.anne.media/f/1")
      sign_in(donor)

      get "/kuno-nautas/campaigns/#{topic.id}/donate.json", params: { attributed: true }

      expect(response.parsed_body["address"]).to eq(address)
      expect(response.parsed_body["attributed"]).to eq(false)
      expect(MoneroCampaignAddress.count).to eq(0)
    end

    it "404s once the campaign is closed" do
      topic.custom_fields[DiscourseKunoNautas::STATUS_FIELD] = "closed"
      topic.save_custom_fields

      get "/kuno-nautas/campaigns/#{topic.id}/donate.json"

      expect(response.status).to eq(404)
    end
  end

  describe "the topic" do
    it "carries the campaign, and tells only the owner about the wallet" do
      ready_wallet
      MoneroCampaignDonation.create!(
        topic_id: topic.id,
        donor_id: donor.id,
        txid: "t",
        address: address,
        amount: DiscourseKunoNautas::ATOMIC_UNITS / 2,
        confirmed: true,
        received_at: Time.zone.now,
      )

      get "/t/#{topic.id}.json"
      campaign = response.parsed_body["monero_campaign"]
      expect(campaign["raised"]).to eq(0.5)
      expect(campaign["goal"]).to eq(2.0)
      expect(campaign["supporters"].map { |s| s["username"] }).to eq([donor.username])
      expect(campaign).not_to have_key("wallet")

      DiscourseKunoNautas.set_wallet_error(topic.id, "rpc.internal:18083 refused")
      sign_in(owner)
      get "/t/#{topic.id}.json"
      expect(response.parsed_body.dig("monero_campaign", "wallet", "status")).to eq("error")
      expect(response.parsed_body.dig("monero_campaign", "wallet")).not_to have_key("error")

      sign_in(Fabricate(:admin))
      get "/t/#{topic.id}.json"
      expect(response.parsed_body.dig("monero_campaign", "wallet", "error")).to include("refused")
    end

    it "forgets the key when the topic is hard-deleted, and keeps donations" do
      ready_wallet
      MoneroCampaignAddress.create!(topic_id: topic.id, donor_id: donor.id, address: "8#{"9" * 94}")
      MoneroCampaignDonation.create!(
        topic_id: topic.id,
        txid: "t",
        address: address,
        amount: 1,
        confirmed: true,
        received_at: Time.zone.now,
      )

      topic.destroy!

      expect(DiscourseKunoNautas.get_wallet(topic.id)).to be_nil
      expect(MoneroCampaignAddress.count).to eq(0)
      expect(MoneroCampaignDonation.count).to eq(1)
    end

    it "reports an unreadable key instead of raising" do
      ready_wallet
      row = PluginStoreRow.find_by(plugin_name: "discourse-kuno-nautas")
      row.update!(value: JSON.parse(row.value).merge("view_key" => "garbage").to_json)

      expect(DiscourseKunoNautas.get_wallet(topic.id)["view_key"]).to be_nil
      sign_in(owner)
      get "/t/#{topic.id}.json"
      expect(response.status).to eq(200)
    end

    it "carries nothing without a campaign" do
      get "/t/#{topic.id}.json"

      expect(response.parsed_body).not_to have_key("monero_campaign")
    end
  end
end
