# frozen_string_literal: true

module DiscourseKunoNautas
  class CampaignsController < ::ApplicationController
    requires_plugin DiscourseKunoNautas::PLUGIN_NAME

    requires_login only: %i[update close]
    before_action :find_topic
    before_action :ensure_owner, only: %i[update close]

    # Sets the campaign up in one go. The key cannot spend, but it does reveal
    # every incoming payment to this wallet — the form says so before this point.
    def update
      unless DiscourseMoneroTips::MoneroWalletRpc.configured?
        return render_json_error(I18n.t("kuno_nautas.unavailable"), status: 422)
      end
      unless DiscourseKunoNautas.campaign_category?(@topic.category_id)
        return render_json_error(I18n.t("kuno_nautas.not_campaign_category"), status: 422)
      end
      # One campaign per topic, ever: the donations recorded for it would
      # otherwise carry over into the next one.
      if DiscourseKunoNautas.campaign?(@topic)
        return render_json_error(I18n.t("kuno_nautas.already_set_up"), status: 422)
      end

      address = params[:address].to_s.strip
      # Kuno only matches outputs paid to a primary address, so that is what a
      # campaign publishes on both sites.
      if !address.match?(DiscourseMoneroTips::ADDRESS_FORMAT) || !address.start_with?("4") ||
           address.length != 95
        return render_json_error(I18n.t("kuno_nautas.invalid_address"), status: 422)
      end
      # Otherwise every tip to the author would count as a donation.
      if address == @topic.user&.custom_fields&.dig(DiscourseMoneroTips::ADDRESS_FIELD)
        return render_json_error(I18n.t("kuno_nautas.same_as_tips_address"), status: 422)
      end

      view_key = params[:view_key].to_s.strip.downcase
      unless view_key.match?(DiscourseMoneroTips::VIEW_KEY_FORMAT)
        return render_json_error(I18n.t("kuno_nautas.invalid_view_key"), status: 422)
      end

      kuno_url = params[:kuno_url].to_s.strip
      if kuno_url.present? && !https_url?(kuno_url)
        return render_json_error(I18n.t("kuno_nautas.invalid_kuno_url"), status: 422)
      end

      goal = parse_goal(params[:goal])
      return render_json_error(I18n.t("kuno_nautas.invalid_goal"), status: 422) if goal.nil?

      start_date = parse_date(params[:start_date])
      if start_date.nil?
        return render_json_error(I18n.t("kuno_nautas.invalid_start_date"), status: 422)
      end

      @topic.custom_fields[DiscourseKunoNautas::GOAL_FIELD] = goal
      @topic.custom_fields[DiscourseKunoNautas::KUNO_URL_FIELD] = kuno_url.presence
      @topic.custom_fields[DiscourseKunoNautas::STATUS_FIELD] = "active"
      @topic.save_custom_fields

      DiscourseKunoNautas.store_wallet(
        @topic.id,
        {
          "address" => address,
          "view_key" => view_key,
          "wallet" => "monero-campaign-#{@topic.id}",
          "start_date" => start_date.iso8601,
          "restore_height" => nil,
          "status" => "pending",
          "error" => nil,
        },
      )

      Jobs.enqueue(:create_monero_campaign_wallet, topic_id: @topic.id)
      log_staff_action("set_up")

      render json: success_json.merge(monero_campaign: campaign_json)
    end

    # Forgetting the key stops the scanning. Donations stay: they happened, and
    # the bar freezes at its final total.
    def close
      DiscourseKunoNautas.remove_wallet(@topic.id)
      ::MoneroCampaignAddress.where(topic_id: @topic.id).delete_all
      @topic.custom_fields[DiscourseKunoNautas::STATUS_FIELD] = "closed"
      @topic.save_custom_fields
      log_staff_action("close")

      render json: success_json.merge(monero_campaign: campaign_json)
    end

    def donate
      wallet = DiscourseKunoNautas.get_wallet(@topic.id)
      raise Discourse::NotFound if wallet.blank?

      address = wallet["address"]
      # A linked Kuno never mints a subaddress: Kuno would miss that donation.
      if params[:attributed].to_s == "true" && current_user.present? &&
           @topic.custom_fields[DiscourseKunoNautas::KUNO_URL_FIELD].blank? &&
           wallet["status"] == "ready"
        address = DiscourseKunoNautas.donor_address_for(@topic, current_user, wallet) || address
      end

      render json: {
               address: address,
               uri: payment_uri(address),
               qr: qr_data_url(address),
               attributed: address != wallet["address"],
             }
    end

    private

    def find_topic
      @topic = Topic.find_by(id: params[:topic_id])
      raise Discourse::NotFound if @topic.nil?
      guardian.ensure_can_see!(@topic)
    end

    def ensure_owner
      raise Discourse::InvalidAccess unless DiscourseKunoNautas.owner?(@topic, current_user)
    end

    def campaign_json
      DiscourseKunoNautas.campaign_json(@topic.reload, current_user)
    end

    # An admin acting on another member's fundraiser is a staff action.
    def log_staff_action(action)
      return if current_user.id == @topic.user_id

      StaffActionLogger.new(current_user).log_custom(
        "monero_campaign_#{action}",
        topic_id: @topic.id,
        username: @topic.user&.username,
      )
    end

    def https_url?(value)
      URI.parse(value).scheme == "https"
    rescue URI::Error
      false
    end

    # XMR as typed, kept in atomic units from here on. Blank means no goal.
    def parse_goal(value)
      goal = BigDecimal(value.to_s.strip.presence || "0")
      goal.negative? ? nil : (goal * DiscourseKunoNautas::ATOMIC_UNITS).to_i
    rescue ArgumentError, FloatDomainError
      nil
    end

    def parse_date(value)
      value.present? ? Date.iso8601(value.to_s) : Date.current
    rescue ArgumentError
      nil
    end

    def payment_uri(address)
      "monero:#{address}"
    end

    # Drawn here because core already ships rqrcode, so no QR library has to be
    # pulled into the page.
    def qr_data_url(address)
      require "rqrcode" if !defined?(RQRCode)

      RQRCode::QRCode.new(payment_uri(address)).as_png(border_modules: 1, size: 240).to_data_url
    end
  end
end
