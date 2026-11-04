import { withPluginApi } from "discourse/lib/plugin-api";
import KunoCampaign from "../components/kuno-campaign";

export default {
  name: "kuno-nautas",

  initialize(container) {
    if (!container.lookup("service:site-settings").kuno_nautas_enabled) {
      return;
    }

    withPluginApi((api) => {
      // Under the first post's cooked content; the component itself ignores
      // every other post.
      api.renderAfterWrapperOutlet("post-content-cooked-html", KunoCampaign);
    });
  },
};
