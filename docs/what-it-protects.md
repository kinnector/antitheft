# What antitheft protects

antitheft does two things with the files on your computer that thieves go for:

- **Kept for their own app.** Only the app that owns the file may open it. On Linux, with kernel protection on, any
  other program is refused before the file opens. On Windows and macOS, a program that touches it is stopped. Either
  way you get an alert naming the program, where it came from and what it reached for.
- **On the record.** Every program may open the file, and you see which one did, and when, in the app's Activity.

Apps antitheft finds on your computer are listed under **Vaults** in the app, with what it guards for each.

## Kept for their own app

**Browsers**: saved passwords, signed-in cookies, saved cards and autofill, and the browser's own key files.
Google Chrome, Chromium, Microsoft Edge, Brave, Opera, Vivaldi, Yandex Browser, Firefox, LibreWolf, Waterfox.

This covers every site you sign in to through the browser, banks and exchanges included: their passwords and sessions
live in the browser's files, so no add-on per site is needed.

**Wallet browser extensions**: MetaMask, Phantom, Rabby, Trust Wallet, Coinbase Wallet, and any other extension
that is a wallet. Their storage opens only for the browser they live in.

**Desktop crypto wallets**: Exodus, Electrum (and Electrum-LTC, Electron Cash, Dash Electrum), Atomic Wallet, Bisq,
Feather, Guarda, Ledger Wallet's data, Monero GUI, Sparrow, Wasabi.

**Password managers**: 1Password, Bitwarden, Keeper, Enpass, NordPass, Proton Pass. KeePass and KeePassXC: their
settings and browser connection; the `.kdbx` database itself lives wherever you keep it and is not covered.

**Messengers**: Discord, Slack, Signal, Element.

**2FA apps**: Authy, Ente Auth, Proton Authenticator, and authenticator browser extensions.

**Cloud storage logins**: Dropbox, MEGA, Nextcloud, pCloud, Syncthing, rclone.

**Email**: Thunderbird's saved logins.

**Keyrings**: the desktop keyring files on Linux (GNOME Keyring, KWallet).

## Identity checks

Every wallet app, hardware wallet companions included (Ledger Wallet, Trezor Suite, BitBoxApp, Keystone, OneKey,
GridPlus and more), is checked against its signed release. A copy that was replaced is marked **Hijacked** and kept
away from the wallet. On Linux, a debugger reaching into a protected wallet app is refused.

## On the record

**Developer secrets**: SSH keys, AWS, Google Cloud and Azure credentials, kubeconfig, Docker logins, Terraform,
Vault, Vercel, Netlify, Fly.io, Cloudflare and other cloud tools, `.env` files, git credentials, GitHub and GitLab
tokens, npm, PyPI and other registry tokens, database client passwords, GnuPG.

On Linux, turn on **SSH hardening** in Settings to keep your private SSH keys for SSH itself.

**Command-line crypto wallets**: Bitcoin Core, Monero CLI, geth, Solana CLI, Foundry, Hardhat and others.

## Start-up places (Linux)

Start-up entries, systemd units, cron jobs and shell profiles are where malware settles in to stay. On Linux, a
package install that tries to add one is refused at the file, and any other change shows up under **Auto start**
for you to look at.

## What it does not cover

- Your documents, photos, projects and other personal files.
- Anything you hand over yourself: a password typed into a fake site, a seed phrase pasted into a form, a
  transaction you approve, a stranger you let control your computer.
- Removing malware. antitheft stops what reaches for your vaults; use your antivirus to clean the computer.

What antitheft covers grows with each release. Missing an app? [Ask for it](https://github.com/kinnector/antitheft/issues/new?template=app-request.yml).
