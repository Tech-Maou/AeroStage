# Changelog

## 1.4.0

- **Reorder stages:** hold a stage card (outside its thumbnails and icons) for a tenth of a
  second, then drag it up or down. The card pops out with an accent border and a shadow while
  the others step back; they make room as you drag, and the stage gets its new number. The card's
  context menu has **Move Up** and **Move Down** as well. No window is moved, the stage
  shortcuts simply follow the new numbers.
- **Tooltips:** resting the mouse on a thumbnail or icon shows the app name and the window
  title (in a browser, the title of the current tab) in one line below it.
- The fixed AeroSpace numbering is gone; stages are always numbered by position without gaps,
  like Stage Manager. Whoever used it is switched over automatically.
- Fixed: in the stacked and layout views, hovering, clicking and dragging a thumbnail could
  hit the front window although another one was under the mouse; the thumbnails were only
  drawn at their place, their mouse area stayed in the corner.
- In reserved mode and when the window manager is not reachable, the texts name the window
  manager actually in use instead of always saying AeroSpace.
- Use it with AeroStage WM 0.21.3-stage.5: older versions quit after typing into a password
  field (macOS Secure Input), which put all windows on one stage until AeroStage brought them
  back after a restart.

## 1.3.3

- Fixed: after the window manager restarted (for example during an update), the sidebar could
  keep saying "AeroStage WM is not running". AeroStage now checks the process list every
  second and only reports a quit after 4 seconds, so updates and restarts show no warning.
- `aerostage status` shows whether the window manager is running.

## 1.3.2

- When the window manager quits (on purpose or not), the sidebar no longer shows the outdated
  stages. It says "AeroStage WM is not running" with a **Start AeroStage WM** button; the menu
  bar menu has the same entry, and a notification explains why all windows are on screen.
- Stages survive a window manager restart: AeroStage remembers which window was on which stage
  (and which floated). When AeroStage WM starts again, for example after a quit or an update,
  the windows go back to their stages and the visible stage is shown again. After a reboot the
  windows are new, so nothing is restored.
- Needs AeroStage WM 0.21.3-stage.4, whose menu no longer quits or disables it with ⌘Q or ⌘E.

## 1.3.1

- The window context menu shows the current state: **Tiling** and **Floating** with a checkmark
  instead of "Toggle Floating / Tiling".
- Floating windows carry a small neutral mark (two overlapping windows) in the top left corner
  of their thumbnail or icon; tiled windows, the default, have none.
- With AeroStage WM 0.21.3-stage.3 the state updates right away, also after a keyboard
  shortcut. With the original AeroSpace it updates when
  the sidebar appears.

## 1.3.0

- Update check: once a day AeroStage asks GitHub for new releases of AeroStage and
  AeroStage WM. A new version shows a notification, a dot on the menu bar icon and
  **Update Available** at the top of its menu.
- **Update Now** returns all windows to the screen, quits both apps, updates them with
  Homebrew and opens them again. Without Homebrew it opens the release page.
- Settings → **Versions & Updates**, pinned to the bottom of the sidebar: installed versions
  of AeroStage and AeroStage WM, **Update to Version x.y.z** per app, automatic check on/off,
  check now. On the command line: `aerostage update`.
- With the original AeroSpace still installed: a warning when both window managers run, with
  **Quit AeroSpace** (windows return to the screen first); the AeroSpace version in Versions &
  Updates; while its Homebrew cask is installed, the AeroStage WM update is disabled with the
  command to uninstall it, as Homebrew would refuse it.
- The Homebrew casks quit the apps before upgrading and reopen them afterwards, also when
  updating in the terminal.

## 1.2.0

- Window manager settings without editing the config file:
  - **Layout:** default layout and direction of new stages, accordion offset, normalization.
  - **Behavior:** focus follows the mouse, move the mouse along when focusing another
    monitor, show apps hidden with ⌘H again.
  - **Keyboard:** key positions (QWERTY, Dvorak, Colemak).
  - **Advanced:** reload the config automatically when the file is saved.
- With the original AeroSpace, the window manager settings show a permanent warning that full
  functionality needs AeroStage WM, with a link to it.
- The "New Stage" area uses the title color and a stronger dashed border, so it is easier to
  see on transparent backgrounds.
- Each change is written as a single line of `~/.aerospace.toml` and reloaded right away;
  everything else in the file stays as it is. App rules, custom modes and free shortcuts are
  still edited in the file ("Open in Editor").

## 1.1.0

- Menu bar item: a monochrome AeroStage icon with the number of the visible stage. Its menu
  lists the stages, opens the settings of AeroStage and of the window manager, switches view
  and mode, and quits AeroStage, AeroStage WM or both. Quitting AeroStage WM first returns all windows to the
  screen (`enable off`), so none stay parked in the screen corner. With AeroStage WM, its own menu bar
  item (which shows the internal workspace name) is hidden.
- Settings window with a sidebar: **AeroStage** (General, Appearance, Menu Bar) and
  **AeroStage WM (AeroSpace)** (General, Keyboard, Gaps, Advanced). With the original
  AeroSpace the second group is called "AeroSpace".

## 1.0.1

- The sidebar moves to the right position right away when monitors change, and after
  unlocking or waking the Mac; before, it could keep the previous monitor's position after
  docking until the next stage switch.
- Stage context menu: **Layout** → Side by Side, Accordion, Reset Layout. Useful after the
  window manager starts with more than three windows on one stage, which AeroSpace arranges
  as an accordion.
- Builds are signed with the long-lived "AeroStage Release" certificate, so macOS keeps the
  Screen Recording permission across updates (one more approval when updating from 1.0.0).

## 1.0.0

First public release.

- App icon, Homebrew cask (`brew install --cask tech-maou/tap/aerostage`), release script.
- Requires [AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM) for reliable updates;
  plain AeroSpace works with a fallback check.

## 0.10

- Uses AeroStage WM's `workspace-windows-changed` event: closed, minimized and moved windows
  and emptied stages are noticed immediately; the window-server check is only a fallback for
  plain AeroSpace.
- No refreshes while the screen is locked, so AeroStage never switches stages behind the
  lock screen.

## 0.9

- Prefers the `aerostage-wm` CLI of AeroStage WM, falls back to `aerospace`.

## 0.8

- The stage limit follows the sidebar monitor (3 to 9 stages, depending on height, width,
  view and sizes); previews shrink evenly when there are many stages.
- When the visible stage becomes empty (last window closed, minimized or moved away), the
  stage above it is shown.
- Layout previews stay inside their cards in overlay mode.

## 0.7

- Launch at login for AeroStage and the window manager.
- Larger icons and an Icon size setting; left-aligned settings tabs.
- The overlay stays open while a context menu or submenu is open.

## 0.6

- Drag a real window by its title bar onto a stage card or "New Stage".

## 0.5

- Windows moved via the sidebar are tiled; toggle floating/tiling from the context menu.
- Background color, opacity and blur, title color and size; settings in tabs.

## 0.4

- Overlay mode (default): the sidebar slides in at the screen edge.
- Drag & drop between stages, "New Stage" area, context menus.

## 0.3

- Keyboard presets: US (`alt`) and International (`ctrl-alt`); all AeroSpace default
  shortcuts follow the chosen modifier.

## 0.2

- Live window thumbnails via ScreenCaptureKit: stacked, layout and icon views.
- English user interface.

## 0.1

- Sidebar with one card per stage, dynamic numbering, monitor priority list, real-time
  updates via `subscribe`, managed sections in `~/.aerospace.toml`, `aerostage` CLI.
