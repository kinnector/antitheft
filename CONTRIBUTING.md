# Contributing to Antitheft

Contributions are welcome.

## License and the CLA

Antitheft is **source-available, not open source**. It is offered to the public
under the [PolyForm Noncommercial License 1.0.0](./LICENSE.md), and separately
under commercial terms. A cloud subscription unlocks certain runtime
capabilities; it is not a separate codebase or license — see section 8 of
[`antitheft.md`](./antitheft.md).

Because the maintainer offers the Project under more than one set of terms, every
contributor must agree to the [Contributor License Agreement](./CLA.md) before
their contribution can be merged. The CLA lets the maintainer include your work
in both the noncommercial and the commercial distributions. You keep ownership of
your contributions.

Signing is a one-time step — see ["How to sign"](./CLA.md#how-to-sign) at the
bottom of the CLA. In short: on your first pull request, comment

```
I have read the CLA and I agree to it.
Signed, <your full legal name> <your email>
```

## Before you open a pull request

- **Build and run** per the "Build and run" section of [`README.md`](./README.md):
  `cargo build --release` in `agent/`, `npm install && npm run tauri dev` in
  `ui/`.
- The authoritative design is [`antitheft.md`](./antitheft.md). Enforcement and
  policy logic belongs on the agent (Rust) side; keep the `core` boundary intact.
- Keep changes focused; one logical change per pull request.
- Match the surrounding code style. Describe what you changed and how you
  verified it.

## Reporting security issues

Do not open a public issue for a security vulnerability. Email
<license@kinnector.dev>.
