# Check a download

You don't need to do this: the install scripts and antitheft's own updater check every file before installing it.
This page is for anyone who wants to see it for themselves.

## The SHA-256

Every release lists the SHA-256 of each file in its notes. Compare it with your download.

Windows (PowerShell):

```powershell
Get-FileHash .\antitheft-0.1.1-windows-x86_64-setup.exe
```

macOS:

```sh
shasum -a 256 antitheft-0.1.1-macos-x86_64.tar.gz
```

Linux:

```sh
sha256sum antitheft-0.1.1-linux-x86_64.tar.gz
```

## The signature

The SHA-256 in the release notes tells you the file is the one on the page. The signature tells you the release
itself comes from us. Every release carries `manifest.token`, its list of files (name, SHA-256, size) signed with the
antitheft release key. That key's public half is built into every installed copy, which refuses any update not
signed with it.

Public key (Ed25519):

```
base64url:  u8amLvQRI4xRHnpuEwDpgUsdl2vS-URYNt6SoR_765c

-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAu8amLvQRI4xRHnpuEwDpgUsdl2vS+URYNt6SoR/765c=
-----END PUBLIC KEY-----
```

### With the script

Download `manifest.token` and your file from the same release, then:

```sh
scripts/verify-release.sh manifest.token antitheft-0.1.1-windows-x86_64-setup.exe
```

```
signature OK: antitheft 0.1.1, signed with the antitheft release key
OK: antitheft-0.1.1-windows-x86_64-setup.exe (2f6c...)
```

It needs bash, OpenSSL 3 and base64 (Linux, macOS, or WSL / Git Bash on Windows).

### By hand

`manifest.token` is two base64url strings joined by a dot: the manifest (JSON), then the Ed25519 signature over the
bytes `antitheft-release-v1`, one zero byte, then the manifest.

```sh
token=$(cat manifest.token)
unb64url() { s=$(printf '%s' "$1" | tr '_-' '/+'); while [ $(( ${#s} % 4 )) -ne 0 ]; do s="$s="; done; printf '%s' "$s" | base64 -d; }

unb64url "${token%%.*}" > manifest.json
unb64url "${token#*.}" > signature.bin
{ printf 'antitheft-release-v1\0'; cat manifest.json; } > signed.bin

cat > antitheft-release.pem <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAu8amLvQRI4xRHnpuEwDpgUsdl2vS+URYNt6SoR/765c=
-----END PUBLIC KEY-----
EOF

openssl pkeyutl -verify -pubin -inkey antitheft-release.pem -rawin -in signed.bin -sigfile signature.bin
cat manifest.json
```

`Signature Verified Successfully` means the manifest is ours. It names each file's SHA-256: compare it with your
download as above.

## Check an installed copy

The manifest covers the downloads. Every release from 0.1.8 on also signs the list of every file inside them, so an
installed copy can be checked file by file at any time. The list is installed beside the programs as `files.token`
(with a readable copy, `files.json`), and attached to the release as `antitheft-<version>-windows-x86_64-files.token`.
It is signed the same way as `manifest.token`, over `antitheft-files-v1`, one zero byte, then the list.

### With the script (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-install.ps1
```

```
signature OK: antitheft 0.1.8 (windows-x86_64), signed with the antitheft release key
OK: all 20 installed files are exactly as released
```

It checks `C:\Program Files\Antitheft` against the `files.token` in it. To not trust the copy on the computer, download
the list from the release page and pass it: `-Token antitheft-0.1.8-windows-x86_64-files.token`. Any file that differs
is printed as `CHANGED`, `MISSING` or `ADDED`. The setup writes the install folder's path into two files of the
Claude Code plugin; the script puts the shipped text back before it compares them. The script runs no antitheft
program. The signature is checked with OpenSSL 3 (Git for Windows ships one).

### With antitheft itself

```powershell
& "C:\Program Files\Antitheft\antitheftd.exe" verify-install
```

The same check, by the installed program. antitheft also runs it each time its service starts and shows an alert for
any file that is not as released.
