# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::MoneroCampaignsSync do
  fab!(:topic)
  fab!(:donor, :user)

  let(:rpc_url) { "http://monero-wallet-rpc.test/json_rpc" }
  let(:wallet_address) { "4#{"8" * 94}" }
  let(:subaddress) { "8#{"5" * 94}" }
  let(:one_xmr) { DiscourseKunoNautas::ATOMIC_UNITS }

  before do
    SiteSetting.kuno_nautas_enabled = true
    SiteSetting.monero_tips_enabled = true
    SiteSetting.monero_tips_verified_enabled = true
    SiteSetting.monero_wallet_rpc_url = rpc_url
    SiteSetting.monero_tips_min_confirmations = 10

    DiscourseKunoNautas.store_wallet(
      topic.id,
      {
        "address" => wallet_address,
        "view_key" => "a" * 64,
        "wallet" => "w",
        "restore_height" => 100,
        "status" => "ready",
      },
    )
    MoneroCampaignAddress.create!(topic_id: topic.id, donor_id: donor.id, address: subaddress)
  end

  def transfers_return(transfers)
    stub_request(:post, rpc_url).to_return do |request|
      result =
        if JSON.parse(request.body)["method"] == "get_transfers"
          { "in" => transfers }
        else
          {}
        end

      {
        status: 200,
        body: { jsonrpc: "2.0", id: "0", result: result }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      }
    end
  end

  def transfer(overrides = {})
    {
      "txid" => "abc123",
      "address" => wallet_address,
      "amount" => one_xmr,
      "confirmations" => 12,
      "timestamp" => Time.now.to_i,
    }.merge(overrides)
  end

  it "records a payment to the primary address with no donor" do
    transfers_return([transfer])

    described_class.new.execute({})

    donation = MoneroCampaignDonation.last
    expect(donation.topic_id).to eq(topic.id)
    expect(donation.donor_id).to be_nil
    expect(donation.amount).to eq(one_xmr)
    expect(donation.confirmed).to eq(true)
  end

  it "credits a payment to a minted subaddress to its donor" do
    transfers_return([transfer("address" => subaddress)])

    described_class.new.execute({})

    expect(MoneroCampaignDonation.last.donor_id).to eq(donor.id)
  end

  def run_tracking(confirmations)
    transfers_return([transfer("confirmations" => confirmations)])
    DiscourseEvent.track_events(:monero_campaign_donation_confirmed) do
      described_class.new.execute({})
    end
  end

  it "confirms on a later run instead of recording twice, and announces once" do
    expect(run_tracking(2)).to be_empty
    expect(MoneroCampaignDonation.last.confirmed).to eq(false)

    expect(run_tracking(12).size).to eq(1)

    expect(run_tracking(20)).to be_empty
    expect(MoneroCampaignDonation.count).to eq(1)
  end

  it "ignores dust" do
    SiteSetting.monero_tips_min_amount = "0.5"
    transfers_return([transfer("amount" => one_xmr / 1000)])

    described_class.new.execute({})

    expect(MoneroCampaignDonation.count).to eq(0)
  end

  it "skips a closed campaign and a deleted topic" do
    transfers_return([transfer])
    DiscourseKunoNautas.remove_wallet(topic.id)

    described_class.new.execute({})
    expect(MoneroCampaignDonation.count).to eq(0)

    DiscourseKunoNautas.store_wallet(
      topic.id,
      {
        "address" => wallet_address,
        "view_key" => "a" * 64,
        "wallet" => "w",
        "restore_height" => 100,
        "status" => "ready",
      },
    )
    topic.trash!
    described_class.new.execute({})
    expect(MoneroCampaignDonation.count).to eq(0)
  end

  it "never writes a tip" do
    transfers_return([transfer("address" => subaddress)])

    described_class.new.execute({})

    expect(MoneroTip.count).to eq(0)
  end

  it "tries a failed wallet again and clears the error once it syncs" do
    DiscourseKunoNautas.set_wallet_error(topic.id, "timed out")
    transfers_return([transfer])

    described_class.new.execute({})

    expect(MoneroCampaignDonation.count).to eq(1)
    expect(DiscourseKunoNautas.get_wallet(topic.id)["status"]).to eq("ready")
  end

  it "rebuilds a wallet whose creation failed, while the key is still readable" do
    wallet = DiscourseKunoNautas.get_wallet(topic.id)
    DiscourseKunoNautas.store_wallet(
      topic.id,
      wallet.merge("restore_height" => nil, "status" => "error", "error" => "down"),
    )

    expect_enqueued_with(job: :create_monero_campaign_wallet, args: { topic_id: topic.id }) do
      described_class.new.execute({})
    end
  end

  it "remembers why a wallet failed instead of raising" do
    stub_request(:post, rpc_url).to_return(
      status: 200,
      body: { jsonrpc: "2.0", id: "0", error: { message: "no such wallet" } }.to_json,
    )

    described_class.new.execute({})

    expect(DiscourseKunoNautas.get_wallet(topic.id)["status"]).to eq("error")
    expect(DiscourseKunoNautas.get_wallet(topic.id)["error"]).to eq("no such wallet")
  end
end
