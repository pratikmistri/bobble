# Learnings

_Session log: what we did, what worked, what didn't._

---

## 2026-03-20

- Confirmed Bobble is a SwiftUI + AppKit menu bar app built around floating chat heads and an expandable floating chat panel.
- Confirmed the core flow is session-centric: `ChatHeadsManager` coordinates sessions/history/providers, `ChatSessionViewModel` owns per-chat interaction state, and `CLIProcessManager` + `StreamParser` bridge installed agent CLIs into the UI.
- Worked approach: keep project guidance in a root `agents.md` file and point agents to this cumulative log instead of scattering temporary notes.
- Rejected approach: writing a generic agent brief without reading the code first. The repo already has a concrete architecture and product direction, so the notes should reflect the actual app structure.
- Installed external Codex skill `swiftui-expert-skill` from `AvdLee/SwiftUI-Agent-Skill` into `/Users/pratikmistri/.codex/skills/swiftui-expert-skill`.
- Rejected approach: installer default download mode via Python `urllib` failed locally with an SSL certificate verification error; the supported installer still worked when retried with `--method git`.
- Worked approach: derive assistant-side attachments from markdown file links in `ChatSessionViewModel` so older and streaming agent responses can both surface inline previews without changing the CLI protocol.
- Worked approach: use text snippets for text-like files and Quick Look thumbnails for other documents inside `MessageBubbleView`; this gives previews for code, markdown, JSON, PDFs, and similar outputs while keeping image previews unchanged.
- Verification note: local builds required `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because `xcode-select` currently points at Command Line Tools.

## 2026-03-21

- Confirmed prompt execution is currently one process per turn: `ChatSessionViewModel.send()` creates a fresh `CLIProcessManager`, and Codex resumes context by reusing `cliSessionId` with `codex exec resume` rather than keeping a long-lived subprocess alive.
- Worked approach: for the current multi-provider design, structured CLI streaming (`codex exec --json`, Claude `--output-format stream-json`) is still the most practical integration surface because it preserves real tool activity/events and keeps each chat isolated to its workspace.
- Recommended next step: if latency becomes noticeable, improve efficiency around the existing process boundary first (persistent session IDs, lower UI update frequency, slimmer prompt wrapping, and backend-specific adapters) before attempting a custom long-lived PTY or direct API integration.
- Rejected approach: a single persistent shell/PTY for all prompts. It would be more fragile across Codex/Copilot/Claude, harder to parse reliably, and easier to desynchronize from Bobble's per-session workspace model.
- Worked approach: move the running-state feedback into the chat-head emoji itself in `ChatHeadView` with scale/tilt/offset animation, while leaving unread and error as corner badges so active heads feel alive without losing status clarity.
- Constraint discovered: SwiftUI's modern `onChange` here requires an `Equatable` value, so `ChatSession.SessionState` should be observed through a derived `Bool` like `isWorking` unless the enum is explicitly made `Equatable`.
- Worked approach: derive both the bobble animation and the corner badge from the same `HeadStatus` state in `ChatHeadView`; this prevents the emoji from continuing to wobble after the session transitions to the completed badge state.
