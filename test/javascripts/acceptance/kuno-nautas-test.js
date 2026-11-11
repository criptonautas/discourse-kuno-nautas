import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import topicFixtures from "discourse/tests/fixtures/topic";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const ADDRESS = `4${"8".repeat(94)}`;

function topicWith(campaign) {
  const payload = cloneJSON(topicFixtures["/t/280/1.json"]);
  if (campaign) {
    payload.monero_campaign = campaign;
  }
  return payload;
}

const CAMPAIGN = {
  goal: 2,
  raised: 0.5,
  donations: 1,
  kuno_url: null,
  status: "active",
  supporters: [
    { username: "eviltrout", avatar_template: "/images/avatar.png" },
  ],
};

acceptance("Kuno Nautas | a topic with a campaign", function (needs) {
  needs.user();
  needs.settings({ kuno_nautas_enabled: true, kuno_nautas_categories: "" });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () => helper.response(topicWith(CAMPAIGN)));
    server.get("/kuno-nautas/campaigns/280/donate.json", () =>
      helper.response({
        address: ADDRESS,
        uri: `monero:${ADDRESS}`,
        qr: "data:image/png;base64,iVBORw0KGgo=",
        attributed: false,
      })
    );
  });

  test("draws the bar under the first post and offers to donate", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert.dom("#post_1 .kuno-campaign").exists();
    assert.dom("#post_2 .kuno-campaign").doesNotExist();
    assert.dom(".kuno-campaign__percentage").hasText("25%");
    assert.dom(".kuno-campaign__supporter").exists({ count: 1 });
    assert
      .dom(".kuno-campaign__kuno")
      .doesNotExist("no Kuno link without a URL");

    await click(".kuno-campaign__donate");

    assert.dom(".kuno-donate-modal__address").hasValue(ADDRESS);
    assert
      .dom(".kuno-donate-modal__attribute")
      .exists("a community Kuno offers attribution");
  });
});

acceptance("Kuno Nautas | a linked Kuno", function (needs) {
  needs.user();
  needs.settings({
    kuno_nautas_enabled: true,
    kuno_nautas_categories: "",
    kuno_nautas_show_anne_button: true,
  });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () =>
      helper.response(
        topicWith({ ...CAMPAIGN, kuno_url: "https://kuno.anne.media/f/1" })
      )
    );
    server.get("/kuno-nautas/campaigns/280/donate.json", () =>
      helper.response({
        address: ADDRESS,
        uri: "",
        qr: null,
        attributed: false,
      })
    );
  });

  test("links to Kuno and never offers attribution", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert
      .dom(".kuno-campaign__kuno")
      .hasAttribute("href", "https://kuno.anne.media/f/1");

    await click(".kuno-campaign__donate");

    assert.dom(".kuno-donate-modal__attribute").doesNotExist();
  });
});

const CATEGORY_ID = topicFixtures["/t/280/1.json"].category_id;

acceptance("Kuno Nautas | a linked Kuno, button hidden", function (needs) {
  needs.user();
  needs.settings({
    kuno_nautas_enabled: true,
    kuno_nautas_categories: "",
    kuno_nautas_show_anne_button: false,
  });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () =>
      helper.response(
        topicWith({ ...CAMPAIGN, kuno_url: "https://kuno.anne.media/f/1" })
      )
    );
  });

  test("hides the Anne button but keeps the campaign", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert.dom(".kuno-campaign").exists();
    assert.dom(".kuno-campaign__kuno").doesNotExist();
  });
});

acceptance("Kuno Nautas | the owner of a topic without one", function (needs) {
  needs.user({ admin: true });
  needs.settings({
    kuno_nautas_enabled: true,
    kuno_nautas_categories: String(CATEGORY_ID),
  });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () => helper.response(topicWith(null)));
  });

  test("gets the set-up button in a campaign category", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert.dom("#post_1 .kuno-campaign__set-up").exists();
    assert.dom(".kuno-campaign__donate").doesNotExist();
  });
});

acceptance("Kuno Nautas | outside a campaign category", function (needs) {
  needs.user({ admin: true });
  needs.settings({ kuno_nautas_enabled: true, kuno_nautas_categories: "" });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () => helper.response(topicWith(null)));
  });

  test("offers nothing", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert.dom(".kuno-campaign").doesNotExist();
  });
});

acceptance("Kuno Nautas | when disabled", function (needs) {
  needs.user();
  needs.settings({ kuno_nautas_enabled: false });

  needs.pretender((server, helper) => {
    server.get("/t/280.json", () => helper.response(topicWith(CAMPAIGN)));
  });

  test("nothing is drawn", async function (assert) {
    await visit("/t/internationalization-localization/280");

    assert.dom(".kuno-campaign").doesNotExist();
  });
});
