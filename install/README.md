# Install script

The exact script the macOS and Linux one-line install runs, so you can read it before you run it. macOS and Linux are
not available yet; on Windows, use the signed installer from the [latest release](https://github.com/kinnector/antitheft/releases/latest).

| Command | Script |
| --- | --- |
| `curl -fsSL https://antitheft.pro/antitheft.sh \| bash` (macOS, Linux) | [antitheft.sh](antitheft.sh) |

What it does, in order:

1. Read the newest release's `manifest.json` from this repository's releases, or `latest.json` from our mirror at
   `dl.antitheft.pro` when GitHub can't be reached.
2. Pick the file for your system and processor.
3. Download it from the GitHub release (the mirror as a fallback) and check its SHA-256 against the manifest. A copy
   that doesn't match is never installed.
4. Install it with your system's own tools, asking for permission (sudo).

`ANTITHEFT_DRY_RUN=1` downloads and checks everything, prints what it would run, and installs nothing:

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | ANTITHEFT_DRY_RUN=1 bash
```

A daily check ([install-scripts.yml](../.github/workflows/install-scripts.yml)) compares this file with what
antitheft.pro serves.
