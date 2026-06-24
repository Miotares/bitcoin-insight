# Privacy Policy — Bitcoin Insight

_Last updated: 24 June 2026_

Bitcoin Insight ("the app") is a read-only Bitcoin statistics and watch-only
wallet app. It is built to respect your privacy: there is no account, no login,
no analytics, no advertising, and no user tracking of any kind.

## What we collect

**Nothing on our servers.** The app does not have a backend that stores your
data. We do not collect, sell, or share personal information.

## Data that stays on your device

- **Wallet data** (Bitcoin addresses and extended public keys / xpubs) is stored
  exclusively in the iOS Keychain on your device. It is never uploaded to us.
- **Preferences** (selected currency, haptics, gap limit, wallet-tab toggle) are
  stored locally on your device using `UserDefaults`.

We never ask for and never have access to private keys or seed phrases. The
wallet feature is watch-only.

## Data sent to third parties

To show balances, transactions, and live network statistics, the app sends
requests to public Bitcoin services. These requests are made directly from your
device:

- **mempool.space** — to look up balances and transaction history for the
  addresses/xpubs you add, and to fetch network statistics (fees, block height,
  mempool, hashrate, difficulty, etc.). Your watch-only addresses are included in
  these requests so the service can return their data.
- **CoinGecko** — as a fallback source for the Bitcoin price.
- **Supabase** (our cached statistics endpoint) — the app and the Home/Lock-screen
  widgets read pre-aggregated, global Bitcoin statistics from here: current network
  stats (price, fees, block height) and historical price/fee data used for the in-app
  charts and to convert prices into currencies that mempool.space does not serve
  directly. This endpoint only ever returns public market and network data — no
  wallet data, addresses, or xpubs are ever sent to it.

These services may receive your IP address and the requested data as part of a
normal network request, and they process it under their own privacy policies.

## Purchases

The optional one-time "Premium" unlock (Home and Lock-screen widgets) is handled
entirely by Apple via the App Store (StoreKit). We do not receive or store your
payment details. The unlock status is kept on your device.

## Children

The app is not directed at children and collects no personal information.

## Changes

If this policy changes, the updated version will be posted at this URL.

## Contact

Questions about privacy: **miotares@proton.me**
