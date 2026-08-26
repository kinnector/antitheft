# Antitheft

Keep your money, passwords, and secrets safe.

Cross-platform protection for your passwords, software and hardware wallets, bank and exchange accounts, supply-chain packages (npm, PyPI, Cargo, Composer, and more), and more - running quietly in the background on Windows, macOS, and Linux. This repository is the Antitheft monorepo: the agent and the app that talks to it, built and shipped together.

---

## How it works

No signatures, no blocklists, no analyst in the loop. Antitheft answers one question continuously for every sensitive resource on your machine: *is the process touching this the one process that's allowed to?* If not, the access is refused before it completes - not flagged afterward.

- **Storage-ownership locking**: passwords, browser vaults, software wallet key material, 2FA seeds, SSH keys, and dev/cloud credentials are storage owned by exactly one process - the password manager, the browser, the wallet extension. Every other process is refused on sight, no allowlist to maintain.
- **Content-integrity checking**: catches process injection, binary/resource replacement, and mimic-app swaps in wallet popups and bank/exchange pages by cross-checking the browser process, the extension's execution context, and the rendered DOM - any level disagreeing with the others is caught immediately, before you confirm a transaction or type a seed phrase.
- **Supply-chain protection**: vets packages from npm, PyPI, Cargo, Composer, and more before they run, catching malicious/compromised dependencies before they can reach your secrets in the first place.

There's no separate Pro codebase. One agent, one CLI, one app, fully open source - a cloud subscription unlocks specific capabilities (bank/exchange page-integrity, behavioral correlation, fleet view) at runtime via an entitlement check, not a different binary.

See [kinnector.dev/antitheft](https://kinnector.dev/antitheft) for the full product walkthrough, supported wallets/exchanges, and install instructions.

## Layout

- `agent/` - the Rust daemon that owns the enforcement decision and talks to `core`'s telemetry engine
- `ui/` - the Tauri + SvelteKit desktop app that talks to the agent's control socket

## Build and run

**Recommended IDE setup**: [VS Code](https://code.visualstudio.com/) + [Svelte extension](https://marketplace.visualstudio.com/items?itemName=svelte.svelte-vscode) + [Tauri extension](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer).

```bash
# agent
cd agent
cargo build --release

# app
cd ui
npm install
npm run tauri dev     # development mode
npm run tauri build   # standalone production bundle for your platform
```
