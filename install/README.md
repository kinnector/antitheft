# Install scripts

The exact scripts the one-line installs run, so you can read them before you run them:

| Command | Script |
| --- | --- |
| `curl -fsSL https://antitheft.pro/antitheft.sh \| bash` (macOS, Linux) | [antitheft.sh](antitheft.sh) |
| `iwr https://antitheft.pro/antitheft.ps1 -useb \| iex` (Windows) | [antitheft.ps1](antitheft.ps1) |

What they do, in order:

1. Read the newest release's `manifest.json` from this repository's releases, or `latest.json` from our mirror at
   `dl.antitheft.pro` when GitHub can't be reached.
2. Pick the file for your system and processor.
3. Download it from the GitHub release (the mirror as a fallback) and check its SHA-256 against the manifest. A copy
   that doesn't match is never installed.
4. Install it with your system's own tools, asking for permission (sudo or Windows' prompt).

`ANTITHEFT_DRY_RUN=1` downloads and checks everything, prints what it would run, and installs nothing:

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | ANTITHEFT_DRY_RUN=1 bash
```

A daily check ([install-scripts.yml](../.github/workflows/install-scripts.yml)) compares these files with what
antitheft.pro serves.
