# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is (and is not)

A **local macOS activity & time-quality tracker**. It samples the foreground application
and, for browsers, the active tab's URL/title, classifies each observation as
educational / productive / news / social / entertainment / sports / games, and reports
whether time looks well-spent vs wasted (the "what are they actually doing" question).

It does **not** capture keystrokes. Despite the `key_logger` directory name, there is no
`CGEventTap`, no keystroke content capture, and no input logging anywhere in the codebase —
this was a deliberate scope decision. `spec.md` is the *original* brief and still describes
system-wide keystroke logging; **the implementation intentionally diverges from it**. Do not
add keystroke-content capture: it is a system-wide credential-harvesting capability that the
productivity goal does not require, and every feature in `spec.md` (websites, YouTube titles,
game/app time, dashboards, export) is achievable from window/tab metadata alone. If asked to
"follow the spec," prefer the metadata approach and flag the divergence.

Deploying to other Macs (install steps, permissions, run-at-login) is documented in `DEPLOY.md`.
`build.sh` targets macOS 12 by default (`MACOS_MIN` overrides) so binaries built on a newer Mac
run on older Intel laptops.

## Build & test

SwiftPM (`swift build` / `swift test`) is the intended workflow **but is currently broken in
this checkout's environment**: the bundled Command Line Tools ship a `PackageDescription`
dylib that fails to link the manifest for x86_64 (`symbol(s) not found ... __allocating_init`).
Until a full Xcode toolchain is present, use the direct-`swiftc` scripts:

```bash
./build.sh     # compiles ActivityCore module + activitytracker into .build-direct/
./test.sh      # builds the module and runs Tests/run.swift assertions
```

`swift build` / `swift test` should work once full Xcode is installed (they drive
`Package.swift` + the XCTest target in `Tests/ActivityCoreTests/`). When SwiftPM works again,
keep both test entry points in sync — `Tests/run.swift` (plain-main, used by `test.sh`) and
`Tests/ActivityCoreTests/ClassifierTests.swift` (XCTest) assert the same behavior.

Run a single logical test by editing/commenting checks in `Tests/run.swift`; under XCTest use
`swift test --filter ClassifierTests/testYouTubePokemonIsEntertainment`.

### Running the CLI

```bash
.build-direct/activitytracker once          # one sample (good for verifying permissions)
.build-direct/activitytracker permissions   # show Accessibility/Automation status
.build-direct/activitytracker track         # foreground sampling loop (Ctrl-C to stop)
.build-direct/activitytracker report --today
.build-direct/activitytracker notify --hours 1   # email last hour's report now
.build-direct/activitytracker export --days 7 --out activity.csv
```

## Email notifications (Resend)

`track` sends an **hourly** report plus a **daily summary** (fired once when the local calendar
day rolls over, covering the day that just ended). `notify` sends one on demand:
`notify --hours N` for the trailing N hours, `notify --daily` for today so far. All go through
the Resend HTTP API (`EmailReporter`). Configuration is environment-only — the API key is never
written to disk:

```bash
export RESEND_API_KEY=re_xxxxxxxx           # required; without it email is silently disabled
export RESEND_FROM=onboarding@resend.dev    # optional (this default works only in test mode)
export RESEND_TO=dharamarao.bala@manabadi.siliconandhra.org   # optional; this is the built-in default
```

Deliverability caveat: `onboarding@resend.dev` is Resend's shared test sender and will only
deliver to the **email address that owns the Resend account**. To send to an arbitrary address
(e.g. the manabadi one), verify a domain in Resend and set `RESEND_FROM` to an address on it.

Scheduling options (pick one):
- Leave `track` running — it self-schedules the hourly send (`emailPeriod` in `main.swift`).
- Or run `notify` from `launchd`/`cron` every hour while a separate `track` collects data.

The send path is verified against the live API in this repo's history (an invalid key returns a
parsed `401`); `EmailReporter.html(...)` is pure and covered by the test suite. Tests never make
network calls.

## Architecture

Two targets: `ActivityCore` (all logic, fully unit-testable) and `activitytracker` (thin CLI
in `Sources/activitytracker/main.swift` that parses args and wires Core together).

