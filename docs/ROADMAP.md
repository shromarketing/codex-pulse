# Roadmap

## 0.1 — local MVP

- Native dashboard, menu bar, floating widget.
- Codex live read-only quota.
- Claude compatible local bridge and connection state.
- RU/EN, system/light/dark, three menu icon modes.
- Local deterministic task router and local history.
- Universal arm64 + x86_64 local package.

## 0.2 — local product build

- Adaptive Mini, Compact, Focus, and freely resizable widget.
- Usage intelligence by day, model, project, category, and estimated cost.
- Project/day task receipts without prompt content.
- Predictive pace, safe daily budget, threshold alerts, and public service status.
- Simple/Pro modes, six menu-bar presets, launch at login, and privacy controls.

## 0.3 — Codex UX hardening

- Rich Codex menu with quota windows, pace, usage, cost, models, projects, history, status, and quick actions.
- Separate Codex/Codex Spark windows and current ChatGPT plan from App Server.
- Connected-state cleanup: unavailable Claude hidden by default and never marked connected from public status alone.
- Reliable Compact/Focus widget expansion with screen bounds and no duplicate provider icon.
- Stronger build-task routing, localized dates/currency, and independent refresh caches.

### 0.3.1 — menu and widget hotfix

- Prevent the `MenuBarExtra` content area from collapsing to an empty strip.
- Verify live Overview/Usage content, charts, rankings, quick actions, and accessibility labels.
- Replace the stretched-widget empty canvas with responsive Focus/Expanded layouts and persistent Adaptive sizing.

### 0.3.2 — daily activity and history clarity

- Replace ambiguous Calendar/Task Receipts labels with Daily Activity and Usage History.
- Make every day selectable, expose tokens/cost/model/projects, and carry the selected date into history.
- Show only data-backed category filters, add counts and recovery-oriented empty states.
- Pre-group daily aggregates so the 90-day view remains responsive.

### 0.3.3 — instant analytics navigation

- Fetch one 90-day aggregate on the independent analytics refresh cadence.
- Derive 7/30/90-day totals, models, projects, account days, and receipts locally.
- Keep period and analytics-tab interactions free of provider refreshes and global loading indicators.

## 0.4 — hybrid task intelligence

- Explicit structured Codex AI analysis with immediate local fallback.
- Scale, risk, external-I/O, and verification guardrails.
- Confidence and task-shape labels.
- Multi-stage routes with different model/effort choices for planning, repeatable batches, and verification.
- Representative route evals for simple edits, builds, architecture, writing, and large web automation.

### 0.4.1 — quota forecast clarity

- Name quota reset and predicted exhaustion as separate events on every primary surface.
- Expose the pace forecast directly under the relevant quota instead of showing an unexplained duration.
- Add a refresh control to every floating-widget size and keep warning copy readable at the minimum Focus width.
- Cover timing copy and injected-clock pace calculations with Swift Testing.

### 0.4.2 — compact reset and explicit refresh

- Keep the weekly reset visible in Compact without hiding the pace forecast.
- Replace the menu popover's icon-only refresh with a labeled action, busy state, and Command-R shortcut.
- Keep quota refresh separate from application updates.

### 0.4.3 — compact height hardening

- Reserve a tested 360 × 138 pt preset for the four-row Compact layout.
- Normalize obsolete flattened saved frames to the Compact preset.
- Fall back to Mini below the content-driven height threshold instead of clipping the forecast.

### 0.4.4 — informative wide Compact

- Correct the overly aggressive 0.4.3 breakpoint that turned the existing 490 × 108 pt frame into Mini.
- Fit all four Compact rows through tighter vertical rhythm.
- Keep Mini only below a tested 100 pt content height.

### 0.4.5 — narrower Compact and scrollable detail

- Reduce the default Compact footprint from 360 × 138 pt to 320 × 138 pt without removing reset or forecast copy.
- Keep Focus/Expanded controls visible while the detail stack scrolls vertically.
- Preserve the usage chart, top model, and top project at shorter expanded heights instead of conditionally hiding them.

### 0.4.6–0.4.8 — one desktop control group

- Remove the duplicate native macOS traffic-light buttons from the floating panel.
- Keep refresh, expand/collapse, and close visible inside the widget at the top right.
- Retain accessible labels and working native resize/close behavior through the custom controls.

### 0.4.9 — full-width pace surface

- Make the shared pace/status card fill the Focus and Expanded content column.
- Preserve left-aligned copy, semantic health color, scrolling, and the existing card hierarchy.
- Verify the correction in the live signed universal application, not only in source or preview.

### 0.4.10 — smaller default Compact

- Reduce the default Compact preset from 320 × 138 pt to 260 × 138 pt without removing percentage, reset, pace, forecast, or controls.
- Migrate only the legacy 320/360 pt default frames; preserve genuine manual Adaptive sizes.
- Cover preset and migration geometry with Swift Testing and verify the live window at exactly 260 × 138.

## 0.5 — public beta readiness

- Bundled Claude Web Pulse Connector with opt-in loopback pairing and explicit disconnected states.
- Separate quota-and-pace intelligence from exact token/cost analytics; retain every Codex and Claude quota window locally for 7/30/90-day charts and reset history.
- Onboarding and source diagnostics.
- Unsigned public-preview ZIP/DMG, checksums, local source build, and AI-agent installation route without `sudo` or Gatekeeper changes.
- Complete keyboard and VoiceOver audit.
- Provider contract tests with sanitized fixtures.
- CSV/JSON export and configurable project category rules.

## 1.0

- Stable Codex + Claude integrations.
- Optional provider plugin SDK.
- Exportable usage reports without prompt content.
- Developer ID signing, notarization, Sparkle updates and a Homebrew cask proposal when release credentials are available.
