#!/bin/sh
# antitheft installer for Linux and macOS:   curl -fsSL https://antitheft.pro/antitheft.sh | bash
# and to remove it:                          curl -fsSL https://antitheft.pro/antitheft.sh | bash -s uninstall
#
# What it does, in order:
#   1. reads the current release: the newest one on GitHub (github.com/kinnector/antitheft/releases, its
#      manifest.json), or https://dl.antitheft.pro/antitheft/latest.json when GitHub cannot be reached:
#        {"version": "1.2.3", "files": {"linux-x86_64-deb": {"url": "...", "sha256": "..."}, ...}}
#      file keys are <os>-<arch>-<package>: os linux | macos, arch x86_64 | aarch64, package deb | rpm | tar
#   2. picks the package for this computer (on Linux the release tarball when there is one, else deb where apt is,
#      rpm where dnf, zypper or yum is; tar on macOS)
#   3. downloads it from that GitHub release, else from https://dl.antitheft.pro/antitheft/<version>/, and checks its
#      SHA-256 against the release description (a copy that does not match is never installed)
#   4. installs it with the system's own package tool (sudo asks for your password when you are not root).
#      macOS has no package for it: the release is a .tar.gz holding the daemon, the app and install.sh
#      (antitheft repo, packaging/macos/), unpacked here and installed by its install.sh under sudo, which
#      signs both ad hoc on this Mac. Nothing passes through a browser, so Gatekeeper has nothing to check
#      and no Apple developer certificate is needed.
#   5. macOS only: asks whether to turn on macOS auditing, which antitheft needs to see which programs open
#      your vaults (Apple ships it off), turns it on with your yes, and offers to restart, which finishes it.
#      The app asks the same later if you say no here. Then it opens the app.
# `uninstall` (after `bash -s`): macOS runs the installed uninstall.sh under sudo (`--purge` also deletes
# antitheft's records, `--disable-auditing` turns auditing back off); Linux runs the installed uninstall.sh of a
# tarball install the same way (`--purge`), or says which package to remove.
# Nothing is installed when any step fails. No release published yet: it says STAGING MODE and stops.
#
# Environment: ANTITHEFT_DL (another download root holding latest.json and <version>/, used INSTEAD of GitHub
# and the mirror, for testing a release before it is public),
# ANTITHEFT_DRY_RUN=1 (download and verify, print the install command, install nothing),
# ANTITHEFT_AUDIT=yes|no (macOS: answer step 5 without asking, for an install with no terminal to ask in).
#
# Everything runs inside main(), called on the last line: a download cut short runs nothing at all.

set -eu

