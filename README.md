<p align="center">
  <a href="https://antitheft.pro"><img src="assets/icon.png" width="96" height="96" alt="antitheft"></a>
</p>

<h1 align="center">antitheft</h1>

<p align="center">
  <b>Every program that reaches for your wallets has to get past antitheft.</b><br>
  Desktop protection for crypto wallets, saved passwords, browser logins and cookies, messengers and 2FA apps.<br>
  Windows, macOS and Linux.
</p>

<p align="center">
  <a href="https://github.com/kinnector/antitheft/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/kinnector/antitheft?label=release&color=3b82f6"></a>
  <img alt="Windows, macOS, Linux" src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-555">
  <a href="https://github.com/kinnector/antitheft/actions/workflows/verify-release.yml"><img alt="Release verified" src="https://github.com/kinnector/antitheft/actions/workflows/verify-release.yml/badge.svg"></a>
  <a href="https://antitheft.pro"><img alt="antitheft.pro" src="https://img.shields.io/badge/web-antitheft.pro-111"></a>
</p>

<p align="center">
  <a href="https://antitheft.pro">Website</a> ·
  <a href="docs/install.md">Install</a> ·
  <a href="docs/what-it-protects.md">What it protects</a> ·
  <a href="docs/faq.md">FAQ</a> ·
  <a href="https://github.com/kinnector/antitheft/releases">Releases</a> ·
  <a href="SUPPORT.md">Support</a>
</p>

---

Malware that steals from your computer doesn't break in through the front door. It is a cracked game, a "test task"
from a recruiter, a browser extension, a package a tool installed for you. Once it runs, it goes straight for the same
few files on every computer: your wallet, your browser's saved passwords and cookies, your Discord login.

antitheft keeps those files for the one app that owns them. Your wallet opens for your wallet app. Chrome's passwords
open for Chrome. Anything else that reaches for them is stopped, and you see what it was, where it came from and what
it tried to touch.

- **On Windows and macOS**, a program that touches a protected file is stopped, and you get an alert.
- **On Linux**, once kernel protection is on, any other program is refused before the file even opens.

No blocklist to keep up to date and no virus signatures to match: antitheft doesn't need to know the malware. It
knows your apps.

## What it protects

| | |
| --- | --- |
| **Crypto wallets** | Desktop wallets (Exodus, Electrum, Atomic, Ledger Wallet's data, Sparrow, Wasabi and more) and wallet browser extensions (MetaMask, Phantom, Rabby, Trust Wallet, Coinbase Wallet and any other wallet extension) |
| **Browsers** | Saved passwords, signed-in cookies, saved cards and autofill in Chrome, Edge, Brave, Firefox, Opera, Vivaldi, LibreWolf, Waterfox and more |
| **Your bank and exchange logins** | No add-on per site: the passwords and signed-in sessions for every site live in your browser's files, and only your browser opens them |
| **Password managers** | 1Password, Bitwarden, Keeper, Enpass, NordPass, Proton Pass and more |
| **Messengers** | Discord, Slack, Signal, Element |
| **2FA apps** | Authy, Ente Auth, Proton Authenticator and authenticator browser extensions |
| **Cloud storage logins** | Dropbox, MEGA, Nextcloud, pCloud, Syncthing, rclone |
| **Wallet apps' identity** | Every wallet app, hardware wallet companions included (Ledger Wallet, Trezor Suite, BitBoxApp...), is checked against its signed release. A replaced copy is marked **Hijacked** and kept away from the wallet |

Developer keys (SSH keys, AWS and other cloud credentials, `.env` files, git and registry tokens) are on the record: you
see which program read each one, and when. The full list, per system: [docs/what-it-protects.md](docs/what-it-protects.md).

## Install

**Windows 10 and 11:** download `antitheft-<version>-windows-x86_64-setup.exe` from the
[latest release](https://github.com/kinnector/antitheft/releases/latest) and run it.

**Windows, from PowerShell:**

```powershell
iwr https://antitheft.pro/antitheft.ps1 -useb | iex
```

**macOS and Linux:**

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | bash
```

The install scripts download the release from this page (from our own mirror at `dl.antitheft.pro` when GitHub can't
be reached) and check its SHA-256 before installing anything. Read them before you run them: [install/](install/).
Step by step, and how to uninstall: [docs/install.md](docs/install.md).

## Updates

antitheft updates itself. Every release is signed with the antitheft release key, and an installed copy checks that
signature and every file's SHA-256 before it installs anything. An update that doesn't start properly is rolled back
by itself. More: [docs/updates.md](docs/updates.md).

## Check a download yourself

Each release lists the SHA-256 of every file and carries `manifest.token`, the release signed with the antitheft
release key. [scripts/verify-release.sh](scripts/verify-release.sh) checks both with plain `openssl`:

```sh
scripts/verify-release.sh manifest.token antitheft-0.1.1-windows-x86_64-setup.exe
```

On Windows, [scripts/verify-release.ps1](scripts/verify-release.ps1) does the same. Every release is also checked
this way in public as soon as it is published ([Verify release](https://github.com/kinnector/antitheft/actions/workflows/verify-release.yml)).
How it works and how to do it by hand: [docs/verify.md](docs/verify.md).

## Price

**$10 per computer, a year.** Renews yearly, cancel any time, money back within 14 days. Without a subscription
antitheft runs in watching-only mode: it shows everything that reaches for your files, and stops nothing.
For a business licence, write to [business@antitheft.pro](mailto:business@antitheft.pro).

## Questions

**Is it an antivirus?** No. An antivirus looks for known malware. antitheft doesn't need to recognize the malware:
it guards the files malware goes for, and lets only their own apps in. It works next to your antivirus.

**Something I trust was stopped.** Every alert names the program and where it came from. Mark it as not a threat
from the alert. If antitheft keeps getting one of your apps wrong, [tell us](https://github.com/kinnector/antitheft/issues/new?template=false-alert.yml).

**Why is the source code not here?** This repository holds antitheft's releases, documentation and issue tracker.
The source code is not public. You are welcome to examine antitheft itself on your own computer: see
[SECURITY.md](SECURITY.md).

More in the [FAQ](docs/faq.md).

## Support and feedback

- Questions and help: [SUPPORT.md](SUPPORT.md), or [support@antitheft.pro](mailto:support@antitheft.pro)
- Something wrong: [open an issue](https://github.com/kinnector/antitheft/issues/new/choose)
- An app you want protected: [request it](https://github.com/kinnector/antitheft/issues/new?template=app-request.yml)
- A security problem: [SECURITY.md](SECURITY.md), never a public issue

## In this repository

| | |
| --- | --- |
| [Releases](https://github.com/kinnector/antitheft/releases) | Every version: installers, `manifest.json` and the signed `manifest.token` |
| [docs/](docs/) | Install, updates, what it protects, checking a download, FAQ |
| [install/](install/) | The scripts behind the one-line installs |
| [scripts/](scripts/) | Release checkers for macOS, Linux and Windows |
| [.github/workflows/](.github/workflows/) | Public checks: every release verified, install scripts compared with antitheft.pro |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |

## Legal

antitheft is licensed, not sold, under the [Terms](https://antitheft.pro/terms/). See also the
[Privacy policy](https://antitheft.pro/privacy/) and [LICENSE](LICENSE).

<sub>antitheft by kinnector. Wallet, browser and app names belong to their owners and are used only to say what antitheft protects.</sub>
