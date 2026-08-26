# Antitheft

Your passwords, your bank, your wallet, never touched. Antitheft is a lightweight, cross-platform agent that locks down passwords, browser vaults, software/hardware wallets, and bank/exchange sessions so that only the process that's supposed to touch them ever can.

This repository is **the desktop console** (Tauri + SvelteKit + TypeScript) - the GUI that talks to the `antitheftd` agent daemon over its local control socket. It is not the enforcement engine itself; see [`antitheft-agent`](https://github.com/kinnector/antitheft-agent) for that.

---

## How Antitheft protects you

No signatures, no blocklists, no analyst in the loop. Antitheft answers one question continuously for every sensitive resource on your machine: *is the process touching this the one process that's allowed to?* If not, the access is refused before it completes - not flagged afterward.

Two enforcement shapes cover everything it protects:

- **Storage-ownership locking** (local, free): passwords, browser vaults, software wallet key material, 2FA seeds, SSH keys, and dev/cloud credentials are treated as storage owned by exactly one process - the password manager, the browser, the wallet extension. Every other process is refused on sight, with no allowlist to maintain.
- **Content-integrity checking** (wallet popups: local · banks/exchanges: cloud): catches process injection, binary/resource replacement, and mimic-app swaps by cross-checking the browser process, the extension's execution context, and the rendered DOM - any level disagreeing with the others is caught immediately, before you confirm a transaction or type a seed phrase.

There's no separate Pro codebase. One agent, one CLI, one GUI, fully open source - a cloud subscription unlocks specific capabilities (bank/exchange page-integrity, behavioral correlation, fleet view) at runtime via an entitlement check, not a different binary.

See [kinnector.dev/antitheft](https://kinnector.dev/antitheft) for the full product walkthrough, supported wallets/exchanges, and install instructions for the agent itself.

## What this console does

- **Live daemon status** - agent running/stopped, compiled rules version and timestamp, tracked process count
- **Kernel-enforcement indicator** - shows whether `antitheftd` is running with real BPF LSM enforcement or has fallen back to a user-mode heuristic path (and surfaces the CLI command to re-enable LSM mode if so)
- **Live alert feed** - real-time telemetry/alert events streamed from the daemon, with severity, category, and process detail (image, command line, PID/PPID, matched rule path)
- **Containment release** - release a SIGSTOP-contained process tree by its root PID
- **Rules reload** - trigger the daemon to recompile and hot-swap its policy rules

Talks to `antitheftd` over a local control socket (`/var/run/antitheft/control.sock` on Linux) via Tauri's Rust backend - no network calls for any of the above.

## Build and run

**Recommended IDE setup**: [VS Code](https://code.visualstudio.com/) + [Svelte extension](https://marketplace.visualstudio.com/items?itemName=svelte.svelte-vscode) + [Tauri extension](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer).

```bash
npm install
npm run tauri dev     # development mode, needs a running antitheftd to talk to
npm run tauri build   # standalone production bundle for your platform
```