The data flow is a one-directional pipeline; the key design choice is that **acquisition and
classification are decoupled** through the `ActivityContext` value type:

```
Sampler ──reads──> ActivityContext ──> Classifier ──> ActivitySample ──> Store ──> Reporter
 (NSWorkspace +                          (pure, from                     (SQLite)   (aggregate
  BrowserInspector +                      config rules)                              + CSV)
  Accessibility)
```

- **`Sampler`** (`Sources/ActivityCore/Sampler.swift`) — the only component that touches the
  OS. Polls `NSWorkspace.frontmostApplication` on an interval (no event tap, so no
  input-monitoring entitlement). For supported browsers it pulls the active tab via
  `BrowserInspector`; otherwise it reads the focused window title via the Accessibility API
  (read-only, guarded by `AXIsProcessTrusted()`). Everything it learns goes into an
  `ActivityContext` — nothing else downstream knows *how* the signal was obtained.

- **`BrowserInspector`** (`BrowserInspector.swift`) — reads `(url, title)` of the front tab
  via per-browser AppleScript (`NSAppleScript`). Chromium browsers share one dialect; Safari
  differs. Adding a browser = add a bundle-ID → script entry in the `scripts` map. This is the
  only place that needs macOS **Automation** permission (prompted per-browser at runtime).

- **`Classifier`** (`Classifier.swift`) — pure and deterministic, no system calls, which is
  why it carries the test coverage. Precedence: (1) native-app bundle ID match (a game/IDE
  wins outright) → (2) browser host match, with media hosts like youtube.com **re-bucketed by
  title keywords** so a "lecture" counts as educational but "pokemon"/"cricket" do not → (3)
  keyword vote on a non-browser window title → (4) `unknown`. `quality(for:)` maps category →
  well-spent / neutral / wasted.

- **`ClassificationConfig`** (`ClassificationConfig.swift`) — all rules are *data*
  (host→category, bundle→category, keyword buckets), with a `.default` set and JSON override
  at `~/.activitytracker/classification.json`. Tune *what counts as well-spent* here, not in
  classifier code.

- **`Store`** (`Store.swift`) — SQLite via the system `SQLite3` module (single `samples`
  table at `~/.activitytracker/activity.sqlite`). Local-only; data leaves the machine only via
  explicit `export`. `purge(olderThanDays:)` implements the retention setting.

- **`EmailReporter`** (`EmailReporter.swift`) — renders a `Reporter.Summary` to HTML (pure,
  testable) and POSTs it to Resend. `Config.fromEnvironment` reads `RESEND_API_KEY`/`RESEND_FROM`/
  `RESEND_TO`; a missing key means email is disabled, not an error. The synchronous `send`
  blocks on `URLSession` via a semaphore (CLI context). Driven from `main.swift`: the `track`
  loop's `onTick` fires the hourly send on each `emailPeriod` boundary and the daily send when
  `Calendar.startOfDay` advances; `notify` sends once. The sampler stays unaware of email — it
  only exposes the `onTick` hook.

- **`Reporter`** (`Reporter.swift`) — turns point samples into durations. **Each sample
  represents ~`interval` seconds**; there are no explicit session start/end rows, so all
  durations are `count × interval` approximations. The sampler interval and the reporter
  interval must match (both default to 5s, set in `main.swift`) or reports will be wrong.

### Things worth knowing before changing code

- `interval` is defined in `main.swift` and passed to both `Sampler` and `Reporter`. If you
  make it configurable, thread the *same* value to both.
- `Package.swift` is `swift-tools-version: 6.0` but pins `swiftLanguageVersions: [.v5]` to
  avoid Swift 6 strict-concurrency churn; the code is written for language mode 5.
- AppKit/Accessibility/AppleScript calls are `#if canImport(AppKit)`-guarded so `ActivityCore`
  still type-checks on non-macOS, but this is a macOS-only tool in practice.
- This is a surveillance-adjacent tool: keep the "machine is being monitored" notice in
  `track`, keep storage local, and don't add silent/background-hiding behavior or
  content capture.
