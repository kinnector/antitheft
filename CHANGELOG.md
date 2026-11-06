# Changelog

Every release, newest first. Installed copies update themselves; the app's Updates button shows the same notes.
Downloads: [Releases](https://github.com/kinnector/antitheft/releases).

## 0.1.9

- Game stores and their games are never removed by antitheft. Please update.
- Windows: Steam and Epic Games logins are protected.
- Windows: more of what Chrome, Edge, Brave and other Chromium browsers keep is protected, in every profile.
- Antigravity on Windows works with antitheft again.
- Better support for Cursor and Antigravity.
- Agents and editors you connected stay connected after updates and restarts, without asking again.
- An AI agent can ask to be disconnected from antitheft; you decide in a window.
- Editor extension improvements.
- The Access log counts every read in the range you pick.
- Fewer false alerts.

## 0.1.8

The first public release.

- antitheft now updates itself. Every release is signed, and your computer checks the signature and every file
  before installing it.
- Every installed file is on a signed list. antitheft checks its own files each time it starts and alerts you if one
  is not as released, and you can check them yourself ([docs/verify.md](docs/verify.md)).
- Fewer false alerts from installers, app updaters and programs that only read a browser's settings.
- Updated Terms and Privacy policy: the app asks you to accept them once.
- You can choose to send us reports about what antitheft blocked or allowed, so we can fix wrong decisions. They are
  off unless you turn them on in Settings, carry no account, name or files, and the updated Privacy policy describes
  them.
- AI agents and code editors: antitheft connects to Claude Code, Codex, Cursor and Antigravity, and to VS Code,
  Cursor, VSCodium, Antigravity, JetBrains IDEs and Android Studio through its own extension. Agents and editors have
  their own pages in Settings, each with Connect and Disconnect.
- When an agent or an editor is stopped from reading a protected store, the alert names it, and the agent is told why
  in plain words.
- A new agent or editor on your computer is noticed, and the app offers to connect it.
- Removing antitheft now takes it out of every agent and editor it connected, for every user on the computer.
- An agent keeps working normally while antitheft is not running.
- Fewer false alerts from browsers with temporary or custom profiles, and from shared folders.
- The app window comes to the front when you open it.
