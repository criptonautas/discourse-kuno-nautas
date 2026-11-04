import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// The one private form a topic owner fills to start a campaign. The warnings
// come before the key field, not after it: keep it that way when restyling.
export default class KunoCampaignFormModal extends Component {
  @tracked
  form = {
    goal: "",
    kunoUrl: "",
    address: "",
    viewKey: "",
    startDate: new Date().toISOString().slice(0, 10),
  };
  @tracked saving = false;

  get topic() {
    return this.args.model.topic;
  }

  @action
  set(field, event) {
    this.form = { ...this.form, [field]: event.target.value };
  }

  @action
  async save() {
    this.saving = true;
    try {
      const result = await ajax(`/kuno-nautas/campaigns/${this.topic.id}`, {
        type: "PUT",
        data: {
          goal: this.form.goal,
          kuno_url: this.form.kunoUrl,
          address: this.form.address,
          view_key: this.form.viewKey,
          start_date: this.form.startDate,
        },
      });
      // Not kept in the page any longer than the request needs it.
      this.form = { ...this.form, viewKey: "" };
      this.args.model.onSaved(result.monero_campaign);
      this.args.closeModal();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "kuno_nautas.form.title"}}
      @closeModal={{@closeModal}}
      class="kuno-campaign-form"
    >
      <:body>
        <div class="control-group">
          <label class="control-label" for="kuno-goal">
            {{i18n "kuno_nautas.form.goal"}}
          </label>
          <input
            id="kuno-goal"
            type="text"
            inputmode="decimal"
            value={{this.form.goal}}
            placeholder="0"
            {{on "input" (fn this.set "goal")}}
          />
          <p class="kuno-campaign-form__hint">
            {{i18n "kuno_nautas.form.goal_hint"}}
          </p>
        </div>

        <div class="control-group">
          <label class="control-label" for="kuno-url">
            {{i18n "kuno_nautas.form.kuno_url"}}
          </label>
          <input
            id="kuno-url"
            type="url"
            value={{this.form.kunoUrl}}
            placeholder="https://"
            {{on "input" (fn this.set "kunoUrl")}}
          />
          <p class="kuno-campaign-form__hint">
            {{i18n "kuno_nautas.form.kuno_url_hint"}}
          </p>
        </div>

        <div class="control-group">
          <label class="control-label" for="kuno-address">
            {{i18n "kuno_nautas.form.address"}}
          </label>
          <input
            id="kuno-address"
            class="kuno-campaign-form__mono"
            type="text"
            spellcheck="false"
            autocomplete="off"
            value={{this.form.address}}
            {{on "input" (fn this.set "address")}}
          />
          <p class="kuno-campaign-form__hint">
            {{i18n "kuno_nautas.form.address_hint"}}
          </p>
        </div>

        <div class="control-group">
          <label class="control-label" for="kuno-start">
            {{i18n "kuno_nautas.form.start_date"}}
          </label>
          <input
            id="kuno-start"
            type="date"
            value={{this.form.startDate}}
            {{on "input" (fn this.set "startDate")}}
          />
          <p class="kuno-campaign-form__hint">
            {{i18n "kuno_nautas.form.start_date_hint"}}
          </p>
        </div>

        {{! Said before the field, not after it }}
        <div class="alert alert-warning kuno-campaign-form__warnings">
          <ul>
            <li>{{i18n "kuno_nautas.form.warning_dedicated"}}</li>
            <li>{{i18n "kuno_nautas.form.warning_confirmations"}}</li>
            <li>{{i18n "kuno_nautas.form.warning_kuno_delete"}}</li>
            <li>{{i18n "kuno_nautas.form.warning_view_key"}}</li>
          </ul>
        </div>

        <div class="control-group">
          <label class="control-label" for="kuno-view-key">
            {{i18n "kuno_nautas.form.view_key"}}
          </label>
          <input
            id="kuno-view-key"
            class="kuno-campaign-form__mono"
            type="text"
            spellcheck="false"
            autocomplete="off"
            value={{this.form.viewKey}}
            {{on "input" (fn this.set "viewKey")}}
          />
        </div>
      </:body>

      <:footer>
        <button
          type="button"
          class="btn btn-primary kuno-campaign-form__save"
          disabled={{this.saving}}
          {{on "click" this.save}}
        >
          {{i18n "kuno_nautas.form.save"}}
        </button>
        <button type="button" class="btn btn-flat" {{on "click" @closeModal}}>
          {{i18n "cancel"}}
        </button>
      </:footer>
    </DModal>
  </template>
}
