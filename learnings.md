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
