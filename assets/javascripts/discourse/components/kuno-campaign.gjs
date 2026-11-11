import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { renderAvatar } from "discourse/helpers/user-avatar";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { and } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import { campaignCategoryIds, formatXmr, progress } from "../lib/kuno-nautas";
import KunoCampaignFormModal from "./modal/kuno-campaign-form";
import KunoDonateModal from "./modal/kuno-donate";

// Rendered under the first post of a topic. Shows the bar and the Donate
// button when the topic carries a campaign, and the set-up button to the
// owner of a topic in a campaign category that has none yet.
export default class KunoCampaign extends Component {
  @service currentUser;
  @service dialog;
  @service modal;
  @service siteSettings;

  // Kept here so the bar follows what the owner just saved or closed.
  @tracked campaign = this.topic?.monero_campaign;
  @tracked closing = false;

  get post() {
    return this.args.outletArgs.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get isFirstPost() {
    return this.post?.post_number === 1 && !!this.topic;
  }

  get isOwner() {
    const user = this.currentUser;
    return (
      !!user && (user.admin || user.id === this.topic.details?.created_by?.id)
    );
  }

  get canSetUp() {
    return (
      this.isOwner &&
      !this.campaign &&
      campaignCategoryIds(this.siteSettings.kuno_nautas_categories).includes(
        this.topic.category_id
      )
    );
  }

  get active() {
    return this.campaign?.status === "active";
  }

  get linked() {
    return !!this.campaign?.kuno_url;
  }

  get showAnne() {
    return this.linked && this.siteSettings.kuno_nautas_show_anne_button;
  }

  get progress() {
    return progress(this.campaign);
  }

  get progressStyle() {
    return htmlSafe(`width: ${this.progress?.width ?? 0}%;`);
  }

  get reached() {
    return (this.progress?.percentage ?? 0) >= 100;
  }

  get raisedText() {
    return formatXmr(this.campaign.raised);
  }

  get goalText() {
    return formatXmr(this.campaign.goal);
  }

  get sourceText() {
    return i18n(
      this.linked ? "kuno_nautas.source_linked" : "kuno_nautas.source_community"
    );
  }

  get walletMessage() {
    const wallet = this.campaign?.wallet;
    if (!wallet) {
      return null;
    }
    if (wallet.status === "error") {
      return wallet.error
        ? i18n("kuno_nautas.wallet.error", { error: wallet.error })
        : i18n("kuno_nautas.wallet.error_generic");
    }
    return i18n(`kuno_nautas.wallet.${wallet.status}`);
  }

  @action
  update(campaign) {
    this.campaign = campaign;
    this.topic.set("monero_campaign", campaign);
  }

  @action
  openForm() {
    this.modal.show(KunoCampaignFormModal, {
      model: { topic: this.topic, onSaved: this.update },
    });
  }

  @action
  openDonate() {
    this.modal.show(KunoDonateModal, {
      model: { topic: this.topic, campaign: this.campaign },
    });
  }

  @action
  close() {
    this.dialog.yesNoConfirm({
      message: i18n("kuno_nautas.close_confirm"),
      didConfirm: async () => {
        this.closing = true;
        try {
          const result = await ajax(
            `/kuno-nautas/campaigns/${this.topic.id}/wallet`,
            { type: "DELETE" }
          );
          this.update(result.monero_campaign);
        } catch (e) {
          popupAjaxError(e);
        } finally {
          this.closing = false;
        }
      },
    });
  }

  <template>
    {{#if this.isFirstPost}}
      {{#if this.campaign}}
        <section
          class="kuno-campaign {{if this.active '--active' '--closed'}}"
          aria-label={{i18n "kuno_nautas.title"}}
        >
          <div class="kuno-campaign__summary">
            <span class="kuno-campaign__figures">
              <strong>{{this.raisedText}}</strong>
              {{#if this.progress}}
                <span>{{i18n "kuno_nautas.of_goal"}} {{this.goalText}}</span>
              {{/if}}
            </span>
            {{#if this.progress}}
              <strong
                class="kuno-campaign__percentage"
              >{{this.progress.percentage}}%</strong>
            {{/if}}
          </div>

          {{#if this.progress}}
            <div
              class="kuno-campaign__track {{if this.reached '--reached'}}"
              role="progressbar"
              aria-valuemin="0"
              aria-valuemax="100"
              aria-valuenow={{this.progress.width}}
              aria-label={{i18n "kuno_nautas.progress_label"}}
            >
              <span
                class="kuno-campaign__fill"
                style={{this.progressStyle}}
              ></span>
            </div>
          {{/if}}

          <p class="kuno-campaign__source">
            {{this.sourceText}}
            {{#unless this.active}}
              ·
              {{i18n "kuno_nautas.closed"}}
            {{/unless}}
          </p>

          {{#if this.campaign.supporters.length}}
            <div
              class="kuno-campaign__supporters"
              aria-label={{i18n "kuno_nautas.supporters"}}
            >
              {{#each this.campaign.supporters as |supporter|}}
                <a
                  href={{getURL (concat "/u/" supporter.username)}}
                  data-user-card={{supporter.username}}
                  class="kuno-campaign__supporter"
                  title={{supporter.username}}
                >
                  {{htmlSafe
                    (renderAvatar
                      supporter
                      avatarTemplatePath="avatar_template"
                      usernamePath="username"
                      imageSize="tiny"
                    )
                  }}
                </a>
              {{/each}}
            </div>
          {{/if}}

          <div class="kuno-campaign__actions">
            {{#if this.active}}
              <button
                type="button"
                class="btn btn-primary kuno-campaign__donate"
                {{on "click" this.openDonate}}
              >
                {{i18n "kuno_nautas.donate"}}
              </button>
            {{/if}}

            {{#if (and this.active this.isOwner)}}
              <button
                type="button"
                class="btn btn-danger btn-flat kuno-campaign__close"
                disabled={{this.closing}}
                {{on "click" this.close}}
              >
                {{i18n "kuno_nautas.close"}}
              </button>
            {{/if}}

            {{! Last, pushed to the far right: a link out, not an action here. }}
            {{#if this.showAnne}}
              <a
                class="btn btn-default kuno-campaign__kuno"
                href={{this.campaign.kuno_url}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{i18n "kuno_nautas.view_on_anne"}}
              </a>
            {{/if}}
          </div>

          {{#if (and this.active this.walletMessage)}}
            <p class="kuno-campaign__wallet">{{this.walletMessage}}</p>
          {{/if}}
        </section>
      {{else if this.canSetUp}}
        <div class="kuno-campaign kuno-campaign--setup">
          <button
            type="button"
            class="btn btn-default kuno-campaign__set-up"
            {{on "click" this.openForm}}
          >
            {{i18n "kuno_nautas.set_up"}}
          </button>
        </div>
      {{/if}}
    {{/if}}
  </template>
}
