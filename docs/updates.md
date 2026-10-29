# Updates

antitheft keeps itself up to date. There is nothing to turn on.

## How an update arrives

1. A few minutes after it starts, and a few times a day after that, the protection service asks for the newest
   release: first from [this repository's releases](https://github.com/kinnector/antitheft/releases/latest), and
   from our own mirror at `dl.antitheft.pro` when GitHub can't be reached.
2. It checks the release's signature against the antitheft release key built into it. A release that isn't signed
   with that key is ignored, wherever it came from.
3. It downloads the file for your system and checks its size and SHA-256 against the signed release.
4. It installs it, starts the new version and checks that it runs. If the new version doesn't come up, the previous
   one is put back by itself, and that version is not tried again.

A release is never older than the version you run: antitheft only ever moves forward.

## When an update waits

- **You're answering an alert.** If antitheft is holding a program and waiting for your answer, the update waits
  until you answer.
- **New terms.** When a release comes with updated Terms or Privacy policy, the app shows them first, and the update
  installs once you accept them. If you decline, updates stay off until you accept.

The **Updates** button in the app's title bar shows what is installed, what is waiting, and what changed in each
version.

## The release key

Every release carries `manifest.token`: the list of its files with their SHA-256 and size, signed with the antitheft
release key (Ed25519). The public half of that key:

```
u8amLvQRI4xRHnpuEwDpgUsdl2vS-URYNt6SoR_765c
```

Check a release with it yourself: [verify.md](verify.md).
