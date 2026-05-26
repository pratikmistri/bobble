# BobbleWin (WinUI 3 + C#)

`BobbleWin` is a Windows port of Bobble's architecture, organized 1:1 with the macOS app's core layers:

- `Models/` - session/message/provider state
- `ViewModels/` - `ChatHeadsManager`, `ChatSessionViewModel`, and `MainWindowViewModel`
- `Process/` - CLI process launching, stream parsing, and transport abstractions
- `Windows/` - panel sizing/coordination abstractions
- `Services/` - tray icon + provider/layout menu wiring
- `MainWindow.xaml` - chat-head list + expanded chat UI

## Build (on Windows)

1. Install Visual Studio 2022 (17.8+) with:
- .NET desktop development
- Windows App SDK / WinUI 3 workload

2. Open `BobbleWin/BobbleWin.sln`.
3. Select `x64` and run.

## Notes

- Session persistence is stored in `%APPDATA%/BobbleWin/session-history.json`.
- Each session gets its own workspace in `%APPDATA%/BobbleWin/ChatWorkspaces/<session-id>`.
- Chat head avatar images are copied from the macOS project into `Assets/HeadAvatars/`.
- Provider-specific transports are present as Windows-compatible wrappers over the CLI process transport, keeping API parity with the macOS transport interface.
