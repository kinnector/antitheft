# Antitheft — technical design

Status: **design only, nothing built against this yet**. The existing `antitheft-agent`, `antitheft-agent-pro`, `antitheft-cli`, `antitheft-cli-pro`, `antitheft-pro` repos are pre-existing and not in good shape — this document is a from-zero architecture, not a description of what's currently in those repos. Treat this as the target to build toward, and reconcile/replace existing code against it rather than extending it as-is.

**No Pro/OSS binary split for Antitheft.** Unlike Warden, there is one agent, one CLI, one GUI — all fully open source. "Cloud" is not a separate paid codebase, it's a subscription entitlement that unlocks cloud-dependent *capabilities* (telemetry streaming, bank/exchange page-integrity, behavioral correlation, fleet manager) inside the same binary at runtime. Do not create an `antitheft-agent-pro` crate, an `antitheft-cli-pro` crate, or any code path gated by "is this the Pro build" — gate on "does this device have an active subscription token," checked live against the cloud, same binary either way. The existing `antitheft-agent-pro` / `antitheft-cli-pro` repos are legacy naming from before this decision and should be folded into the single OSS repos, not treated as a target structure.

The **functional requirements** (what must be true from a user's perspective) are derived from `antitheft/index.html`, the product page — that page is the source of truth for *what* Antitheft does. This document is the source of truth for *how*. Specific supported apps/wallets/banks/exchanges are **not enumerated here** — they land later as config data (see [Config & rule domain](#config--rule-domain)), the same way Warden never hardcodes framework/service signatures.

---

## 1. Product boundary

Antitheft answers one question, continuously, for a fixed set of sensitive resource categories on a user's machine: **"is the process touching this resource the one process allowed to touch it?"** If no, the access is refused before it completes.

Two enforcement shapes come out of that one question:

1. **Storage-ownership enforcement** — file/registry/keychain-backed secrets (passwords, wallet key material, 2FA seeds, SSH keys, dev/cloud credentials, game-client session data). Local, deterministic, free tier.
2. **Content-integrity enforcement** — browser-rendered surfaces where the *storage* is fine but the *content shown to the user* or *payload actually submitted* has been tampered with (bank pages, CEX/DEX pages, wallet transaction popups). Requires correlating browser process state, extension context, and DOM — cloud tier for bank/exchange, local for wallet popups since a wallet extension is already something the agent tracks as owned storage.

A third capability, **behavioral correlation over time** (supply-chain lateral movement, RAT/backdoor persistence patterns), doesn't fit either enforcement shape — no single event is conclusive, so it's necessarily cloud-side and probabilistic rather than a local allow/deny decision.

These three map directly to three subsystems below: §4 (storage locking), §5 (page/content integrity), §6 (behavioral correlation).

---

## 2. Component map

```
                     ┌────────────────────────────┐
                     │        antitheft.dev cloud  │   subscription-gated
                     │  ingestion · correlation ·  │   capabilities, not a
                     │  fleet manager · billing    │   separate codebase
                     └───────────▲────────────────┘
                                 │ mTLS, device-scoped token
                                 │ (only sent/consumed when entitlement check passes)
                    ┌────────────┴─────────────┐
                    │      antitheftd (local)   │◄──── unix socket / named pipe ────┐
                    │  built on core/'s engine  │                                    │
                    │  + antitheft collectors   │                              antitheft-cli
                    │  + policy/decision engine │                              (operator TUI/CLI)
                    │  + built-in cloud client   │
                    │    (entitlement-gated)     │
                    └───────┬───────────┬───────┘
                             │           │
                  native msg │           │ local HTTP API (127.0.0.1, loopback-only)
                             │           │
                 ┌───────────▼──┐   ┌────▼─────────────┐
                 │  browser ext │   │   antitheft-gui   │  Tauri desktop GUI
                 │ (integrity   │   │  (dashboard, alerts,
                 │  probe)      │   │   subscription mgmt)
                 └──────────────┘   └───────────────────┘
```

- **`antitheftd`** — the one and only agent daemon, fully open source, no Pro variant. One binary, all platforms. Owns the enforcement decision for every resource-access event, *and* owns the cloud telemetry client, correlation-result consumer, and licensing/entitlement check — all in the same codebase. Which cloud-dependent capabilities are active is decided at runtime by whether the device currently holds a valid subscription entitlement, not by which binary is installed. Runs as a privileged background service (root/SYSTEM) because kernel-level interception requires it.
- **`antitheft-cli`** — operator-facing CLI/TUI, one crate, no `pro` split. Talks to `antitheftd` over the local API; views that depend on cloud data (fleet, cloud alert feed) simply render "subscribe to unlock" when the daemon reports no active entitlement, same binary either way.
- **`antitheft-gui`** (currently named `antitheft-pro` in the existing repo — rename recommended, since "-pro" wrongly implies a separate paid codebase) — consumer-facing desktop GUI (Tauri), for the audience that will never open a terminal: install status, live alert feed, subscription management, fleet view if entitled. Talks to `antitheftd` over the same local API `antitheft-cli` uses — no separate protocol, no separate binary per tier.
- **Browser extension** — new component, not yet represented by any existing repo. Required for §5. Talks to `antitheftd` via the browser's native-messaging host mechanism (stdio-based, OS-registered), not a network socket. Ships as one extension; bank/exchange checks simply no-op without an entitlement, same extension either way.
- **Cloud backend** — new *service*, inherently separate infrastructure (it's a server, not something that ships on-device) but not "the Pro codebase" — it's what `antitheftd` talks to once entitled. Doesn't exist anywhere in the workspace today (`backend/`, `kinnector-fleet`, `kinnector-observer` are all legacy per workspace `CLAUDE.md` and shouldn't be resurrected as-is). Greenfield: ingestion API, correlation engine, fleet manager, billing/entitlement.

---

## 3. Enforcement layer (per platform, blocking)

Extends `core/`'s existing collectors rather than reimplementing kernel interception, where those collectors actually exist — verified per-platform state (as of the last audit) lives in `core/src/<platform>/{WINDOWS,LINUX,MACOS}_COVERAGE_PLAN.md`, and it's uneven: Linux already has real, working, synchronous kernel-level **deny** capability via BPF LSM hooks (just not yet wired to an owner-allowlist match — see `LINUX_COVERAGE_PLAN.md`); Windows has ETW-based detection-only collection and zero kernel-mode driver code; macOS has **no collector code at all** despite `CMakeLists.txt` referencing files that don't exist — that platform is a from-zero implementation gap with an already-detailed design spec (`kinnector-context/detection-engine/mac.md`) to build from, see `MACOS_COVERAGE_PLAN.md`. Antitheft needs, per platform: (a) **blocking** hooks where they don't already exist, (b) the owner-allowlist enforcement logic itself, which doesn't exist as kernel-level policy on any platform yet, and (c) a couple of new collector types (clipboard, USB device I/O, browser native-messaging bridge) that are desktop-specific and out of scope for `core/`'s current server/container focus.

### Linux
- `fanotify` with `FAN_OPEN_PERM` (or `FAN_ACCESS_PERM` where applicable) on the specific protected paths registered from the config domain (§7) — permission events let the kernel block until userspace responds, which is exactly the primitive needed.
- eBPF LSM hooks (`security_file_open` or equivalent) as the fallback/complement for cases `fanotify` can't scope tightly enough (e.g. distinguishing by more than path — need accessing-process identity at decision time, which fanotify's `FAN_OPEN_PERM` response payload already gives via the responding PID's `/proc/<pid>/exe`).
- This is the same primitive class `core/` already uses for its Linux collectors — the new work is wiring permission-event *responses* (allow/deny) instead of only consuming notification events.

**GNOME Keyring / KWallet are Linux's real decryption boundary for many credential stores, and — like DPAPI on Windows (below) — this has not previously been flagged as residual risk anywhere in this doc.** Both implement the freedesktop.org "Secret Service" D-Bus API (`org.freedesktop.secrets`), and any process running **as the logged-in user** can call `Secret.Service.Unlock`/`OpenSession` on the same keyring session a legitimate app would use — the Secret Service API has no concept of this product's owner-allowlist and will hand back the decrypted secret for whichever process asks, exactly analogous to `CryptUnprotectData` on Windows. Practically: (a) same scope boundary as DPAPI's — "only the owning app can read it" means "read the encrypted-at-rest keyring database file," not "produce the plaintext secret," and that needs to be stated as explicitly here as it is for Windows; (b) **unlike Windows' ALPC gap, Linux has a real, existing kernel-enforced mechanism for this**: AppArmor's D-Bus mediation (`dbus_bind`/`dbus_send`/`dbus_receive` rules) can gate specific interface+method+destination D-Bus messages, including `org.freedesktop.Secret.Service.OpenSession`/`Unlock`, not just log them — this makes D-Bus method-call interception **in scope for a later implementation phase**, not automatic residual risk the way Windows ALPC's complete absence of a framework forces it to be. The caveat: this only holds on systems where AppArmor is installed and actively enforcing (Ubuntu/Debian-family defaults; not SELinux-based distros, and not any system with AppArmor disabled) — on those systems, or as a fallback until the AppArmor-profile-generation work is built, the same "encrypted-bytes-only" scoping caveat as DPAPI applies, and should be stated as such rather than implied solved.

### macOS
- Endpoint Security Framework (ESF), `ES_EVENT_TYPE_AUTH_OPEN` (and `AUTH_EXEC` for process-level decisions where relevant, e.g. hardware-wallet companion app impersonation checks). ESF auth events are natively blocking — the client returns allow/deny before the kernel lets the operation proceed.
- Requires the Endpoint Security entitlement (Apple-gated, needs the app to be notarized and the entitlement granted) — this is an operational/signing dependency to track, not a technical unknown.
- **Correction from an earlier draft of this doc**: `core/` does *not* already have an ESF/FSEvents collector — verified directly, `core/src/macos/` doesn't exist at all, and `CMakeLists.txt`'s Darwin build branch references three `.cpp` files that aren't in the repo, so it wouldn't even configure on a real Mac today. This is a from-zero implementation gap, though not a from-zero *design* gap — `kinnector-context/detection-engine/mac.md` already specifies the hybrid ESF (proactive, blocking)/OpenBSM+FSEvents (reactive fallback when the entitlement isn't granted) architecture in detail. See `core/src/macos/MACOS_COVERAGE_PLAN.md` for the full implementation plan.

### Windows

Base mechanism: a signed kernel-mode **minifilter driver** hooking `IRP_MJ_CREATE`, plus `CmRegisterCallbackEx` for registry-key protection, plus a matching user-mode service the driver defers decisions to. This is the single largest net-new engineering item in this whole design — a real kernel driver, WHQL/EV code-signing, and its own release/signing lifecycle independent of `antitheftd`'s.

That base mechanism alone is not sufficient, and treating it as sufficient is the actual risk. Linux/macOS enforcement can lean on "every resource access eventually goes through the VFS/open() path," which is roughly true. Windows has no equivalent unifying layer — the Object Manager exposes files, registry keys, processes/threads, sections, named pipes, and ALPC ports as distinct object types, each with its own access-check path, and a minifilter only ever sees one of those (files). Below is what falls outside file-open-only coverage, and what's needed to close each gap. This list should be treated as the actual Windows spec, not the single paragraph above.

**Handle duplication and inheritance.** `DuplicateHandle()` lets one process hand a fully-capable handle to a protected file, already opened and already past the create-time check, to a second process — no new `IRP_MJ_CREATE` fires for the receiving process. `CreateProcess(..., bInheritHandles=TRUE, ...)` with an inheritable handle does the same at process-creation time. A minifilter that only gates the open call is blind to both. Needs Object Manager callbacks (`ObRegisterCallbacks`, `OB_OPERATION_HANDLE_DUPLICATE`) registered against the relevant object types to gate duplication the same way creation is gated — Process/Thread object-type support for this is well established (it's the standard AV self-protection technique); File object-type support needs to be validated during implementation rather than assumed, since most public examples target Process/Thread.

**Section objects / memory-mapped access.** `NtCreateSection` requires an already-open file handle, so it doesn't bypass the create-time check by itself — but it does mean data keeps flowing to the calling process through ordinary memory reads long after the create-time decision was made, invisible to anything that only logs/audits on `IRP_MJ_CREATE`/`IRP_MJ_READ`. Matters less for pure block-on-open enforcement (the gate already happened), more for two things: (a) access-mask granularity — a process legitimately opened with a narrow mask (e.g. `FILE_READ_ATTRIBUTES`) must not be able to silently escalate via a section mapped with broader rights, so the driver has to evaluate the requested access mask at open time, not just "was open allowed at all"; (b) anything that wants post-open auditing of what was actually read needs a different signal than IRP counting.

**Raw volume / physical disk access.** Opening `\\.\C:` or `\\.\PhysicalDrive0` and reading sectors directly bypasses path-based semantics entirely — there is no filename in that create request for a path-keyed locator to match against. A minifilter attached at the volume-device level does see the open, but reconstructing "does this raw read land on the protected file's clusters" in real time isn't practical. **Residual-risk decision, not solved by extending the path-matching logic**: gate raw volume/physical-drive opens behind their own coarse allowlist (deny by default for any process not on a short, config-driven list of legitimate disk/backup/imaging tools), separate from per-resource protected-path matching.

**Volume Shadow Copy (VSS) access.** Shadow copies expose the same file at a different device path (`\Device\HarddiskVolumeShadowCopy<N>\...`), letting a "frozen" copy of a protected file be read through a path a path-glob locator was never told about. Requires normalizing shadow-copy device paths back to their source volume's canonical path before policy evaluation, not treating them as a separate unprotected namespace.

**Path aliasing (hardlinks, junctions/reparse points, 8.3 short names, `\\?\`/`\??\` prefixes, alternate data streams).** Same class of problem as symlink-race attacks on Linux: a locator keyed on a literal path string can be routed around by any of the above. Decisions must resolve to a **canonical identity** (volume serial number + NTFS File Reference Number) before matching against policy, not compare raw path strings.

**Registry hives as plain files.** `CmRegisterCallbackEx` only sees live registry API calls. The hives backing those keys (`NTUSER.DAT` and friends) are ordinary NTFS files, and when not actively locked — or via a VSS snapshot of them, or via backup APIs like `RegSaveKey` — they can be read as a raw file, skipping the registry callback path completely. Hive files need to also be registered as protected file-path resources, as a required complement to the registry-key protection, not a redundant one.

**DPAPI is the real decryption boundary for many Windows credential stores, and it isn't a file access at all.** Chrome/Edge and most Windows apps encrypt saved secrets with DPAPI (`CryptProtectData`/`CryptUnprotectData`), scoped to the logged-in user's master key (current Chrome adds an "app-bound encryption" layer via a privileged helper tied to the browser's own install, which raises the bar further but is Chrome-specific). Any process running **as that logged-in user** can call `CryptUnprotectData` directly — DPAPI has no concept of this product's owner-allowlist and will decrypt for whichever process asks, regardless of what happened at file-open time. Practically: (a) be explicit internally that "only the owning app can read it" means "read the encrypted-at-rest bytes," not "produce the plaintext" — that's a real scope boundary, not a bug; (b) the `Microsoft-Windows-Crypto-DPAPI` ETW provider exposes `CryptUnprotectData`/`NCryptUnprotectSecret` calls with caller-process context — apply the same owner-allowlist check to those calls, keyed to which credential store's blobs are involved, as a second enforcement point alongside the file-open check. Attribution precision here needs a validation spike before this can be treated as a solved mechanism, not a designed one.

**Injection into the owner process itself — the general case, not just remote-thread injection.** This is the sharpest gap, and identity-pinning by path + code signature does not close it: if an attacker gets code running inside the real, legitimately-signed `1Password.exe`, every subsequent file open genuinely originates from that authentic binary — the OS-level identity check is *correctly* satisfied, because the compromise is inside the trusted process, not impersonating it from outside. There isn't one injection technique to detect here, there are several, and they matter differently for the design:

- `CreateRemoteThread`/`NtCreateThreadEx` — creates a **new** thread in the target running attacker-supplied code. The most detectable variant (a new thread appearing is a strong signal).
- **APC injection** (`QueueUserAPC`/`NtQueueApcThread(Ex)`) — queues attacker code onto an **existing** thread of the target, which runs it the next time that thread enters an alertable wait. No new thread is created, no `SetThreadContext` call happens — it's substantially stealthier than remote-thread injection and needs to be treated as a distinct primitive to watch for, not assumed covered by "detect remote thread creation."
- `SetThreadContext` thread hijacking — redirects an existing (usually suspended) thread's instruction pointer directly, no APC involved.

All three require the attacker to first **obtain a process or thread handle to the target with dangerous access rights** (`PROCESS_VM_WRITE`, `PROCESS_VM_OPERATION`, `PROCESS_CREATE_THREAD`, `THREAD_SET_CONTEXT`, `THREAD_SUSPEND_RESUME`, or enough to queue an APC). That shared prerequisite is the actual choke point, and it's the same `ObRegisterCallbacks` mechanism already needed for handle-duplication coverage above (`PsProcessType`/`PsThreadType`, well-precedented for exactly this — it's the standard AV/EDR self-protection technique): **strip those specific access rights from any `OpenProcess`/`OpenThread`/`DuplicateHandle` request targeting a configured owner process, unless the requester is on a short, explicit allowlist** (the OS itself, the owner app's own installer/updater where legitimately needed, and nothing else). Done at the handle-acquisition step, this pre-empts all three injection techniques at once, rather than trying to detect each one's after-the-fact behavior separately — detection (module-load monitoring, unbacked-executable-memory scanning) is still worth having as a backstop for whatever handle-right restriction doesn't catch, but it's secondary, not the primary mechanism.

This generalizes into a principle worth stating explicitly: **on Windows, trust cannot be a one-time decision made at resource-open time — it has to be a continuously-revocable property of a specific running process instance.** A process that passed the identity check five minutes ago is not guaranteed to still be the process it claims to be. Revoke trust for that instance the moment an injection indicator fires against it, independent of whatever its image path and signature still say.

**Access-token duplication/impersonation is a separate primitive from the process/thread injection above, and this design does not currently cover it.** `DuplicateTokenEx` lets a sufficiently privileged process copy another process's access token (including a SYSTEM or other elevated token) into a new token object it fully controls; `ImpersonateLoggedOnUser`/`SetThreadToken`/`CreateProcessWithTokenW` then let it act under that identity going forward. This is the mechanism behind `SeImpersonatePrivilege`-abusing privilege-escalation chains (the "potato" family — RottenPotato/JuicyPotato/PrintSpoofer and successors, which coerce a SYSTEM-context connection and steal its token) and is also what turns an LSASS memory read (§3's already-noted residual risk, above) into a *usable* impersonated identity rather than just dumped credential material sitting in a dump file. **Object Manager's Token object type is not addressed anywhere in this document.** The handle-duplication coverage described above (`OB_OPERATION_HANDLE_DUPLICATE` registered against `PsProcessType`/`PsThreadType`) only gates handles to process/thread objects — a `DuplicateHandle`/`OpenProcessToken` + `DuplicateTokenEx` chain targeting a protected owner process's token is a distinct code path that would need its own `ObRegisterCallbacks` registration against the Token object type, and unlike Process/Thread, Token-object support for `ObRegisterCallbacks` is not a well-precedented AV/EDR pattern the way process/thread interception is — its feasibility needs to be validated during implementation, not assumed by analogy. Until that validation and implementation happen, treat token duplication/impersonation targeting a protected owner process's identity as an **explicit residual risk**, held to the same "state it plainly, don't imply it's solved" standard as the ALPC and raw-volume gaps below, not something implicitly covered by the injection-prevention mechanism above.

**ALPC has no general third-party blocking framework — this is a real capability gap, not a hook to add.** Unlike files (`FltRegisterFilter`) and the registry (`CmRegisterCallbackEx`), there is no documented minifilter-equivalent attachment point for arbitrary ALPC ports; a third-party driver cannot generally intercept-and-allow/deny an `NtAlpcConnectPort` call the way it can a file create. (Named pipes are different and *are* covered — see below — because they're served through NPFS, an ordinary filterable filesystem.) Practical scope, stated honestly rather than implied-solved: (1) harden **Antitheft's own** local communication surface specifically, since that part is fully controllable — the driver-to-service channel and the loopback API §9 describes should verify the connecting process's identity (PID resolved to image path + signature, not just "something connected to 127.0.0.1 or the pipe") on every connection, not trust anything that can reach the port; (2) for third-party owner apps that use ALPC for their own control plane, there is no separate ALPC-specific defense to add beyond what's already covering the injection vector that would let an attacker manipulate that channel in the first place — the owner-process handle-right restriction and integrity monitoring above is the mitigation, not a new ALPC hook.

**Named pipes, separately, are addressable.** NPFS-backed named pipes are visible to a minifilter attached to `\Device\NamedPipe\`, unlike ALPC ports. Some credential-adjacent IPC (an extension talking to a desktop companion app, a hardware-wallet bridge) goes over named pipes specifically — the locator schema (§7) now has a `named_pipe` kind for this; don't conflate it with the ALPC gap above, they need different treatment.

**Kernel-level self-protection.** A sufficiently privileged attacker (BYOVD — loading their own vulnerable-but-signed driver, or a stolen code-signing cert) can unhook the minifilter, patch its callback pointers, or kill its user-mode service outright. Mitigate with PPL (Protected Process Light) status for the service and driver tamper-protection against stop/unload by anything less than the equivalent of what Defender requires for itself — but state this plainly as a **residual risk, not a solved problem**: a fully privileged kernel-level attacker is close to unstoppable by any endpoint agent, and the design should say so rather than imply otherwise.

### Common decision path (all platforms)
1. Kernel hook fires on an operation touching a path/key/keychain-item that matches a registered protected resource.
2. Hook captures the accessing process's identity (PID, executable path, and where the platform allows it, a hash or code-signature of the on-disk binary at the time of the call — **anchor on path + binary identity, never PID alone**, since PIDs are reused and trivially spoofable as a trust anchor) and resolves the *resource* to a canonical identity rather than the raw path string handed to the call — volume/device ID + inode (Linux/macOS) or volume serial + NTFS File Reference Number (Windows) — so hardlinks, junctions/reparse points, 8.3 short names, and alternate path prefixes can't route around a path-glob match.
3. Identity is resolved against the resource's owner list (§4) via the in-memory rule index `kinnector-config` loaded at startup / hot-reload.
4. Allow → operation proceeds transparently, latency budget target sub-millisecond (this is on the hot path of every file open on the box, not just protected ones, so the pre-filter that decides "is this path even protected" must be cheap — a prefix/hash-set lookup, not a linear scan).
5. Deny → kernel call returns a permission error to the caller (`EACCES`/`EPERM` on Linux, the ESF-equivalent denial on macOS, `STATUS_ACCESS_DENIED` from the minifilter on Windows). Event is logged locally always, and additionally forwarded to cloud telemetry if the device is entitled.

**Why this attribution is close to a hard guarantee, and why process lineage is irrelevant to it.** The requesting process's identity is captured directly from the I/O request's context at the moment the kernel dispatches it (the requesting thread the I/O manager built the IRP for, on Windows; the calling task on Linux/macOS) — never derived from parent/child ancestry. A process detaching from its spawning parent, getting orphaned, breaking away from a job object, or spoofing its reported parent PID at creation changes nothing here, because the check was never looking at lineage to begin with — only at who is issuing *this* request, right now. This guarantee holds as long as the filter is loaded and functioning and the request goes through the filtered I/O path — it breaks only the ways already named as residual risk above (pre-existing/duplicated handles, raw-volume bypass, kernel-level filter tampering), not through any form of process-lineage manipulation. **Contrast this with cross-process memory reads** (an attacker reading an owner process's live decrypted secrets straight from RAM instead of ever touching the file — the LSASS-dump playbook, applied here): gated by the same `PROCESS_VM_READ` restriction as the injection-prevention mechanism in §3, but structurally weaker, not equivalent — Ob callbacks only gate *new* handle acquisition, so a handle obtained before the driver loaded (an early-boot race, or pre-existing persistence) keeps its already-granted rights, since there's no simple native way to downgrade an already-issued handle's access mask after the fact. Mitigate with boot-start driver load ordering to shrink the race window, plus periodic system-wide handle-table auditing (`SystemHandleInformation` walk) as a detect-and-revoke backstop — but state this plainly rather than implying parity with file-open attribution: **file-read/write authorship is close to a hard guarantee; process-memory-read protection against an already-resident attacker is a strong mitigation, not one.**

---

## 4. Storage-ownership subsystem

Covers: password managers & browser vaults, software wallets, hardware-wallet companion-app storage, game-store client sessions, 2FA/authenticator vaults, SSH keys, dev/cloud credentials, and — reusing the exact same primitive — the local supply-chain behavior checks (a postinstall script "reading a secret it doesn't own" is the same check as any other unauthorized-reader event).

### Resource classification
A **protected resource** is a `(platform, locator, category)` tuple, where `locator` is one of:
- filesystem path or glob (most cases — vault files, wallet keystores, `.ssh/*`, `.env`, cloud CLI credential files)
- Windows registry key path (some credential stores use the registry, not files)
- macOS Keychain service/account identifier (Keychain items aren't plain files — need `SecItem` API-level interposition or ESF's keychain-specific event types, not just file hooks, for full coverage there)
- browser-extension storage directory pattern (for extension-based wallets/password managers, scoped per-browser-profile)

### Owner identity
Each protected resource has an **owner set**: one or more `(binary_path_pattern, identity_pin)` entries, where `identity_pin` is a code-signature check (preferred, where the platform supports verifying a running binary's signing identity cheaply — Authenticode on Windows, codesign on macOS) or a content hash pin (Linux, or as a fallback). This mirrors the existing workspace convention of anchoring trust on path/image-digest rather than PID (see prior Warden trust-semantics work) — same principle, applied to a new domain.

Decision is a straightforward allowlist match, never a blocklist: **not in the owner set → denied**, full stop, no heuristic scoring needed for this subsystem (that's what makes it fast and low-false-positive — it's the storage-locking claim from the product page).

### Dev-secrets scoping nuance
Dev/cloud credentials need *narrower* per-secret-type owner sets than "the app that created it" (a `.env` file isn't created by one canonical app the way a password vault is) — owner sets here are keyed by **secret type**, not by the specific file, e.g. "AWS credentials file" → owned by `{aws, terraform, and other explicitly configured CLI tools}` regardless of which project's `.env`/credentials file is being touched. This is exactly the kind of list that must live in config (§7), not source, since it'll grow continuously as new CLI tools get added.

### Package-manager / supply-chain reuse
Local supply-chain detection is *not* a separate mechanism — it's the storage-ownership check plus three additional "sensitive action" categories that get the same allow/deny treatment, scoped to processes descended from a package-manager lifecycle script (a known package-manager binary from the config domain, e.g. `npm`, `pip`, `cargo`).

**Scoping this by live-walking `ParentProcessId` at the time of the sensitive action is exactly wrong, and vulnerable to the same detachment tricks that don't work against §3's authorship guarantee** — a malicious lifecycle script can spawn a detached grandchild (job-object breakaway, explicit re-parenting, or just enough generations of forking) that no longer appears as a descendant of `npm` by the time it acts, silently exempting it from scoping that was supposed to apply. `ParentProcessId` is also just unreliable for this on its own: it can reflect a since-exited parent, and PID reuse means a stored-PID ancestry table can misattribute. Instead: stamp a **persistent lineage marker** once, at the moment a process is first identified as (or descended from) a package-manager invocation, propagated forward to every descendant at the moment of creation, unconditionally, regardless of later re-parenting or job-object breakaway. This is the same "identity is a property fixed at a point in time and carried forward, not re-derived lazily by walking mutable state" principle as §3's requestor-identity guarantee — apply it here too.

**Concrete Linux mechanism** (well-precedented — Falco, Cilium Tetragon, and Tracee all maintain the same kind of live-tree cache for the same reason, this isn't novel): attach eBPF to the `sched_process_fork` tracepoint and the `bprm_check_security` LSM hook. Both run synchronously in-kernel at the moment of the event, which matters — it's what makes this race-free. Inside the eBPF handler, read `task->start_time` off the `task_struct` (via `bpf_probe_read_kernel`/CO-RE) at that exact instant and pair it with the PID as a composite key; never key the lineage table on raw PID alone, since Linux recycles PIDs fast (especially under fork-bomb-style postinstall churn) and a PID-only table lets a dead process's entry get silently inherited by an unrelated new one. On `bprm_check_security`, check the newly-exec'd binary's path/hash against the package-manager config domain (§7) and stamp a root marker if it matches. On every `sched_process_fork`, copy the parent's marker onto the child's lineage-table entry before userspace ever executes a single instruction in that child — this is what actually defeats double-forking, `setsid()`, and reparenting-to-init tricks, since none of them touch the already-copied, kernel-captured marker. Keep the eBPF programs thin (push `(event_type, composite_key, parent_composite_key, exec_path_hash)` to a `BPF_MAP_TYPE_RINGBUF`) and let `antitheftd` own the actual tree and marker table in userspace, pruned on `sched_process_exit` events, with a bounded table size (a fork bomb targeting the tracker itself is a plausible DoS) and a periodic `/proc`-reconciliation sweep as a correctness backstop if the ring buffer's dropped-event counter ever indicates the consumer fell behind. Verify whether `core/`'s existing Linux collectors already track process lifecycle with this composite-key discipline before assuming it — the marker-propagation policy logic is Antitheft-specific either way and is new regardless.

**Concrete Windows mechanism — same shape, one extra wrinkle.** The direct analog is `PsSetCreateProcessNotifyRoutineEx2`: a driver-registered kernel callback firing synchronously during every process creation, before the new process's first instruction runs — same race-freedom property as the Linux hooks, and stronger in one respect, since `PS_CREATE_NOTIFY_INFO.CreationStatus` can veto the creation outright, not just observe it. Composite key follows the same discipline as Linux, since Windows PIDs get reused aggressively too: `(PID, PsGetProcessCreateTimeQuadPart(EPROCESS))`, captured at the same synchronous callback — never expose a raw `PEPROCESS` pointer to user-mode `antitheftd` across the driver/service boundary, that's a kernel-pointer-leak anti-pattern, expose the `(PID, create-time)` pair instead. Marker stamping (image path/hash vs. the package-manager config domain) and propagation (copy the creator's marker to the new child before the callback returns) work the same as Linux.

**The one genuinely Windows-specific subtlety: don't propagate off `ParentProcessId`.** Windows has a well-known technique — parent-PID spoofing via `PROC_THREAD_ATTRIBUTE_PARENT_PROCESS` — where a process claims a different process (e.g. `explorer.exe`) as its parent purely for the metadata field that `InheritedFromUniqueProcessId`/Task Manager/Process Explorer display. That field is genuinely spoofable. What isn't spoofable is which thread actually executed the `NtCreateUserProcess` syscall — `PS_CREATE_NOTIFY_INFO` carries that separately as `CreatingThreadId`, reflecting the real calling context regardless of the claimed parent. Propagate the lineage marker using the process owning `CreatingThreadId`, never `ParentProcessId` — the Windows equivalent of "capture the real creator synchronously in-kernel, don't trust the reported ancestry field." (Exact `PS_CREATE_NOTIFY_INFO` field behavior should be validated against the current WDK header during implementation, not assumed from this description — same caveat as the File-object `ObRegisterCallbacks` coverage noted in §3.) With that in place, `CREATE_BREAKAWAY_FROM_JOB`, job-object detachment, and PPID spoofing all fail to defeat propagation the same way double-forking and `setsid()` fail against the Linux design — none of them touch what the kernel callback actually observed at creation time.

With that fixed, the three sensitive-action categories are:
- credential access → same owner-set check as above, just evaluated against *any* protected secret rather than one the script has a legitimate reason to touch
- persistence write → matches against a config-defined set of persistence locations (autostart entries, cron/systemd paths, LaunchAgents, Windows Run keys) — install scripts have no legitimate owner claim to these, so this list is a pure deny-list, not an owner-set match
- wallet-storage touch → same resource locators as software-wallet protection in this same subsystem
- process injection → `ptrace`/`process_vm_writev` (Linux), `task_for_pid`/similar (macOS), `WriteProcessMemory`/`CreateRemoteThread` (Windows) calls made by a lifecycle-script-descended process, hooked at the same kernel layer as §3

---

## 5. Content-integrity subsystem

Covers: bank pages, CEX/DEX pages (cloud-gated per the product page), and software-wallet transaction/seed-phrase popups (local, since wallet extensions are already owned/tracked storage).

This can't be a file-open hook — the thing being protected is *rendered content and signed payloads*, not a resource being read. Needs a **browser extension** as a probe inside the page/extension context, correlated against what the browser process itself is doing.

### Three correlated signals
1. **Process-level** — is the browser's own process behaving as expected (no unexpected injected modules, no HVNC-style hidden-desktop rendering of the browser window)? Sourced from `antitheftd`'s process/window telemetry (`core/`-derived), not the extension.
2. **Extension-context level** — the extension's own isolated JS context reads the "true" state where the API allows it (e.g. reading the actual `to`/`value` fields of a pending transaction request via the wallet's provider API interception, before the popup renders its formatted display).
3. **DOM level** — what's actually painted in the popup/page, read via content-script DOM inspection.

`antitheftd` (not the extension itself, and not the cloud, for the local wallet-popup case) is the correlator: the extension forwards signals 2 and 3 over native messaging, `antitheftd` already has signal 1, and it diffs them. Mismatch between what's rendered and what's actually signed/submitted → block by instructing the extension to intercept and cancel the in-flight action (`preventDefault`/provider-request rejection) before the user can confirm, and surface a native OS-level block notification.

For the **cloud-gated** bank/exchange case, the same three-signal model applies but the correlation and the "is this page/origin one we should even be watching" decision additionally depends on a domain-classification list (which domains are recognized banks/exchanges) that's realistically too large and fast-changing to hot-reload locally at the fidelity needed — hence cloud tier. Local agent still does the mechanical diffing; cloud supplies the domain classification and, notably, this is also where session/HVNC correlation across the *whole OS session* (not just the tab) matters, which needs the cloud-side behavioral-correlation machinery from §6 anyway.

### Extension architecture notes
- One extension, not one per browser-family — build on `webextension-polyfill` or equivalent so Chromium/Firefox/Safari share one codebase; native-messaging host registration differs per browser and must be handled by `antitheftd`'s installer for each.
- Extension needs to intercept wallet provider calls (`window.ethereum.request` and equivalents) at a point *before* the wallet extension's own popup renders — this requires document-start content-script injection racing the target wallet extension's own injection, which is inherently timing-sensitive and needs empirical testing per target wallet rather than a one-size approach.

---

## 6. Behavioral correlation subsystem (cloud, subscription-gated)

Covers: supply-chain lateral movement (post-install `.env` exfiltration, package-manager config poisoning), and RAT/backdoor/persistence detection (HVNC, reverse shells, reverse SOCKS, droppers).

Unlike §4/§5, this is explicitly **not** a local allow/deny decision — the product claim is that a single event is indistinguishable from legitimate tooling, and only cross-time/cross-install correlation makes the call. Architecture:

1. **Local agent streams structured events** (not raw telemetry) — process spawns, network connections with process attribution, package-manager lifecycle invocations, persistence-location writes — to the cloud ingestion endpoint. Only entitled, enrolled devices stream; an install with no active subscription never phones home. This is a runtime check inside `antitheftd` itself (valid entitlement token present and verified → stream; absent/expired → don't), not a compile-time/binary distinction.
2. **Ingestion service** — per-device event stream, device identity via the enrollment token issued at subscription time (mTLS or signed token, not a static API key baked into the agent binary).
3. **Correlation engine** — evaluates chains of events per device (and, for supply-chain, across devices/installs where patterns repeat — this is where "worm-like spread" detection lives, since a single dev's machine can't see that the same malicious package behaved identically on 500 other machines). This is a genuinely new service; no existing workspace component does this today. Reasonable to build as a rules/window-based correlation engine first (define suspicious chains declaratively) rather than a bespoke ML system for v1 — keeps it debuggable and matches the "config-driven, not hardcoded" philosophy already established for signature data.
4. **Verdict delivery** — flagged chains get pushed back down to the device (or surfaced only in the cloud dashboard/fleet manager, TBD by how time-sensitive a given verdict class is) and/or trigger a kill/quarantine action on the implicated process tree via the same local enforcement primitives as §3, just triggered by a cloud verdict instead of a local rule match.

---

## 7. Config & rule domain

Following the workspace's existing hard rule (no hardcoded match lists in source — see Warden's `protect-community/configs/warden/` + `kinnector-config` pattern): Antitheft needs its **own** config domain, e.g. `protect-community/configs/antitheft/`, loaded the same way — Ed25519-signed, compiled to FlatBuffers, hot-reloadable via `kinnector-config` so `antitheftd` never restarts to pick up a new supported wallet or bank.

Note: `protect-community/configs/antithief/` already exists but is explicitly marked stale/legacy in the workspace `CLAUDE.md` (different spelling too — "antithief" vs "antitheft") — do not resurrect it as the new domain; it's old and unrelated to this design. Start the new domain clean.

**`core`/`antitheftd` boundary**: `core` never links or parses `kinnector-config` — the same boundary Warden already uses for its firewall/inode rules (dumb FFI setters like `add_sensitive_inode`/`add_firewall_cidr`; "the rule store and diffing is owned by the calling agent, Core owns the enforcement decision itself," per `core/README.md`). `antitheftd` is what loads/parses `protect-community/configs/antitheft/` via `kinnector-config` and diffs on hot-reload; it then pushes resolved protected-resource entries into `core` through a matching FFI call keyed on `core`'s platform-native canonical identity (volume serial + NTFS FRN on Windows, dev+inode on Linux).

Schema (structure only — **no actual entries belong in this document**, they get added incrementally as real config data once this is built):

```
ProtectedResource {
  id: string
  platforms: [linux|macos|windows]
  category: enum (password_manager | browser_vault | software_wallet |
                   hardware_wallet_companion | game_client | totp_vault |
                   ssh_material | dev_credential)
  locator: {
    kind: path_glob | registry_key | keychain_item | browser_ext_storage | named_pipe
    pattern: string
    # resolved to a canonical resource identity at decision time (volume+inode /
    # volume-serial+FileReferenceNumber), never matched on the raw path string alone
  }
  owners: [ { binary_path_pattern: string, identity_pin: signature|hash, pin_value: string } ]
  # Windows only, optional: for stores whose real decryption boundary is DPAPI rather
  # than the file itself (see §3), the same owners list additionally gates
  # CryptUnprotectData/NCryptUnprotectSecret calls attributed to this store's blobs.
}

ContentIntegrityTarget {
  id: string
  category: enum (bank | exchange_cex | exchange_dex | wallet_popup)
  tier: local | cloud
  domain_pattern: string           # for bank/exchange
  expected_extension_id: string?   # for wallet_popup
  baseline_source: string          # how "expected" DOM/payload shape is derived/verified
}

PersistenceLocation {
  id: string
  platforms: [...]
  locator: path_glob | registry_key
}

PackageManagerContext {
  id: string
  ecosystem: node|python|rust|php|ruby|java|dotnet
  binaries: [string]                # npm, yarn, pnpm, ...
}

CorrelationRule {                    # cloud-side only
  id: string
  event_chain: [...]                 # declarative chain definition
  window: duration
  verdict_action: alert | quarantine
}
```

`kinnector-config`'s existing atomic hot-reload and signature validation apply unchanged — this is a new *domain* within the same loading mechanism, not a new mechanism.

---

## 8. Free / subscription boundary

**This is explicitly not the Warden OSS/Pro model.** Warden splits *code* into two crates because `warden-pro` is a separately licensed, separately distributed binary. Antitheft has no such split — `antitheftd`, `antitheft-cli`, the GUI, and the browser extension are each a single open-source codebase, and every capability's code ships in that one codebase regardless of subscription status. The only thing a subscription changes is whether a runtime entitlement check passes, which decides whether cloud-dependent code paths are allowed to activate (stream telemetry, enable bank/exchange checks, accept correlation verdicts, show fleet data). There is no `antitheft-agent-pro` crate, no `pro` cargo feature, no second binary to build or distribute.

| Capability | Ships in the OSS codebase | Requires active entitlement to activate |
|---|---|---|
| Storage-ownership enforcement (§4), all categories | ✅ | no — always on |
| Local supply-chain behavior blocking (§4 reuse) | ✅ | no — always on |
| Wallet-popup local content-integrity check (§5) | ✅ | no — always on |
| Bank/exchange page-integrity check (§5) | ✅ (same extension) | yes — needs cloud domain-classification data |
| Cloud telemetry streaming client | ✅ (built into `antitheftd`) | yes — won't stream without a valid token |
| Behavioral correlation (§6) | ✅ (agent-side enforcement of verdicts ships OSS) | yes — the correlation itself is inherently a cloud service |
| Fleet manager enrollment/reporting | ✅ | yes |
| `antitheft-cli` fleet views, cloud alert feed | ✅ (same binary) | yes — renders "subscribe to unlock" without one |

Entitlement checks live in one place inside `antitheftd` (a single "is this device currently entitled" function, checked live/cached-with-expiry against the cloud), not scattered per-feature — everything above just asks that one function before doing cloud-dependent work.

---

## 9. Local API / IPC

`antitheftd` should expose one local-only surface both `antitheft-cli` and `antitheft-gui` consume — no reason for two protocols. Recommend mirroring Warden's approach: an HTTP API bound to loopback only (`127.0.0.1:<port>`, or a Unix domain socket / named pipe where the platform makes that cleaner than a loopback port), rather than inventing a bespoke IPC framing. Surface needs at minimum: live alert/event stream (SSE or long-poll), current protected-resource inventory + status, pause/resume enforcement, quarantine/allow actions on a flagged process, and license/entitlement status for the subscription-gated views.

This surface (and the Windows driver-to-service channel specifically) is itself an attack target — see §3's ALPC discussion — and must authenticate the connecting process (resolve PID → image path + signature, not just "something reached the loopback port/pipe") rather than trusting any local connection, since it can pause/quarantine/allow enforcement decisions.

Native-messaging to the browser extension is a separate, necessarily different channel (stdio-based, browser-mandated) — not something to try to unify with the CLI/GUI API.

---

## 10. Open items / phasing

- Windows minifilter driver is the long pole — signing/WHQL lead time alone likely dwarfs the rest of this design's implementation time. Track it as its own workstream from day one. The driver scope is **not just `IRP_MJ_CREATE`** — see §3's Windows subsection: handle-duplication/inheritance coverage (Ob callbacks, File-object-type support needs validation), registry-hive file protection alongside live registry-key callbacks, and named-pipe coverage are all part of v1 driver scope, not later hardening.
- Five Windows gaps are **explicit residual risk, not solved by this design**, and should be stated as such to anyone relying on the product's claims rather than quietly assumed away: raw physical-disk/volume access (coarse allowlist-gated, not per-resource matched), DPAPI as the true plaintext-decryption boundary for many credential stores (this product protects the encrypted-at-rest bytes; a logged-in-user-context process calling `CryptUnprotectData` directly is a real, only partially-mitigated gap pending the ETW-attribution validation spike noted in §3), access-token duplication/impersonation (`DuplicateTokenEx`/`ImpersonateLoggedOnUser` and `SeImpersonatePrivilege`-abusing "potato"-family escalation — Object Manager's Token object type has no `ObRegisterCallbacks` coverage in this design at all, unlike Process/Thread), ALPC's lack of any general third-party blocking framework (mitigated only indirectly, via owner-process handle-right restriction — there's no ALPC-specific hook to add), and a fully privileged kernel-level attacker (BYOVD) unhooking the driver outright.
- Linux's DPAPI-equivalent gap — GNOME Keyring / KWallet's Secret Service D-Bus API (`Secret.Service.Unlock`/`OpenSession`, callable by any process running as the logged-in user, bypassing the owner-allowlist entirely) — is scoped in §3's Linux subsection: same "encrypted-at-rest bytes only" caveat as DPAPI, but **not automatic residual risk** the way Windows' ALPC gap is, since AppArmor's D-Bus mediation (`dbus_send`/`dbus_receive` rules) is a real existing mechanism that can gate the specific Secret Service method calls — conditional on AppArmor being installed and enforcing (true by default on Ubuntu/Debian-family distros, not SELinux-based ones). Treat the AppArmor-profile-generation work as a genuine later implementation phase, not a "maybe someday," but don't claim plaintext-secret protection on Linux until it's built.
- Owner-process handle-right restriction (`ObRegisterCallbacks` stripping `PROCESS_VM_WRITE`/`THREAD_SET_CONTEXT`/etc. from untrusted `OpenProcess`/`OpenThread`/`DuplicateHandle` requests against configured owner processes) is the primary defense against APC injection, remote-thread injection, and thread hijacking **together**, and is required v1 infrastructure, not optional hardening — without it, identity-pinning-on-open is defeated by anything that compromises the owner process from inside rather than impersonating it from outside. Module-load/unbacked-executable-memory monitoring is a secondary detection backstop, not the primary mechanism. Same underlying principle as the attacker-side injection checks in §4, applied protectively to the owner list — and reinforces the point in §3 that trust must be continuously-revocable per running process instance, not a one-time decision at open time.
- macOS ESF entitlement approval (Apple-gated) is a similarly external dependency to kick off early.
- **Windows Antimalware-PPL/ELAM certification (Microsoft-gated) is a newly-identified external dependency, added 2026-08-26** — the same shape as the macOS ESF entitlement bullet above, but for Windows's `Microsoft-Windows-Threat-Intelligence` ETW provider (§3's injection-visibility source, `core/src/windows/WINDOWS_COVERAGE_PLAN.md` Phase 4). Empirically confirmed on a real elevated-Administrator session that `EnableTraceEx2` against this provider returns `ACCESS_DENIED` — ordinary elevation is not sufficient; the process must be running at Antimalware-PPL, which itself requires Microsoft's ELAM (Early Launch Antimalware) driver certification program, a separate track from the WHQL minifilter certification the driver bullet above already flags. Until this certification is obtained, Phase 4's injection-visibility and token-impersonation-detection work cannot ship for real — kick off the ELAM application early, alongside WHQL, rather than discovering this gap later in the driver workstream.
- Cloud backend (§6 correlation engine, §5 domain-classification service, fleet manager) is 100% greenfield — no existing legacy service should be reused as a starting point.
- Existing `antitheft-agent-pro` / `antitheft-cli-pro` repos should be retired — folded into `antitheft-agent`/`antitheft-cli` as the entitlement-gated code paths described in §8, not kept as separate crates. `antitheft-pro` (the Tauri GUI repo) should be renamed to drop the "-pro" implication once convenient, since it's just the GUI, not a paid tier.
- `protect-community/configs/antithief/` (stale) should be left alone; new domain is `configs/antitheft/`.
- Reconcile whatever's salvageable in the current `antitheft-agent` (`yara_scanner.rs`, `sigma_engine.rs`, `trust_cache.rs`, etc.) against this design deliberately, file by file, rather than assuming any of it survives as-is — none of that was used as input to this design.
