# Bitcoin Insight

A native iOS app for monitoring real-time Bitcoin network statistics and tracking watch-only wallets. Built with SwiftUI, it connects to public APIs without requiring any account or API key.

## Features

### Dashboard
- Live BTC price in 10+ currencies (USD, EUR, GBP, JPY, CHF, AUD, CAD, CNY, HKD, SEK)
- Current block height with animated updates
- Mempool transaction count and fee distribution chart
- Network difficulty and adjustment progress
- Mining hashrate
- Halving countdown with progress visualization and reward chart
- Lightning Network statistics (channels, nodes, capacity)
- Circulating supply

### Wallet Tracker
- Watch-only wallet support — no private keys ever required
- Supported wallet types:
  - `xpub` — Legacy P2PKH
  - `ypub` — Nested SegWit (P2SH-P2WPKH)
  - `zpub` — Native SegWit (P2WPKH)
  - Single Bitcoin addresses
- HD wallet address derivation (BIP32/BIP44)
- Balance tracking across derived addresses
- Transaction history with confirmation status
- Wallet color customization and reordering
- Configurable gap limit (20 / 50 / 100)

### General
- Dark theme with animated background
- Haptic feedback
- Secure wallet storage via iOS Keychain

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Concurrency:** async/await, Combine
- **Cryptography:** [swift-secp256k1 (P256K)](https://github.com/21-DOT-DEV/swift-secp256k1), CryptoKit
- **APIs:**
  - [mempool.space](https://mempool.space/api) — blockchain data, fees, address/transaction lookup
  - [CoinGecko](https://www.coingecko.com/en/api) — BTC price fallback
- **Storage:** Keychain (wallets), UserDefaults (preferences)

## Requirements

- macOS with Xcode 16 or later
- iOS 17+ deployment target
- Internet connection

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Miotares/bitcoin-insight.git
   cd bitcoin-insight
   ```

2. **Open the project in Xcode**
   ```bash
   open BitcoinWidgets.xcodeproj
   ```

3. **Add the Swift package dependency**

   In Xcode: **File → Add Package Dependencies**
   - URL: `https://github.com/21-DOT-DEV/swift-secp256k1`
   - Product: `P256K`

4. **Build and run**

   Select a simulator or connected device, then press `Cmd+R`.

No API keys or accounts are needed. All APIs used are public.

## Project Structure

```
BitcoinWidgets/
├── Models/           # Data models (BitcoinStats, WalletModels)
├── Services/         # API integration, wallet management, Keychain, address derivation
├── ViewModels/       # MVVM presentation logic (DashboardViewModel, WalletViewModel)
├── Views/            # SwiftUI views and components
├── Extensions/       # Swift extensions (Color)
└── Utilities/        # Formatters
```

## Privacy

Bitcoin Insight is a read-only tool. It never asks for private keys or seed phrases. Wallet data (xpub keys and addresses) is stored exclusively in the iOS Keychain on the user's device and is never transmitted to any server other than the public mempool.space API for balance and transaction lookups.

## License

MIT — see [LICENSE](LICENSE) for details.
