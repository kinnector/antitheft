# Kinnector Desktop

Kinnector Desktop is the cross-platform visual administration console and dashboard for the Kinnector endpoint protection agent, built with Tauri, SvelteKit, and TypeScript.

---

## What it protects

Security threats on developer workstations and personal devices often go unnoticed when buried in background daemon logs. 

Kinnector Desktop brings host telemetry to the foreground. It visualizes behavioral detections in real-time, manages local containment actions, and alerts users to active threats like credential access attempts, system persistence changes, and reverse shells.

---

## Why traditional interfaces are insufficient

Security software frequently operates as a "black box," silently blocking processes without explaining why or providing an easy way to override false positives. Conversely, command-line security tools are difficult for developers and home administrators to monitor across multiple devices.

Kinnector Desktop provides absolute transparency. It shows the exact process tree and heuristics rule that triggered a detection, allowing developers to manage allowlists and contain threats from a single, intuitive interface.

---

## Core Capabilities

* **Interactive Alert Visualizer**: View the exact system event logs, process chains, and rule triggers that led to a security block.
* **Crowdsourced Reputation Check**: Instantly verify if unsigned developer binaries have been run safely by other users in the community, reducing false-positive friction.
* **Remote Containment Controls**: Trigger host isolation, severing all network connections except for the Kinnector API, and quarantine suspected process trees with a single click.
* **Identity Leak Scanner**: Monitors credential databases and public infostealer logs in the background for compromised emails or browser sessions.

---

## Technical Architecture

Kinnector Desktop is built on a progressive, low-overhead stack:

```
[ Local Agent Daemon ] ──(JSON-RPC / UNIX Socket)──> [ Tauri Core ] ──> [ SvelteKit Frontend ]
```

* **Frontend**: SvelteKit 2 + Svelte 5 (Vite) and Tailwind CSS for responsive, lightweight UI rendering.
* **Backend**: Tauri (Rust) interfacing directly with the local agent control socket `/var/run/kinnector/control.sock`.
* **Central Fleet Integration**: Connects to the Kinnector Cloud API to aggregate multi-device alerts into a unified family or team dashboard.

---

## Getting Started

### Recommended IDE Setup
* [VS Code](https://code.visualstudio.com/) + [Svelte Extension](https://marketplace.visualstudio.com/items?itemName=svelte.svelte-vscode) + [Tauri Extension](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer).

### Build and Run

To run the desktop application in development mode:

```bash
npm install
npm run tauri dev
```

To build a standalone production bundle for your platform:

```bash
npm run tauri build
```