main() {
  if [ "${1:-}" = uninstall ]; then
    shift
    uninstall "$@"
    return
  fi
  # Where releases are: GitHub first, our own mirror when GitHub is blocked or down. ANTITHEFT_DL replaces both.
  gh="https://github.com/kinnector/antitheft/releases"
  mirror="https://dl.antitheft.pro/antitheft"
  if [ -n "${ANTITHEFT_DL:-}" ]; then gh=""; mirror="${ANTITHEFT_DL%/}"; fi

  need curl
  sha_tool

  os=$(uname -s)
  case "$os" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) die "antitheft has no package for $os. On Windows, open PowerShell and run: iwr https://antitheft.pro/antitheft.ps1 -useb | iex" ;;
  esac
  arch=$(uname -m)
  case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "antitheft has no package for $arch processors yet." ;;
  esac

  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t antitheft)
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT TERM

  # 1. the release: GitHub's newest, else the mirror's latest.json.
  # No release is: nothing on GitHub and no latest.json (404, or 403 from the bucket), or no download host at all yet (curl's 6, the name does
  # not resolve; this script itself just came from antitheft.pro, so the network is there).
  code=000
  if [ -n "$gh" ] && curl -fsSL --retry 2 -o "$tmp/latest.json" "$gh/latest/download/manifest.json" 2>/dev/null; then
    code=200
  else
    rc=0
    code=$(curl -sSL --retry 2 -o "$tmp/latest.json" -w '%{http_code}' "$mirror/latest.json" 2>"$tmp/curl.err") || rc=$?
    [ "$rc" -ne 6 ] || code=404
  fi
  case "$code" in
    200) ;;
    403 | 404)
      echo "STAGING MODE"
      echo "antitheft is not released yet: there is nothing to install. Check https://antitheft.pro for the launch."
      return 0 ;;
    *) die "could not reach the antitheft download server (HTTP $code). Check your connection and try again. $(cat "$tmp/curl.err" 2>/dev/null)" ;;
  esac
  # latest.json on one line, without spaces (it holds a version, keys, URLs and hex digests, none of which has any)
  json=$(tr -d ' \t\r\n' <"$tmp/latest.json")
  version=$(printf '%s' "$json" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  case "$version" in
    "" | *[!A-Za-z0-9._+-]*) die "the release description is unreadable (no valid version)." ;;
  esac

  # 2. the package for this computer
  package_kind
  key="$os-$arch-$pkg"
  entry=$(printf '%s' "$json" | sed -n "s/.*\"$key\":{\([^}]*\)}.*/\1/p")
  [ -n "$entry" ] || die "antitheft $version has no $pkg package for $os on $arch yet."
  url=$(printf '%s' "$entry" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
  sha=$(printf '%s' "$entry" | sed -n 's/.*"sha256":"\([0-9A-Fa-f]*\)".*/\1/p' | tr 'A-F' 'a-f')
  [ ${#sha} -eq 64 ] || die "the release description has no valid SHA-256 for $key."
  # Only the file NAME is taken from the description; where it is fetched from is ours (GitHub's release, the mirror).
  file=${url##*/}
  case "$file" in
    "" | *[!A-Za-z0-9._+-]*) die "the release names an unexpected file: $file" ;;
  esac

  # 3. download and verify: GitHub first, then the mirror; only a copy that matches the SHA-256 counts
  echo "Downloading antitheft $version ($file)..."
  ok=""
  for from in ${gh:+"$gh/download/v$version"} "$mirror/$version"; do
    rm -f "$tmp/$file"
    if ! curl -fSL --retry 2 --progress-bar -o "$tmp/$file" "$from/$file"; then
      echo "Could not download it from $from, trying the next place..."
      continue
    fi
    got=$($SHA "$tmp/$file" | awk '{print $1}')
    if [ "$got" = "$sha" ]; then ok=1; break; fi
    echo "The copy at $from does not match its SHA-256 (expected $sha, got $got), trying the next place..."
  done
  [ -n "$ok" ] || die "the download failed or did not match its SHA-256. Nothing was installed. Try again in a minute."
  echo "SHA-256 verified: $sha"
  # said before anything is installed: the daemon, its services and any boot change come before the app's own gate
  echo "By installing antitheft you agree to its Terms: https://antitheft.pro/terms/"
  echo "It runs with full system rights and can stop programs. To remove it: https://antitheft.pro/uninstall/"

  # 4. install
  case "$pkg" in
    deb) install_cmd apt-get install -y "$tmp/$file" ;;
    rpm)
      if have dnf; then install_cmd dnf install -y "$tmp/$file"
      elif have zypper; then install_cmd zypper --non-interactive install --allow-unsigned-rpm "$tmp/$file"
      else install_cmd yum install -y "$tmp/$file"; fi ;;
    tar)
      mkdir "$tmp/release"
      tar -xzf "$tmp/$file" -C "$tmp/release" || die "the download could not be unpacked."
      set -- "$tmp/release"/antitheft-*/install.sh
      [ -f "$1" ] || die "the download holds no installer (antitheft-*/install.sh)."
      install_cmd /bin/sh "$1" "${1%/install.sh}" ;;
  esac
  [ "$os" = macos ] && macos_auditing
  [ "${ANTITHEFT_DRY_RUN:-}" = 1 ] && return 0
  echo
  echo "antitheft $version is installed. Open the antitheft app to finish setting it up."
  # The app, as the person who ran this (never as root), when there is a screen to show it on.
  if [ "$os" = macos ] && [ "$(id -u)" -ne 0 ] && [ -d "$APP" ]; then
    open "$APP" >/dev/null 2>&1 || true
  fi
}

uninstall() {
  case "$(uname -s)" in
    Darwin)
      [ -x "$UNINSTALL" ] || die "antitheft is not installed on this Mac ($UNINSTALL is missing)."
      say "Removing antitheft..."
      as_root "$UNINSTALL" "$@" ;;
    Linux)
      if [ -f /usr/lib/antitheft/current/uninstall.sh ]; then
        say "Removing antitheft..."
        as_root /bin/sh /usr/lib/antitheft/current/uninstall.sh "$@"
      elif have apt-get && have dpkg; then say "To remove antitheft, run: sudo apt-get remove antitheft"
      elif have dnf; then say "To remove antitheft, run: sudo dnf remove antitheft"
      elif have zypper; then say "To remove antitheft, run: sudo zypper remove antitheft"
      else say "To remove antitheft, run: sudo yum remove antitheft"; fi ;;
    *) die "this script removes antitheft from Linux and macOS only." ;;
  esac
}

