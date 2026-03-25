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
- Worked approach: keep the Ask/Bypass picker label text-only in the collapsed state. The extra leading icon added visual noise for a two-state control whose meaning is already explicit in the label text.
- Worked approach: store model selection as a provider-aware enum rather than a Codex-only type, but keep the persisted coding key as `selectedModel` so older sessions still decode cleanly. A single shared picker can then filter options by provider without introducing a separate settings store.
- Constraint discovered: persistent Claude and Copilot transports need to be torn down when the selected model changes, because their model is chosen at process startup rather than per turn. Resetting only the session ID is not enough for those providers.
- Worked approach: for SwiftUI `Menu` controls on macOS, hide the system menu indicator with `.menuIndicator(.hidden)` when using a custom capsule label that already includes its own trailing chevron; otherwise AppKit adds a second disclosure glyph before the label text.
- Worked approach: if the native macOS menu glyph should stay visible, remove the custom trailing chevron from the label instead of hiding the system indicator. That keeps a single disclosure cue and matches the platform convention more closely.
- Worked approach: switch the floating panel root from a bare `NSHostingView` to `NSHostingController` and defer panel frame mutations by one main-runloop turn. That reduces the chance of AppKit re-entering SwiftUI host layout while the panel is resizing or collapsing.
- Constraint discovered: repo-local verification still needs `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` even when `DEVELOPER_DIR` is set, otherwise local `xcodebuild` fails on the missing `Mac Development` certificate for team `MJWG2F9J23`.
- Rejected approach: keeping the floating panel on `NSHostingController` for all cases. With long chat transcripts, AppKit can start honoring the hosted SwiftUI fitting height, which surfaced as the `Update Constraints in Window` recursion warning and multi-thousand-point panel heights.
- Worked approach: keep the deferred frame mutations in `AppDelegate`, but host the panel root with `NSHostingView` and `sizingOptions = []` so the panel frame remains authoritative while SwiftUI still fills the window bounds.
- Constraint discovered: the collapsed chat-head stack was spacing rows off `headDiameter` (`50`), but each rendered `ChatHeadView` shell is actually `58` points tall. That effectively removed the intended inter-head gap even though the add/history buttons still used the standard `8` point row spacing.
- Worked approach: define a shared `headControlDiameter` token and use it for collapsed head offsets plus collapsed panel height math. That preserves the intended `8` point gap between every control in the collapsed column.
- Review finding: `ChatSessionViewModel.updateConversationMode(...)` updates the stored mode during a running turn, but unlike model changes it does not mark the cached provider transport for reset. Because the transport factory switches only on `session.provider`, the next turn can reuse a Copilot/Claude/Codex transport started with the previous execution mode.
- Review finding: provider changes from the menu bar remain live while a session is running. `ChatHeadsManager.setProvider(...)` mutates the session immediately and `ChatSessionViewModel.updateProvider(...)` resets the active transport, so switching providers mid-turn can interrupt the in-flight conversation instead of deferring the change.
- Review note: `ChatHeadView.previewContent` checks the last message before checking `session.state`. In practice the `running` branch rarely wins after the first turn, so the intended live "Working on your latest message..." preview is mostly hidden by stale content.
- Worked approach: repo-local verification succeeded with `xcodebuild -project Bobble.xcodeproj -scheme Bobble -configuration Debug -derivedDataPath /Users/pratikmistri/bobble/.derived-data-review CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`.

## 2026-03-23

