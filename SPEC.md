# AeroStage – Specification

Status: **1.0**, phases 0–4 complete

AeroStage is a native macOS companion app for the tiling window manager
[AeroSpace](https://github.com/nikitabobko/AeroSpace). It recreates the strip of the macOS
Stage Manager: every AeroSpace workspace appears as a "stage" with window thumbnails at the
edge of the screen. It is driven primarily by keyboard through AeroSpace; the mouse works
just as well.

---

## 1. Principles

- **Separate app on a thin fork.** AeroStage stays a separate app and talks to the window
  manager only through its CLI. Since v0.9 the window manager is **AeroStage WM**, a thin
  fork of AeroSpace (see 17); plain AeroSpace still works with fallbacks.
- **Stay close to AeroSpace.** AeroSpace's default shortcuts and behavior are kept. If
  AeroStage is not running, AeroSpace keeps working normally.
- **No polling of AeroSpace.** Updates come from the `aerospace subscribe` event stream. The
  only periodic check is a local window-server query every 0.5 s for the visible
  stage's windows (see 16), because AeroSpace reports no event for minimized windows.
- **Open source** on GitHub under the MIT license, distributed through a Homebrew tap.

## 2. Terms

| Term | Meaning |
|---|---|
| Stage | A non-empty AeroSpace workspace, shown as a card in the sidebar |
| Position | Number shown for a stage (1, 2, 3 …), gapless and ascending |
| Internal name | The real AeroSpace workspace name (also a number, e.g. `3`) |
| Sidebar monitor | The monitor the sidebar is currently shown on |

## 3. Features

### 3.1 Display modes

1. **Reserved:** the sidebar is always visible. AeroSpace reserves its space via
   `gaps.outer.left` or `gaps.outer.right`, on the sidebar monitor only. Windows never
   cover the sidebar.
2. **Overlay (target mode, like Stage Manager):** the sidebar is hidden and no gaps are
   reserved.
   - Shown when the mouse touches the screen edge (invisible 1–2 px strip) or via shortcut
     (`aerostage toggle`).
   - The sidebar floats above the windows.
   - Hidden when the mouse leaves it, after clicking a card or thumbnail, or via shortcut.

Side: left or right, **right by default**.

### 3.2 Monitor priority list

- The settings contain an ordered list of monitors, e.g. `DELL U4025QW → Built-in Display`.
- The sidebar appears on the highest-ranked connected monitor of the list, never on any
  other monitor (e.g. a TV).
- It shows the stages that live on the sidebar monitor. With only the built-in display
  connected, that is every stage.
- Monitors are detected automatically.
- When monitors are connected or disconnected, the sidebar follows. In reserved mode the
  gaps are rewritten.
- Workspaces are never lost in the process.

### 3.3 Cards

- One card per stage, in a fixed order by position (1 at the top).
- Each card has a header with the position and the app names, e.g. **"1.** Firefox, Mail, Code".
- Three views, switchable:
  - **Stacked Thumbnails (default):** up to 3 window thumbnails stacked like in Stage
    Manager, the layers behind offset towards the screen center and upwards; "+n" for
    more windows. The most recently focused window is in front.
  - **Thumbnails in Layout:** the windows of the stage to scale at their actual position,
    like a miniature screen.
  - **App Icons:** app icons of the windows in a grid.
- The active stage is highlighted.
- Background color and opacity (default black at 30 %), optional blur; title color
  (default white, with a soft shadow) and size (default 14 pt, the number 3 pt larger).
- Tooltip on hover: app name and window title.
- Width in **% of the monitor width**, clamped by minimum and maximum in points, so it fits
  on a 5K ultrawide as well as on a laptop display.

### 3.4 Interaction

| Action | Effect |
|---|---|
| Click a card | Switch to that stage |
| Click a thumbnail/icon | Focus exactly that window (`aerospace focus --window-id`) |
| Drag a thumbnail onto another card | Move the window to that stage |
| Drag a thumbnail onto the "+" area | New stage with that window |
| Right-click a card | Close stage (all windows), switch to stage |
| Right-click a thumbnail | Bring window to the current stage, close window |

The panel never takes keyboard focus (non-activating `NSPanel`) and is visible on all Spaces.

### 3.5 Numbering

Setting **"Numbering"**:

- **Dynamic (default, Stage Manager behavior):**
  - The position is shown, not the name.
  - When a stage becomes empty it disappears and the following ones move up (1, 3 → 1, 2).
  - New stages are appended at the end.
  - AeroStage picks the internal name automatically: the lowest free number. The user
    never sees it.
  - AeroStage remembers the order itself; after a restart it is sorted by name.
- **Fixed (classic AeroSpace):**
  - The real name is shown.
  - Gaps remain (1, 3).
  - Shortcuts go straight to AeroSpace.

Internal names are deliberately numbers, so AeroSpace keeps working sensibly without
AeroStage.

Maximum number of stages: computed per sidebar monitor (see 15), between 3 and 9.

### 3.6 Keyboard

Based on AeroSpace's default config (focus, move, layouts, resize, service mode). All of it
lives in managed sections and uses one modifier, chosen by preset:

- **US:** `alt`, exactly like AeroSpace.
- **International:** `ctrl-alt`, because on many European layouts `alt`+key types
  characters (German: `@`, `[`, `]`, `{`, `}`, `|`, `~`).
- **Custom:** `cmd-alt`, `ctrl-alt-cmd`.

On first launch the preset is derived from the current keyboard layout (US/ABC/Dvorak/
Colemak → US, everything else → International). Added or replaced (shown for `ctrl-alt`):

| Shortcut | Command | Effect |
|---|---|---|
| `ctrl-alt-1` … `9` | `aerostage focus N` | Switch to position N |
| `ctrl-alt-shift-1` … `9` | `aerostage move N` | Move the focused window to position N (N = count+1 → new stage) |
| `ctrl-alt-n` | `aerostage new` | Move the focused window to a new stage and follow it |
| `alt-tab` | `aerostage next` | Next stage (wraps around) |
| `alt-shift-tab` | `aerostage prev` | Previous stage |
| `ctrl-alt-s` | `aerostage toggle` | Show/hide the sidebar |

In fixed mode AeroStage writes the plain AeroSpace commands instead (`workspace N`,
`move-node-to-workspace N`).

### 3.7 Settings

A settings window with four tabs, reachable via `aerostage settings` and the sidebar's
context menu:

- **General:** launch AeroStage at login (`SMAppService.mainApp`), start AeroSpace at login
  (sets `start-at-login` in the AeroSpace config), mode (reserved/overlay, edge trigger,
  delay), side and width, monitor priority list, numbering (dynamic/fixed)
- **Appearance:** view, thumbnail refresh interval, Screen Recording status, icon size,
  background color/opacity/blur, title color and size
- **Keyboard:** preset (US / International / Custom), modifier for custom, detected layout
- **AeroSpace:** managed config on/off, gaps, path to the CLI, status

Stored in `UserDefaults` (`io.github.tech-maou.AeroStage`).

## 4. Architecture

```
                ┌──────────────────────── AeroStage.app ─────────────────────────┐
aerospace       │  EventStream ──► StateStore ──────────────────► SwiftUI views  │
subscribe ─────►│  (JSON lines)    (stages, windows, order,       (SidebarView)  │
                │                   active stage, monitor)              ▲         │
aerospace ◄─────│  AeroSpaceClient ◄─┘                                  │         │
list-* / focus  │  (CLI calls)          ThumbnailService ───────────────┘         │
                │                       (ScreenCaptureKit, images + positions)    │
NSWorkspace ───►│  AppDelegate: app terminated, screens changed → refresh        │
NSScreen   ────►│  MonitorResolver ──► SidebarController (NSPanel)               │
                │  ConfigManager ──► ~/.aerospace.toml (managed sections)        │
aerostage CLI ─►│  CommandServer (Unix socket) ──► StageCommands                 │
                └─────────────────────────────────────────────────────────────────┘
```

| Component | Responsibility |
|---|---|
| `AeroSpaceClient` | Runs `aerospace` commands (`list-windows --all --json`, `list-monitors --json`, `list-workspaces --json`, `focus`, `workspace`, `move-node-to-workspace`, `reload-config`) and decodes the JSON |
| `EventStream` | Keeps `aerospace subscribe --all` running as a child process, restarts it if it exits |
| `StateStore` | Single source of truth: stages, windows, order, active stage, sidebar monitor. Refreshes via the CLI after events (debounced) |
| `ThumbnailService` | Captures the sidebar's windows via ScreenCaptureKit, active stage first, then on an interval. Remembers the last visible position of every window for the layout view |
| `MonitorResolver` | Picks the sidebar monitor from the priority list and maps it to the AeroSpace monitor |
| `SidebarController` | Non-activating `NSPanel`, positioning, show/hide |
| `ConfigManager` | Writes gaps and shortcuts into the marked sections of `~/.aerospace.toml`, then runs `aerospace reload-config` |
| `CommandServer` / `StageCommands` | Unix domain socket; receives commands from the CLI and translates positions into workspace names |
| `aerostage` (CLI) | Tiny binary for shortcuts: `focus N`, `move N`, `new`, `next`, `prev`, `toggle`, `settings`, `reload`, `status`, `quit`. Falls back to plain `aerospace` commands when the app is not running |

## 5. Project layout

Swift Package Manager, builds with `swift build`, no Xcode project required. Swift 6,
targets macOS 14+ (for `SCScreenshotManager`).

```
AeroStage/
├── Package.swift
├── Sources/
│   ├── AeroStageCore/        # models, JSON types, IPC, stage order, managed config, template
│   ├── AeroStageApp/         # app: panel, views, client, event stream, state, settings
│   └── aerostage/            # CLI
├── Tests/AeroStageCoreTests/ # Swift Testing
├── Resources/Info.plist      # LSUIElement, bundle ID io.github.tech-maou.AeroStage
├── Prototypes/ThumbnailProbe # phase 0 prototype for ScreenCaptureKit
├── scripts/
│   ├── test.sh               # swift test, also without Xcode (Command Line Tools only)
│   ├── bundle.sh             # builds build/AeroStage.app and signs it
│   ├── install.sh            # bundle.sh + install to /Applications + restart
│   └── release.sh            # (phase 4) zip + SHA256 for GitHub release / cask
├── LICENSE                   # MIT
├── THIRD-PARTY-NOTICES.md
└── README.md
```

The app binary is called `AeroStageApp` in the package because `AeroStage` and `aerostage`
collide on case-insensitive APFS. In the bundle the app lives at `Contents/MacOS/AeroStage`
and the CLI at `Contents/Helpers/aerostage`.

## 6. Permissions & signing

- **Screen Recording:** required for thumbnails. Without it the sidebar falls back to icons.
- **Accessibility:** not required for AeroStage (only AeroSpace itself needs it).
- **Signing:** no paid Apple developer account.
  - Local builds are signed with a stable self-signed certificate so the Screen Recording
    permission survives rebuilds.
  - Releases are signed ad-hoc; users may have to grant the permission again after updates.
- **Launch at login:** `SMAppService.mainApp` (phase 4).

## 7. Distribution

- GitHub repo `Tech-Maou/AeroStage`, MIT license.
- The README names AeroSpace as a requirement and links to it.
- GitHub releases with a `.zip`.
- Homebrew tap `Tech-Maou/homebrew-tap` with a cask:
  - modeled after `nikitabobko/tap/aerospace`
  - `depends_on cask: "nikitabobko/tap/aerospace"`
  - removes the quarantine attribute

## 8. Phases

| Phase | Scope | Result |
|---|---|---|
| **0 – Setup** ✅ | Install and configure AeroSpace, toolchain, repo. **Prototype checks:** thumbnails of hidden windows, monitor disconnect, `subscribe` events | Running AeroSpace, risks cleared |
| **1 – Core** ✅ | Panel (reserved mode), cards with icons, clicks, `subscribe`, priority list, dynamic numbering, CLI and socket, managed config | Sidebar usable day to day |
| **2 – Thumbnails** ✅ | ScreenCaptureKit, cache, stacked view, layout view, view switcher | Stage Manager look |
| **3 – Overlay & mouse** ✅ | Overlay mode with edge trigger, drag & drop, "+" area, context menus | Target mode |
| **4 – Polish & release** ✅ | Complete settings, launch at login, app icon, release script, Homebrew tap | Public release 1.0 |

Each phase starts with a short alignment.

## 9. Findings phase 0 (AeroSpace 0.21.3, macOS 26)

- **`aerospace subscribe --all`** sends the current state on connect, then
  `focus-changed`, `focused-workspace-changed`, `focused-monitor-changed`,
  `window-detected`, `mode-changed`, `binding-triggered` as JSON lines.
  - There is no event for "window closed" or "window moved"; both only show up through
    the following `focus-changed`.
  - → `StateStore` refreshes via `list-windows --all --json` after every event (debounced)
    and additionally when an app terminates (`NSWorkspace`).
- **Empty workspaces** disappear after leaving them (with `persistent-workspaces = []`).
  This happens with a slight delay, so the window list is the source of truth.
- **Activating** an app on another workspace via AppleScript/`open` makes AeroSpace jump
  there. If that workspace becomes empty when the app quits, you stay on it.
- **Hidden windows** are moved to the bottom-right corner by AeroSpace (e.g. origin
  2559,1048) and still count as `onScreen` for macOS.
- **ScreenCaptureKit captures hidden windows live:** full size, about 65–80 ms per window
  at 2× resolution; content still current after 60 s hidden (tested with a terminal clock).
- **Prerequisite:** `NSApplication.shared` must be initialized before capturing, otherwise
  it crashes (`CGS_REQUIRE_INIT`). The real app does this anyway.
- **Signing:** ad-hoc signed rebuilds lose the Screen Recording permission. Removing and
  re-adding it did not help, only `tccutil reset ScreenCapture <bundle-id>` plus a new
  prompt. → A stable self-signed code signing certificate for development.

## 10. Findings phase 2 (v0.2)

- `ThumbnailService` captures the sidebar's windows via `SCScreenshotManager` at 2.5× the
  sidebar width: active stage first, again 0.4 s after the window list changes (AeroSpace
  re-lays out windows), then live at the configured interval (default 3 s, "only on
  changes" possible). Capturing only runs while the sidebar is visible and a thumbnail
  view is selected.
- Videos in browsers on hidden stages keep updating in the thumbnails.
- Cards observe the thumbnail service directly; otherwise SwiftUI would not redraw them
  when only the images change.
- The layout view uses each window's last position while it was visible; AeroSpace parks
  hidden windows off screen. Windows never seen visible are laid out side by side.
- Without permission the sidebar falls back to icons and retries every 10 s.
- **Permission and signing:** with the "AeroStage Dev" certificate the permission survives
  rebuilds (verified with a changed CDHash). After changing the bundle ID at the same path
  there were duplicate TCC entries; `tccutil reset ScreenCapture
  io.github.tech-maou.AeroStage` plus a new prompt fixed it.
- **Minimum window widths:** some apps cannot shrink below ~600 pt (e.g. Firefox). With four
  windows next to a reserved sidebar on a 2560 pt wide screen AeroSpace assigns ~581 pt
  each, so those windows overlap their neighbor slightly. Overlay mode (phase 3) frees the
  reserved space.

## 11. Phase 3 (v0.4)

- **Overlay is the default mode.** No gaps are reserved; a global plus a local mouse monitor
  (no extra permission needed) watch for the cursor at the outer edge of the sidebar monitor.
  After the reveal delay (default 100 ms) the panel slides in (160 ms), and it hides 300 ms
  after the mouse left it (with a 20 pt margin), never while a mouse button is held (drag).
- `aerostage toggle` in overlay mode shows the sidebar until it is toggled again, a stage or
  window is chosen, a workspace change happens, or the mouse visits and leaves it. In
  reserved mode it switches the sidebar off and on as before.
- While the overlay is hidden, thumbnails are only captured on changes; showing it triggers
  an immediate capture and resumes the live interval.
- Drag & drop uses the window ID as a string payload: drop on a card →
  `move-node-to-workspace`, drop on "New Stage" → the next free stage name. Clicking "New
  Stage" opens an empty stage.
- Context menus: window → focus, move to current stage, move to new stage, close
  (`aerospace close --window-id`); card → switch, close stage (all windows; apps still ask
  about unsaved changes).

## 12. v0.5

- Windows moved via the sidebar (drag & drop, context menu) are tiled afterwards with
  `layout tiling --window-id`, so the target stage splits like any other stage. Before, a
  window AeroSpace had made floating covered the tiled ones. The window context menu can
  toggle floating/tiling.
- Appearance settings (colors, opacity, blur, title size), settings grouped in tabs, the
  stage maximum is fixed at 5.

## 13. v0.6: dragging real windows onto the sidebar

- `WindowDragTracker`: a global mouse-down monitor remembers the window under the cursor
  (CG window list, AeroSpace-managed windows only). While the button is held, a 30 Hz timer
  polls the cursor, because other apps' window drags are not reliably delivered as drag
  events. Only a window that actually moves (> 6 pt) counts as a drag.
- In overlay mode the sidebar slides out as soon as the cursor is within 6 pt of the edge.
  The card or "New Stage" under the cursor is highlighted (hit test by height, including the
  margin up to the screen edge). On release over a target, the window is moved and tiled
  150 ms later, after AeroSpace has handled the mouse-up itself.
- Drop targets report their frames via a SwiftUI preference. A hidden overlay therefore stays
  on screen transparent and click-through (alpha 0, `ignoresMouseEvents`) instead of being
  ordered out, so SwiftUI keeps the card frames current.
- Layout view: AeroSpace only re-lays out a stage when it becomes visible. If the remembered
  positions of a stage are missing or overlap, its windows are drawn evenly side by side.

## 14. v0.7

- Launch at login for AeroStage via `SMAppService.mainApp`; if macOS asks for approval, the
  settings link to Login Items. "Start AeroSpace at login" only rewrites the
  `start-at-login` line of the AeroSpace config and reloads it.
- After a restart AeroSpace starts with empty workspaces and puts all windows on one; stages
  are deliberately not restored (same behavior as AeroSpace).
- Larger icons: 44 pt in the icon grid, 36 pt badges on stacked thumbnails, 22 pt in the
  layout view, all scaled by the "Icon size" setting (60–160 %).
- Settings use their own left-aligned tab bar.
- The overlay stays open while one of its context menus (or a submenu) is open, tracked via
  `NSMenu` begin/end tracking notifications; afterwards the mouse position decides again.
  While a menu is open, new thumbnails are held back: publishing them redraws the sidebar,
  and SwiftUI then rebuilds the open menu, which closed submenus like "View".

## 15. v0.8: stage limit per monitor

- `CardMetrics` mirrors the card layout (header from the title size, paddings, preview
  height per view: stacked `width / 1.25`, layout `width / canvas aspect`, icons two rows).
- The stage limit is the number of cards that fit when previews shrink to 70 % of their
  natural height, clamped to 3…9 (`StageCapacity`, shortcuts only go to `mod-9`). It is
  recomputed when the monitor, sidebar width, view, title or icon size change; the managed
  shortcuts follow (`mod-1` … `mod-<max>`).
- The sidebar always gives every card the same preview height: natural when there is room,
  smaller when there are many stages. The icon view does not shrink.
- On a 2560×1080 pt display with a 179 pt sidebar: 9 in layout view (measured), 7 stacked and
  7 icons (calculated).
- More open stages than the limit (e.g. after switching to a smaller display) are kept;
  only new stages cannot be added until there is room again.

## 16. Leaving an emptied stage

- Minimized windows disappear from `aerospace list-windows`, so closing and minimizing look
  the same: the visible stage had windows before a refresh and has none after it.
- AeroStage then switches to the stage above (by the previous order), or to the next one if
  it was the first.
- Closing an app's last window makes macOS activate another app about a second later, and
  AeroSpace follows it to that app's stage. AeroStage therefore holds the chosen stage for
  2 s and switches back if AeroSpace jumps away; a shortcut (`binding-triggered`), a click in
  the sidebar or a CLI command ends the hold immediately.
- If the last window was moved to another stage and focus followed it (`mod-n`), nothing
  happens; if focus stayed on the empty stage, the rule applies as well.
- Verified with a terminal window on stage 5 of 5: closing and minimizing both end on stage 4.
- Minimizing sends no AeroSpace event at all, and closing often only shows up with the next
  focus change (e.g. Thunderbird minimized: nothing happened until the next click). Since
  v0.8.4 `StateStore` checks every 0.5 s (v0.8.5; 1 s before) via `CGWindowListCopyWindowInfo`
  whether the visible stage's windows are still on screen and refreshes when that set
  changes. It runs locally without calling AeroSpace; one query takes about 0.6 ms, so the
  check costs about 0.1 % of one CPU core. Reaction time is about 0.5 s.

- The layout view's canvas is the full monitor in overlay mode and the monitor minus the
  sidebar only in reserved mode (v0.8.3); before, windows of the visible stage spilled out
  of their card in overlay mode. The preview is also clipped to its card.

## 17. AeroStage WM (decision 2026-10-26)

- **Why:** AeroSpace's `subscribe` lacks events for closed, minimized and moved windows and for
  emptied workspaces. A `window-closed` event was declined upstream (PR #2199, screen lock makes
  all windows briefly "die"), and similar PRs (#2116, #2162, #2181) were closed without review.
  Feature ideas go through Discussions; in a sample of 35 recent ideas the maintainer replied
  to 20 %, none visibly became an issue.
- **What:** a thin fork, `Tech-Maou/AeroStage-WM`, based on an AeroSpace release tag, with
  few atomic commits: rename (app name, bundle ID `io.github.tech-maou.AeroStageWM`, CLI
  `aerostage-wm`, internal paths), a bundle script for the Command Line Tools, README/LICENSE,
  then the extra `subscribe` events. Config file lookup stays AeroSpace's, as a drop-in
  replacement.
- **Updates:** a pull mirror of the original on a private Git server is the source;
  the fork's commits are rebased onto new AeroSpace release tags. Versions name the base,
  e.g. `v0.21.3-stage.1`.
- **Licenses:** AeroSpace's MIT license and copyright stay, with an added line for the
  modifications; `legal/third-party-license/` stays complete; AeroSpace's name, logo and icon
  are not used for the fork.
- **Hosting:** like AeroStage: `main` + `dev` on a private Git server, GitHub gets `main` via a push mirror. The
  GitHub repo is a normal repo, not a GitHub fork, so issues and PRs don't default to upstream.

## 18. v0.10: `workspace-windows-changed`

- AeroStage WM broadcasts `workspace-windows-changed` (`workspace`, `windowIds`) after each
  complete refresh session for every workspace whose set of windows changed, empty list
  when it became empty. Skipped while the screen is locked (`CGSSessionScreenIsLocked`),
  keeping the previous snapshot, so the lock's phantom closes and restores are not reported.
- Verified with a terminal window: open, move to another workspace (two events), minimize
  (workspace empty), unminimize, close: each produced the expected event within a refresh.
  Screen lock with a single stage: state unchanged after unlock.
- AeroStage itself skips refreshes while the screen is locked (v0.10.1). Otherwise any event
  during the lock would make it read the window manager's temporarily emptied model and
  leave the "emptied" stage behind the lock screen.
- AeroStage refreshes on the event like on any other and disables the 0.5 s window-server
  check when the CLI is `aerostage-wm`; with plain AeroSpace the check stays as fallback.
  `aerostage status` shows "(window events)" or "(fallback check)".

## 19. 1.0 release

- App icons for AeroStage and AeroStage WM drawn by `scripts/make-icons.swift` (no AeroSpace
  artwork); the bundle scripts turn them into `.icns` with `sips` and `iconutil`.
- `scripts/release.sh` in both repositories builds the zip for a GitHub release and updates
  the casks in `Tech-Maou/homebrew-tap` (`aerostage` depends on `aerostage-wm`, which conflicts
  with `nikitabobko/tap/aerospace`). Casks remove the quarantine attribute because the apps
  are not notarized.
- Versions: AeroStage 1.0.0, AeroStage WM 0.21.3-stage.1.

## 20. 1.1: menu bar and settings by app

- `MenuBarController`: template icon (sidebar outline) plus the visible stage's position;
  menu with stages, "AeroStage Settings …", "AeroStage WM Settings …" (or "AeroSpace
  Settings …"), View, Mode, Quit AeroStage / Quit AeroStage WM / Quit Both. Can be hidden;
  the sidebar's context menu keeps a Settings entry (menu bar items can disappear behind the
  notch).
- AeroStage WM 0.21.3-stage.2 hides its own menu bar item when its user default
  `hideMenuBarItem` is true (`MenuBarExtra(isInserted:)`), except without Accessibility
  permission. AeroStage writes that default.
- Settings window: `NavigationSplitView` with the groups AeroStage (General, Appearance, Menu
  Bar) and AeroStage WM (AeroSpace) (General, Keyboard, Gaps, Advanced). The second group is
  named "AeroSpace" when the original is used, because gaps and shortcuts still apply.
- Releases: 1.0.1 (fixes, current `dev`), 1.1.0 (this, branch `next`), 1.2.0 (window manager
  settings from the config: layout, behavior).

## 21. 1.2: window manager settings

- `ConfigManager.values` holds the raw values of the editable top-level keys
  (`default-root-container-layout`, `default-root-container-orientation`, `accordion-padding`,
  both normalization flags, `focus-follows-mouse.enabled`, `on-focused-monitor-changed`,
  `automatically-unhide-macos-hidden-apps`, `key-mapping.preset`, `auto-reload-config`).
- A change replaces only that line (`ManagedConfig.settingRaw`, keeps comments, ignores
  keys inside tables), backs up the file once and runs `reload-config`. Keys missing from
  the file disable their control instead of being added.
- New sections: Layout and Behavior; Keyboard gains key positions, Advanced the auto reload.

## 22. 1.3: updates

- `UpdateChecker`: 30 s after launch and then hourly, if the last check is 24 h old and
  "Check for updates automatically" is on, requests
  `api.github.com/repos/Tech-Maou/{AeroStage,AeroStage-WM}/releases/latest` and compares
  `tag_name` with the installed `CFBundleShortVersionString` (`ReleaseVersion`: numbers in
  order, so `0.21.3-stage.10` > `0.21.3-stage.2`). AeroStage WM is skipped when it is not
  installed (original AeroSpace).
- Found updates: one notification per new version, a dot in the menu bar glyph, "Update
  Available …" at the top of the menu, status in Settings → Versions & Updates. No manual
  check in the menu (the automatic one is enough); `aerostage update` shows the update window,
  also when everything is up to date.
- Settings → Versions & Updates: a section outside both groups, pinned below the sidebar
  list (`safeAreaInset`, a second `List` bound to the same selection so it is highlighted
  like the rows above). Installed versions of both apps; per outdated app "Update to
  Version x.y.z" (Homebrew) or "Download Version x.y.z" (release page). "Check Now" there
  only refreshes the status, it opens no window.
- Update window: release notes per app, **Update Now** when every outdated app has a folder
  in Homebrew's Caskroom, otherwise **Open Release Page**.
- Update Now: `enable off` and quit AeroStage WM (only if it is updated and running), start a
  detached `/bin/sh` script, quit AeroStage. The script waits for AeroStage to exit (so brew
  neither finds it running nor runs inside it), runs `brew update` and
  `brew upgrade --cask …`, writes the exit code to `~/Library/Logs/AeroStage/update-status`
  and reopens both apps. A non-zero code is reported on the next launch.
- Casks: `uninstall quit:` for both apps. On `brew upgrade` Homebrew quits the running app
  (AeroStage WM then returns its windows to the screen) and reopens it afterwards.

- AeroSpace next to AeroStage WM (`AeroSpaceConflict`): both read `~/.aerospace.toml` and
  register themselves as login items. While both run (`bobko.aerospace` and the fork), an
  alert offers "Quit AeroSpace" (its own `aerospace enable off`, then terminate; the original
  does not clean up on terminate), the menu starts with "AeroSpace Is Running Too – Quit
  AeroSpace", and Versions & Updates shows the same. The AeroSpace version is listed while it
  is installed. With the `aerospace` cask installed, Homebrew refuses to upgrade
  `aerostage-wm` (`conflicts_with`), so that update is disabled and the settings and update
  window show `brew uninstall --cask aerospace` with a copy button; "Update Now" installs the
  other updates only.

## 23. Open

1. How exactly does AeroSpace redistribute workspaces when the external monitor is
   disconnected or reconnected? `workspace-to-monitor-force-assignment` may be needed.
   Test postponed. Decided: with the laptop open and the external monitor connected, the
   sidebar stays on the external monitor, per the priority list.
2. TOML allows each table only once (`[gaps]`, `[mode.main.binding]`). That is why
   AeroStage creates `.aerospace.toml` from its template on first launch and manages the
   affected parts between markers (`gaps`, `bindings`, `stages`). The user's own additions
   outside the markers are kept. Configs without the `bindings` section (created before
   v0.3) keep working; the modifier then only applies to the stage shortcuts.
