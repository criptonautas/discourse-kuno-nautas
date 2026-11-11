# discourse-kuno-nautas

[![Linting and Tests](https://github.com/criptonautas/discourse-kuno-nautas/actions/workflows/plugin-linting-and-tests.yml/badge.svg)](https://github.com/criptonautas/discourse-kuno-nautas/actions/workflows/plugin-linting-and-tests.yml)

**ENGLISH** | [ESPAÑOL](README.es.md)

Maintained by Criptonautas. Not affiliated with or endorsed by Discourse (Civilized Discourse Construction Kit, Inc.).

**Community Kunos**: Monero fundraisers that members publish as topics on the forum, with a progress bar that counts what actually reached the member's wallet. Optionally linked to a fundraiser on [Kuno](https://codeberg.org/nebras/kuno), in which case the one bar counts donations made on Kuno and on the forum, once.

The forum never holds funds. It holds a **view** key per campaign, which cannot spend, and uses it to watch the campaign's wallet.

## Needs

[discourse-monero-tips](https://github.com/criptonautas/discourse-monero-tips) with verified tips configured: this plugin reuses its `monero-wallet-rpc`, its lock, its address formats and its `monero_tips_*` settings (`restore_height`, `min_confirmations`, `min_amount`). Tips themselves are not touched: a campaign is a second, separate watch-only wallet keyed by topic, never by user.

## How it works

1. A member creates a topic in a campaign category (`kuno_nautas_categories`). Who may post there is the category's own permission.
2. On their own topic, they click **Campaign** and fill one private form: goal in XMR (empty for no goal), Kuno fundraiser link (optional, `https://` only), the wallet's **primary** address (`4…`, 95 characters, what Kuno accepts), the private view key and the campaign start date. The warnings below are shown before the key field.
3. The topic shows the bar and a **Donate** button. Every confirmed incoming transfer to the wallet counts, whatever address it was paid to; that is what makes Kuno and the forum add up without double counting. Kuno's own figure is never added.
4. When done, they click **Close campaign**: the key is forgotten, the bar freezes at its final total.

A topic carries one campaign, ever: after closing, a new fundraiser needs a new topic. A wallet that failed (RPC down, timeout) is tried again on every sync run, so an outage does not stop a campaign for good.

Admins can set up or close a campaign on another member's topic; each such action lands in the staff action log as `monero_campaign_set_up` or `monero_campaign_close`.

Two kinds of campaign:

| | Anonymous donation (default) | "Show me as a supporter" |
|---|---|---|
| **Community Kuno** (no Kuno link) | primary address | a subaddress minted for (topic, donor): their avatar joins the bar |
| **Linked Kuno** (has a Kuno link) | primary address | not offered: Kuno only matches payments to the primary address, so a subaddress donation would be missing from Kuno's own bar |

Donations count at `monero_tips_min_confirmations` (10 by default); Kuno counts at about 1, so the two figures differ for a few blocks.

## Installation

Add to `containers/app.yml`, after `discourse-monero-tips`, and rebuild:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/criptonautas/discourse-monero-tips.git
          - git clone https://github.com/criptonautas/discourse-kuno-nautas.git
```

Then enable `kuno_nautas_enabled` and pick `kuno_nautas_categories`.

## Settings

| Setting | Purpose |
|---|---|
| `kuno_nautas_enabled` | Off by default |
| `kuno_nautas_categories` | Categories whose topics may carry a campaign |
| `kuno_nautas_show_anne_button` | On by default: a **View on Anne** button, far right, linking to the Kuno fundraiser of linked campaigns |

Everything about the wallet RPC, confirmations, dust and restore height is set in discourse-monero-tips.

## What members are told, and why

- **Use a dedicated wallet and do not spend from it** while the bar is live: a view key reveals the wallet's whole incoming history, past and future, and the member's own change coming back would count as a donation (on Kuno too).
- **On Kuno, delete the fundraiser when it ends**: deactivating keeps the key there, in plaintext.
- Whoever reads a wallet's view key sees every incoming payment, forever. It can never spend.

The campaign address must differ from the member's tips address, otherwise tips would count as donations.

## What the forum stores

- Topic custom fields, public: goal, Kuno link, status.
- The address, the view key (encrypted with a key derived from the site secret) and the wallet status, in the plugin store, never serialized.
- `monero_campaign_donations`: one row per incoming transfer, with the donor when it reached a minted subaddress.
- `monero_campaign_addresses`: the minted subaddresses.

The restore height of a new wallet is taken from the chain height, read through any synced wallet the RPC already has, minus a day of blocks per day since the campaign start, never below `monero_tips_restore_height`. Before the first wallet exists there is no reading, and the floor is used.

`monero-wallet-rpc` cannot delete a wallet file: closing a campaign removes the key from Discourse and stops opening that wallet, but the watch-only file stays on the RPC host until an operator removes it.

## Banner

[discourse-kuno-banner](https://github.com/criptonautas/discourse-kuno-banner) reads `monero_campaign` from topic list items and draws the bar on campaign topics in its daily rotation, next to the external Kunos it supports.

## Development

```bash
pnpm install && pnpm lint
```

Specs: `bundle exec rspec plugins/discourse-kuno-nautas/spec`, with discourse-monero-tips installed. Frontend: `/qunit?filter=Kuno`.

## License

MIT. See [LICENSE](LICENSE).

Text of this README under [CC BY-NC-SA 4.0](CC-BY-NC-SA-4.0.txt).