- Worked approach: unify flyout styling through shared view primitives instead of maintaining separate one-off card layouts. `SessionFlyoutSurface` now provides the common panel chrome and `SessionFlyoutRowContent` provides the shared session row layout.
- Worked approach: migrate both the history popover and chat-head hover preview to those shared controls so typography, spacing, border treatment, and avatar row structure stay visually consistent.
- Worked approach: add `showsLeadingAvatar` to the shared flyout row so the hover preview can suppress its duplicate emoji while history rows keep the avatar.
- Constraint discovered: `RelativeDateTimeFormatter.localizedString(...)` is an instance method in this toolchain; use a cached formatter instance on `ChatSession` extensions for history trailing labels.
- Verification note: local build passed after the flyout refactor with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bobble.xcodeproj -scheme Bobble -configuration Debug -derivedDataPath /Users/pratikmistri/bobble/.derived-data-codex CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`.

## 2026-03-24

- Constraint discovered: rapid `Add` taps can queue repeated session expansions and drive the floating panel to pathological frame heights (multi-thousand points), which aligns with AppKit's `Update Constraints in Window` recursion exception on `FloatingPanel`.
- Worked approach: route `onAddSession` through a throttled AppDelegate handler (`0.2s` gate) and skip expand-state animation for newly added sessions to reduce re-entrant layout churn during burst input.
- Worked approach: clamp requested panel size to the current screen's constrained frame before resolving origin/anchor; this keeps panel frame math bounded even when active session count grows quickly.
- Verification note: local build passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bobble.xcodeproj -scheme Bobble -configuration Debug -derivedDataPath /Users/pratikmistri/bobble/.derived-data-fix CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build -quiet`.
- Worked approach: replaced emoji chat heads with bundled `Bobble1`...`Bobble9` image assets and rendered them through a shared `ChatHeadAvatarView` so stack heads, chat header avatars, and history rows all use the same visual source.
- Worked approach: moved the PNGs into `Resources/Assets.xcassets` image sets instead of loading from raw file paths, which keeps avatar lookups simple (`Image`/`NSImage` by asset name) and compile-time validated.
- Worked approach: assign each session a stable bobble image by hashing session ID (with optional support for explicit `BobbleN` values in persisted `chatHeadSymbol`), so old sessions remain deterministic without extra metadata migration.
- Rejected approach: keeping first-message emoji generation in `ChatSessionViewModel` after the UI switched to image avatars. It became dead work, so the helper process and related prompt plumbing were removed.
- Verification note: local build succeeded with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bobble.xcodeproj -scheme Bobble -configuration Debug -derivedDataPath /Users/pratikmistri/bobble/.derived-data-codex CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`.
- Worked approach: persist explicit bobble-head assignments separately from default per-session hashing by introducing `hasAssignedChatHeadSymbol` in `ChatSession`. Rendering now uses the stored `chatHeadSymbol` only when explicitly assigned, so manually assigned bobbles survive app relaunch while legacy unassigned chats keep deterministic ID-based avatars.
- Worked approach: normalized `InputBarView` outer insets by replacing split padding (`horizontal: 12`, `vertical: 8`) with uniform `.padding(12)`, which makes the chat input area spacing consistent on all sides in the expanded window.
- Worked approach: allocate chat-head images from a usage-count pool when creating new sessions (`ChatHeadsManager.addSession`) so bobbles do not repeat until all 9 image assets are in use, then rotate through the least-used image.
- Worked approach: migration on restore now assigns explicit bobble images to legacy sessions missing `hasAssignedChatHeadSymbol`, then immediately persists, so old data also follows the non-repeating allocation rule.
- Constraint discovered: current target `Release` signing is `Apple Development` and app sandbox is disabled in `Bobble.entitlements`, so packaging for public distribution should use Developer ID signing + notarization (direct download), not Mac App Store flow.
- Worked approach: added a dedicated `menubar.imageset` in `Resources/Assets.xcassets` backed by `menubar.svg` and switched `AppDelegate` status-item icon lookup to `NSImage(named: "menubar")`, with `isTemplate = true` so the icon automatically adapts to light/dark menu bar themes.
- Worked approach: kept a system-symbol fallback (`bubble.left.fill`) if the custom asset is unavailable, and normalized status bar icon size to `18x18` for consistent rendering.
- Verification note: local build passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bobble.xcodeproj -scheme Bobble -configuration Debug -derivedDataPath /Users/pratikmistri/bobble/.derived-data-menubar CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build -quiet`.

## 2026-03-25

- Worked approach: renamed the menu bar provider section label from `Provider` to `Agents` in `AppDelegate.makeStatusMenu()` to match product terminology in the UI.
- Worked approach: ignore all repo-local Xcode derived data directories with `.derived-data*/` in `.gitignore` so sandbox-friendly `xcodebuild -derivedDataPath` runs do not show up as untracked workspace noise.
