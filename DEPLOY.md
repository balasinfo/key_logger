# Deploying to your two Macs (2015 + 2019, both Intel)

Both laptops are Intel/x86_64 — same as the build machine — so there is no architecture issue.
You do **not** need Homebrew, Node, or any third-party package. Everything used (`swiftc`,
`sqlite3`, AppKit) ships with Apple's tools. Pick **one** of the two approaches below.

---

## Approach A — Build on each laptop (recommended, most reliable)

### 1. Install Xcode Command Line Tools (once per laptop)
```bash
xcode-select --install      # click "Install" in the popup; ~1.5 GB, free
```
This provides `swiftc`, `sqlite3`, and the macOS frameworks. (Full Xcode is **not** required.)

### 2. Copy the project folder to the laptop
Any of these works — pick what's easy:
- **AirDrop** the whole `key_logger` folder, or
- USB stick, or
- `scp -r key_logger user@other-mac.local:~/`

### 3. Build and verify
```bash
cd key_logger
./build.sh          # compiles to .build-direct/activitytracker
./test.sh           # optional: should print ALL PASS
```

### 4. Grant permissions (see "Permissions" below), then run.

---

## Approach B — Copy a prebuilt binary (no dev tools on the laptops)

### 1. Build a portable binary on any Intel Mac
`build.sh` already targets macOS 12 by default, so the binary runs on Monterey and later
(both your laptops qualify). Copy these two files together (they must stay side by side):
```
.build-direct/activitytracker
.build-direct/libActivityCore.dylib
```

### 2. Clear the quarantine flag on the target
Files moved via AirDrop/USB/download get quarantined and macOS will block them. On each laptop:
```bash
xattr -dr com.apple.quarantine /path/to/.build-direct
```
> If the laptop runs macOS older than 12 (Monterey), rebuild with a lower floor:
> `MACOS_MIN=11.0 ./build.sh`. macOS 10.14.4+ is required for the bundled Swift runtime.

### 3. Grant permissions, then run.

---

## Permissions (required on every laptop, both approaches)

The tracker reads window titles (Accessibility) and browser tab URLs (Automation). macOS gates
these per-machine. **The app that launches the binary** is what gets the permission:

1. Run it once from Terminal so the prompts appear:
   ```bash
   .build-direct/activitytracker once
   ```
2. **Accessibility** — System Settings ▸ Privacy & Security ▸ **Accessibility** ▸ enable
   **Terminal** (or iTerm). If you use the LaunchAgent below, enable the entry that appears for
   `activitytracker`/`run-tracker.sh` instead.
3. **Automation** — the first time it reads a browser you'll get a "Terminal wants to control
   Safari/Chrome" prompt; click **OK**. Check status anytime with:
   ```bash
   .build-direct/activitytracker permissions
   ```

---

## Email + run-at-login (do this on each laptop)

### 1. Put your Resend key in a locked-down file (not in any plist)
```bash
mkdir -p ~/.activitytracker
cp deploy/secrets.env.example ~/.activitytracker/secrets.env
# edit the file, paste your RESEND_API_KEY
chmod 600 ~/.activitytracker/secrets.env
```

### 2. Install the LaunchAgent (starts at login, restarts if it dies)
```bash
./deploy/install-agent.sh
```
It runs `deploy/run-tracker.sh`, which sources `secrets.env` and launches `track` (hourly email).
Logs go to `~/.activitytracker/agent.log`. To stop:
```bash
launchctl unload ~/Library/LaunchAgents/com.activitytracker.agent.plist
```

### Sending to the manabadi address
`onboarding@resend.dev` only delivers to the email that **owns the Resend account**. To email
`dharamarao.bala@manabadi.siliconandhra.org`, verify a domain in Resend and set `RESEND_FROM`
to an address on it (in `secrets.env`). See CLAUDE.md → "Email notifications".

---

## Quick checklist per laptop
- [ ] `xcode-select --install` (Approach A) **or** copied binary + `xattr -dr` (Approach B)
- [ ] `./build.sh` → `.build-direct/activitytracker` exists
- [ ] Accessibility + Automation granted (`activitytracker permissions` confirms)
- [ ] `~/.activitytracker/secrets.env` filled in and `chmod 600`
- [ ] `./deploy/install-agent.sh` loaded; `agent.log` shows tracking
- [ ] Got the first hourly email (or run `activitytracker notify` to test immediately)
