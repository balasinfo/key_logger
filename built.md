Short answer

No third-party software needed — no Homebrew, Node, or packages. Everything uses Apple's own tools. Both your laptops are Intel, same as where this was built, so there's no        
architecture problem. You only need to decide between two approaches:

Approach A — build on each laptop (recommended)

The most reliable. On each Mac:                                                                                                                                                     
xcode-select --install     # one-time, free, ~1.5 GB (Command Line Tools, NOT full Xcode)
# AirDrop/USB/scp the key_logger folder over, then:
cd key_logger && ./build.sh

Approach B — copy a prebuilt binary (no dev tools on the laptops)

Build once, copy .build-direct/activitytracker and libActivityCore.dylib together, then clear the download/AirDrop quarantine flag on the target:                                   
xattr -dr com.apple.quarantine /path/to/.build-direct

The one thing that would have bitten you

The binary I built first reported minos 26.0 — it would not have launched on your 2015/2019 Macs (they top out around macOS 12 Monterey). I fixed build.sh to target macOS 12 by    
default, so any binary it produces now runs on both. Verified: minos 12.0, and it still runs fine here.

Permissions (required on every laptop — this is the real "make it work" step)

macOS gates the two capabilities per-machine. After copying/building, run activitytracker once, then:
- Accessibility (window titles) → System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable Terminal (or the agent)
- Automation (browser URLs) → click "OK" on the prompt the first time it reads a browser                                                                                            


Check with activitytracker permissions.

Files I added

- DEPLOY.md — full step-by-step for both approaches, permissions, and a per-laptop checklist.
- deploy/install-agent.sh — installs a LaunchAgent so track (with hourly email) starts at login and restarts if it dies. Logs to ~/.activitytracker/agent.log.
- deploy/run-tracker.sh + deploy/secrets.env.example — your Resend API key goes in ~/.activitytracker/secrets.env (chmod 600), kept out of the plist and the repo.

So per laptop it's: install CLT → copy folder → ./build.sh → grant 2 permissions → fill in secrets.env → ./deploy/install-agent.sh. The checklist at the bottom of DEPLOY.md walks  
through it.

One reminder carried over: to actually email the @manabadi.siliconandhra.org address, you'll need to verify a domain in Resend and set RESEND_FROM — the default                    
onboarding@resend.dev only delivers to your own Resend account email.

Want me to also add a report-style daily summary email (in addition to hourly), or a small uninstaller script for the agent?  
---
What changed

- track now sends two kinds of email when RESEND_API_KEY is set:
    - Hourly — trailing-hour summary (unchanged).
    - Daily — fires once when the local calendar day rolls over (just after midnight), summarizing the day that just ended. It won't double-fire or send a partial day on startup — it
      waits for a real day boundary.
- notify --daily — on-demand daily report for today so far (since local midnight), in addition to the existing notify --hours N.
- Both the daily email and notify --daily carry a dated label (e.g. "daily summary — Jun 16, 2026").

Implementation notes

- The daily logic rides the same Sampler.run(onTick:) hook as hourly — no new scheduling machinery. It tracks lastDailyDay via Calendar.startOfDay and, on rollover, pulls          
  store.samples(since: dayStart).filter { $0.timestamp < today } so the report is exactly the previous day.
- Since track runs continuously under the LaunchAgent, the daily email "just works" once it's running across midnight — no extra cron entry needed. (If you'd rather drive it from  
  cron/launchd instead, notify --daily is the one-shot entry point.)

Verified

- ./build.sh + ./test.sh → ALL PASS (20 checks).
- notify --daily send path reaches Resend and returns a correctly-parsed response (401 with a fake key, so the daily code path constructs and POSTs correctly).
- CLAUDE.md updated (email section + architecture note).

Nothing to redo on the laptops beyond rebuilding (./build.sh) and restarting the agent — the secrets.env and LaunchAgent setup are unchanged.                                       
                                                                                                                                                 