# 5. macOS: auditing (antitheftd audit-setup, agent/src/audit_setup.rs in the antitheft repo)
DAEMON="/Library/Application Support/Antitheft/antitheftd"
UNINSTALL="/Library/Application Support/Antitheft/uninstall.sh"
APP=/Applications/Antitheft.app
macos_auditing() {
  if [ "${ANTITHEFT_DRY_RUN:-}" = 1 ]; then
    say "dry run, would ask to turn on macOS auditing, then run: sudo \"$DAEMON\" audit-setup enable"
    return 0
  fi
  [ -x "$DAEMON" ] || { say "antitheft: the install did not put $DAEMON in place; open the app to finish setting it up." >&2; return 0; }
  step=$(as_root "$DAEMON" audit-setup status 2>/dev/null | sed -n 's/.*"step": *"\([a-z_]*\)".*/\1/p')
  case "$step" in
    active | reader_missing) say "macOS auditing is already on."; return 0 ;;
    needs_reboot) say "macOS auditing is set up already; restart your Mac to turn it on."; offer_restart; return 0 ;;
  esac
  echo
  say "antitheft sees which programs open your wallets, keychains and browser profiles through macOS auditing."
  say "Apple ships it switched off. Turning it on copies Apple's own audit settings into place and enables the audit"
  say "service; a restart finishes it. Without it antitheft is installed but cannot see or stop anything."
  if ! ask "Turn on macOS auditing now? [Y/n] " yes "${ANTITHEFT_AUDIT:-}"; then
    say "Skipped. The antitheft app asks again, or run: sudo \"$DAEMON\" audit-setup enable"
    return 0
  fi
  as_root "$DAEMON" audit-setup enable || { say "antitheft: turning on auditing failed; the app can try again." >&2; return 0; }
  step=$(as_root "$DAEMON" audit-setup status 2>/dev/null | sed -n 's/.*"step": *"\([a-z_]*\)".*/\1/p')
  [ "$step" = needs_reboot ] && offer_restart
  return 0
}

offer_restart() {
  if ask "Restart your Mac now to finish? [y/N] " no ""; then
    # The Apple menu's Restart: apps can save, and you can still cancel.
    osascript -e 'tell application "loginwindow" to «event aevtrrst»' >/dev/null 2>&1 \
      || say "Restart from the Apple menu when you are ready."
  else
    say "Restart when you are ready; antitheft starts watching once the Mac is back up."
  fi
}

# ask PROMPT DEFAULT(yes|no) PRESET: true for yes. The script itself is stdin under `curl | bash`, so the
# question goes to the terminal; with no terminal and no PRESET, the DEFAULT stands for "no" (nothing changes).
ask() {
  case "$3" in yes | y | 1) return 0 ;; no | n | 0) return 1 ;; esac
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf '%s' "$1" >/dev/tty
    read -r answer </dev/tty || answer=""
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) [ "$2" = yes ] && return 0 || return 1 ;;
    esac
  fi
  return 1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

say() { printf '%s\n' "$*"; }
die() { say "antitheft: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || die "this installer needs $1."; }

sha_tool() {
  if have sha256sum; then SHA="sha256sum"
  elif have shasum; then SHA="shasum -a 256"
  else die "this installer needs sha256sum or shasum to verify the download."; fi
}

# sets pkg: the package format this computer installs
package_kind() {
  if [ "$os" = macos ]; then pkg=tar; return; fi
  # Linux: the release tarball when the release has one (the antitheft repo's packaging/linux: a
  # systemd service, one folder per version, and it updates itself); packages otherwise.
  case "$json" in *"\"$os-$arch-tar\":"*) pkg=tar; return ;; esac
  if have apt-get && have dpkg; then pkg=deb; return; fi
  if have dnf || have zypper || have yum; then pkg=rpm; return; fi
  die "antitheft has packages for Debian, Ubuntu and their family (apt), and Fedora, RHEL, openSUSE and theirs (dnf, zypper, yum). This system has none of those package tools."
}

# runs a command as root (through sudo when needed), or only prints it in a dry run
install_cmd() {
  if [ "$(id -u)" -eq 0 ]; then run="$*"; else need sudo; run="sudo $*"; fi
  if [ "${ANTITHEFT_DRY_RUN:-}" = 1 ]; then say "dry run, would run: $run"; return 0; fi
  say "Installing: $run"
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

main "$@"
