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
- Worked approach: persist a conversation-level execution mode on `ChatSession` with provider-aware defaults so older sessions can decode cleanly and new conversations start in the expected Ask/Bypass state without needing a separate settings store.
- Rejected approach: infer permission cards from raw text in the UI only. The better shape is to carry structured interruption metadata on `ChatMessage`, even if the transport layer is wired later.
- Worked approach: split provider execution behind a conversation transport boundary. Codex and Claude can stay on the existing one-shot process runner, while Copilot now gets a dedicated ACP stdio transport without forcing the rest of the app into the same lifecycle.
- Constraint discovered: local verification is reliable when `xcodebuild` writes DerivedData inside the repo (`-derivedDataPath /Users/pratikmistri/bobble/.derived-data`); the default user Library path is blocked in this sandboxed environment.
- Constraint discovered: the installed `codex exec` build supports full bypass directly, but approval-gated execution is not exposed as `codex exec --ask-for-approval ...`. For non-interactive runs, approval policy has to be passed through `-c approval_policy="..."` while sandbox level can still use `--sandbox`.
- Worked approach: Claude and Codex need provider-specific long-lived transports for real Ask-mode behavior. Claude's `-p --verbose --input-format stream-json --output-format stream-json --replay-user-messages` path supports interactive follow-up messages, while Codex's `app-server` exposes explicit JSON-RPC approval callbacks (`item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, and `item/tool/requestUserInput`).
- Rejected approach: trying to extend the one-shot `CLIConversationTransport` for Claude/Codex approvals. That wrapper can only show an interruption and stop the subprocess; it cannot continue a paused turn because `resolveInterruption(...)` has no live protocol behind it.
- Worked approach: when expanding a chat, use `ScrollViewReader` with an initial non-animated bottom jump keyed off the expanded session/message state, while keeping animated scroll only for new incoming messages. This avoids reopening a conversation mid-history.

## 2026-03-22

- Constraint discovered: Claude permission failures can arrive on the stream as `type: "user"` events carrying `tool_use_result`, not only as explicit `permission` or `question` event types. If the transport only keys off the event type, Bobble falls back to rendering raw JSON as a generic system message and never opens the reply-in-chat continuation path.
- Worked approach: extract interruption text from Claude `tool_use_result` payloads and route those `user` events through the same structured interruption path as other approval/question events. That keeps the turn interactive and surfaces readable permission details instead of the raw stream payload.
- Worked approach: keep interruption cards on a single left edge by stacking the status icon, title, body, and action buttons in one vertical column. A separate icon column looked misaligned once cards contained multiline body text and full-width buttons.
- Constraint discovered: Claude `-p` / `--output-format stream-json` does not actually pause inline for permission approval by itself. Without a dedicated `--permission-prompt-tool`, Claude treats denied permissions as tool failures and can continue with a fallback assistant explanation.
- Worked approach: always pass Claude `--add-dir <workspace>` so Bobble's per-chat workspace is pre-authorized, and fail closed on any remaining Claude permission interruption by suppressing later assistant output from that turn instead of pretending the turn can continue inline.
