import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import { clipboardCopy } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";

// The campaign's address with a QR, like the tip modal, plus the choice to be
// shown as a supporter, which asks the server for a subaddress of one's own.
export default class KunoDonateModal extends Component {
  @service currentUser;

  @tracked address = null;
  @tracked uri = null;
  @tracked qr = null;
  @tracked attributed = false;
  @tracked wantAttributed = false;
  @tracked error = null;
  @tracked copied = false;

  constructor() {
    super(...arguments);
    this.load();
  }

  get topic() {
    return this.args.model.topic;
  }

  get campaign() {
    return this.args.model.campaign;
  }

  // Only a community Kuno can attribute: Kuno counts the primary address alone.
  get canAttribute() {
    return !!this.currentUser && !this.campaign.kuno_url;
  }

  async load() {
    this.address = null;
    this.copied = false;
    try {
      const result = await ajax(
        `/kuno-nautas/campaigns/${this.topic.id}/donate.json`,
        { data: { attributed: this.wantAttributed } }
      );
      this.address = result.address;
      this.uri = result.uri;
      this.qr = result.qr;
      this.attributed = result.attributed;
    } catch (e) {
      this.error = extractError(e);
    }
  }

  @action
  toggleAttributed(event) {
    this.wantAttributed = event.target.checked;
    this.load();
  }

  @action
  async copy() {
    await clipboardCopy(this.address);
    this.copied = true;
  }

  <template>
    <DModal
      @title={{i18n "kuno_nautas.donate_title"}}
      @closeModal={{@closeModal}}
      class="kuno-donate-modal"
    >
      <:body>
        <p class="kuno-donate-modal__intro">
          {{i18n "kuno_nautas.donate_intro"}}
        </p>

        {{#if this.canAttribute}}
          <label class="kuno-donate-modal__attribute checkbox-label">
            <input
              type="checkbox"
              checked={{this.wantAttributed}}
              {{on "change" this.toggleAttributed}}
            />
            {{i18n "kuno_nautas.show_me"}}
          </label>
        {{/if}}

        <p class="kuno-donate-modal__attribution">
          {{#if this.attributed}}
            {{i18n "kuno_nautas.attributed"}}
          {{else}}
            {{i18n "kuno_nautas.unattributed"}}
          {{/if}}
        </p>

        {{#if this.error}}
          <div class="alert alert-error">{{this.error}}</div>
        {{else if this.address}}
          {{#if this.qr}}
            <img
              class="kuno-donate-modal__qr"
              src={{this.qr}}
              alt={{i18n "kuno_nautas.scan"}}
              width="240"
              height="240"
            />
          {{/if}}

          <label class="kuno-donate-modal__label" for="kuno-donate-address">
            {{i18n "kuno_nautas.address"}}
          </label>
          <input
            id="kuno-donate-address"
            class="kuno-donate-modal__address"
            type="text"
            value={{this.address}}
            readonly
          />
        {{/if}}
      </:body>

      <:footer>
        {{#if this.address}}
          <button
            type="button"
            class="btn btn-primary"
            {{on "click" this.copy}}
          >
            {{if
              this.copied
              (i18n "kuno_nautas.copied")
              (i18n "kuno_nautas.copy")
            }}
          </button>

          <a href={{this.uri}} class="btn btn-default">
            {{i18n "kuno_nautas.open_wallet"}}
          </a>
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
