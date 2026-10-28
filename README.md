# AeroStage

**A Stage Manager–style sidebar for [AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM),
a tiling window manager based on [AeroSpace](https://github.com/nikitabobko/AeroSpace).**

AeroStage shows every workspace as a "stage" in a slim sidebar at the edge of the screen, like
the strip of the macOS Stage Manager. You keep driving everything with the keyboard through
the window manager, but clicking a stage or a window works just as well.

> [!IMPORTANT]
> AeroStage only runs reliably with **[AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM)**,
> our fork of AeroSpace (see [Why AeroStage WM?](#why-aerostage-wm)). It still starts with the
> original AeroSpace, but closed, minimized and moved windows are then only noticed by a
> fallback check. `aerostage status` shows which mode is active.

> [!NOTE]
> AeroStage and AeroStage WM are **unofficial**. They are not part of AeroSpace and not
> maintained by its developers. Please report issues here, not in the AeroSpace project.

## Features

- Two modes:
  - **Overlay** (default): the sidebar slides in when the mouse touches the screen edge
    (or via shortcut), floats above your windows and hides again when the mouse leaves.
    Windows keep the full screen width.
  - **Reserved:** the sidebar is always visible and AeroSpace keeps its space free via
    gaps, on the sidebar's monitor only.
- Sidebar on the left or right.
- One card per stage with **live window thumbnails**, also for stages in the background.
  Three views:
  - **Stacked Thumbnails** like in Stage Manager, the most recently used window in front
  - **Thumbnails in Layout**: the windows to scale at their actual position
  - **App Icons**
- Each card has a header with its number and apps, e.g. **"1.** Firefox, Mail, Code". The
  active stage is highlighted.
- Click a card to switch stages, click a thumbnail or icon to focus exactly that window.
- **Drag & drop** a window onto another card to move it there, or onto **New Stage** to put
  it on a new stage. Clicking **New Stage** opens an empty one. Moved windows are tiled, so
  the target stage splits like any other.
- **Drag real windows:** grab a window by its title bar and drag it to the screen edge. The
  sidebar slides out, and dropping the window on a card or on **New Stage** moves it there.
- **Context menus:** right-click a window to focus it, move it to the current or a new stage,
  switch it between **Tiling** and **Floating** (the current state has a checkmark), or close
  it; right-click a card to switch to it, change its layout (side by side, accordion, reset)
  or close the whole stage.
- Floating windows carry a small neutral mark (two overlapping windows) in the top left
  corner of their thumbnail or icon.
- **Numbering** like Stage Manager: stages appear and disappear automatically and the numbers
  close up without gaps.
- **Reorder stages:** hold a card (outside its thumbnails) for a moment and drag it to a new
  place, or use **Move Up/Down** in its context menu. The shortcuts follow the new numbers.
- **Tooltips:** rest the mouse on a thumbnail or icon to see the app and the window title, for
  example the tab title in a browser.
- When the last window of the visible stage is closed, minimized or moved away, AeroStage
  shows the stage above it (or the next one if it was the first).
- **Monitor priority list:** the sidebar appears on your preferred connected monitor (e.g.
  the external display, otherwise the built-in one). Other monitors such as a TV stay free.
- Real-time updates via the window manager's `subscribe` event stream. With AeroStage WM
  closed, minimized and moved windows arrive as events (`workspace-windows-changed`); with
  plain AeroSpace a lightweight window-server check twice a second covers the visible stage.
- **Customizable look:** background color, opacity and optional blur, title color and size,
  icon size.
- **Stages survive a window manager restart:** AeroStage remembers which window is on which
  stage. When AeroStage WM starts again (after a quit, a crash or an update), the windows go
  back to their stages. If it is not running, the sidebar says so and offers to start it.
- **Launch at login** for AeroStage and the window manager, switchable in the settings.
- Menu bar icon with the number of the visible stage; its menu switches stages, opens the
  settings and quits AeroStage, AeroStage WM or both.
- Settings with a sidebar, grouped by app: AeroStage and AeroStage WM (AeroSpace), plus
  **Versions & Updates** at the bottom. The window manager's common options (layout,
  behavior, key positions) are regular settings; they are written into `~/.aerospace.toml`
  line by line.
- **Update check** once a day, installed with one click through Homebrew (see
  [Updates](#updates)).
- Warns when the original AeroSpace runs at the same time as AeroStage WM.
- No Dock icon, never steals keyboard focus.

Ideas are welcome as issues.

Details are in the [specification](SPEC.md).

## Requirements

- macOS 14 Sonoma or later
- [AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM) (recommended) or
  [AeroSpace](https://github.com/nikitabobko/AeroSpace) 0.21 or later, with Accessibility
  permission

## Installation

### Homebrew

```bash
brew install --cask tech-maou/tap/aerostage
```

This installs AeroStage and, as a dependency, AeroStage WM, and puts the `aerostage` and
`aerostage-wm` commands on your `PATH`. If the original AeroSpace is installed, remove it
first (see [Switching from AeroSpace](#switching-from-aerospace)). The apps are not notarized
by Apple because the project does not use a paid Apple developer account, so the casks remove
the quarantine attribute to let macOS launch them.

### Switching from AeroSpace

AeroStage WM replaces AeroSpace; run only one of them. Both read `~/.aerospace.toml`, so your
config carries over, and with `start-at-login = true` both would start at login.

```bash
brew uninstall --cask aerospace   # keeps ~/.aerospace.toml
brew install --cask tech-maou/tap/aerostage
```

Homebrew refuses to install or upgrade AeroStage WM while the `aerospace` cask is installed.
If AeroSpace was installed without Homebrew, move `AeroSpace.app` to the Trash. AeroStage warns
when both run at the same time and offers to quit AeroSpace (its windows are returned to the
screen first). **Settings → Versions & Updates** shows the AeroSpace version while it is
installed.

### Updates

Once a day AeroStage asks GitHub for new releases of AeroStage and AeroStage WM. When there is
one, you get a notification, the menu bar icon shows a dot and its menu starts with
**Update Available**. **Update Now** returns all windows to the screen, quits both apps,
runs `brew upgrade` and opens them again; the log is in `~/Library/Logs/AeroStage/update.log`.
Turn the check off or run it by hand under **Settings → Versions & Updates** (or
`aerostage update`). Only the two public release URLs on `api.github.com` are requested.

Updating in the terminal works as well; the casks quit the apps first and reopen them:

```bash
brew update && brew upgrade --cask aerostage aerostage-wm
```

### From source

The Command Line Tools are enough (`xcode-select --install`); Xcode is not required.

```bash
git clone https://github.com/Tech-Maou/AeroStage.git
cd AeroStage
scripts/install.sh
```

`install.sh` builds the app, signs it, copies it to `/Applications` and launches it. Install
AeroStage WM separately, from its [releases](https://github.com/Tech-Maou/AeroStage-WM/releases)
or its source. Updates of a build from source are offered as a download, not installed.

## Setup

1. Launch **AeroStage WM** and allow it under **System Settings → Privacy & Security →
   Accessibility**. It is the window manager; AeroStage itself needs no Accessibility
   permission.
2. Launch **AeroStage**. On first launch:
   - AeroStage creates `~/.aerospace.toml` if none exists.
   - In an existing config only the marked sections are changed (see below).
   - The current main monitor is added to the priority list, followed by the built-in display.
   - macOS asks for **Screen Recording** permission, which is needed for thumbnails.
3. Open the settings from the menu bar icon or by right-clicking the sidebar → **Settings …**
   There you can also let both apps start at login.

### Managed AeroSpace config

AeroStage only writes between these markers:

```toml
# >>> AeroStage: gaps (managed) >>>
…  # gaps, including the space for the sidebar
# <<< AeroStage: gaps <<<

    # >>> AeroStage: bindings (managed) >>>
    …  # AeroSpace default shortcuts with the chosen modifier
    # <<< AeroStage: bindings <<<

    # >>> AeroStage: stages (managed) >>>
    …  # shortcuts for the stages
    # <<< AeroStage: stages <<<
```

Everything outside the markers stays untouched.
- Before its first change AeroStage saves a backup as `~/.aerospace.toml.aerostage-backup`.
- If your own config has no markers, AeroStage leaves it alone. Copy the sections from
  [`DefaultConfig.swift`](Sources/AeroStageCore/DefaultConfig.swift) into it.
- Config management can be turned off completely in the settings.

## Usage

All shortcuts use one modifier (`mod` below), chosen under **Settings → AeroStage WM →
Keyboard**:

| Preset | Modifier | For |
|---|---|---|
| **US** | `alt` | US/ABC layouts, exactly like AeroSpace's defaults |
| **International** | `ctrl-alt` | Layouts where `alt`+key types characters you need, e.g. German `@ [ ] { } \| ~` |
| **Custom** | `cmd-alt`, `ctrl-alt-cmd` | Anything else |

On first launch AeroStage picks the preset that matches your current keyboard layout.

| Shortcut | Effect |
|---|---|
| `mod-1` … `9` | Switch to the stage at position n. Count + 1 opens a new stage |
| `mod-shift-1` … `9` | Move the focused window to the stage at position n |
| `mod-n` | Move the window to a new stage and follow it |
| `alt-tab` / `alt-shift-tab` | Next / previous stage |
| `mod-s` | Show or hide the sidebar (overlay: show until a stage is chosen) |

All other AeroSpace default shortcuts are kept with the same modifier: `mod-h/j/k/l` focus,
`mod-shift-h/j/k/l` move, `mod-slash`/`mod-comma` layouts, `mod-minus`/`mod-equal` resize,
`mod-shift-semicolon` service mode.

The number of stages adapts to the sidebar monitor: as many as fit with previews at 70 % or
more of their full size, between 3 and 9 (e.g. 7 stacked or 9 in layout view on a 2560×1080
display). With many stages all previews shrink evenly, so every stage stays visible.

### Command line

```bash
aerostage <command>    # installed with Homebrew; otherwise
/Applications/AeroStage.app/Contents/Helpers/aerostage <command>
```

| Command | Effect |
|---|---|
| `focus <n>` / `move <n>` | Switch stage / move window |
| `new`, `next`, `prev` | New stage, next, previous |
| `toggle`, `settings` | Show/hide sidebar, open settings |
| `update` | Check for updates and show the result |
| `reload`, `status`, `quit` | Re-sync, show status (connection, window manager, monitor, stages, permissions), quit |

If AeroStage is not running, the CLI passes `focus`, `move`, `next` and `prev` straight to
AeroSpace, so the shortcuts keep working.

## Permissions

| App | Permission | Used for |
|---|---|---|
| AeroStage WM | Accessibility | Moving and resizing windows (required) |
| AeroStage | Screen Recording | Window thumbnails |
| AeroStage | Notifications | Update available, window manager quit (optional) |

Both apps are signed with the same long-lived certificate, so macOS keeps these permissions
across updates.

Without Screen Recording the sidebar shows app icons. Grant it under **System Settings → Privacy &
Security → Screen & System Audio Recording**, or via the button in the AeroStage settings.

If thumbnails do not appear even though the permission is granted (`aerostage status`
reports "not allowed"), reset the entry, restart AeroStage and allow the prompt again:

```bash
tccutil reset ScreenCapture io.github.tech-maou.AeroStage
```

AeroStage controls windows exclusively through the `aerospace` CLI and therefore needs no
Accessibility permission of its own.

## Why AeroStage WM?

AeroStage started as a pure companion app that talks to AeroSpace only through its command
line (`aerospace subscribe`, `list-windows`, …). That works, with one gap: AeroSpace reports
no event when a window is **closed** or **minimized**, when a window is **moved** to another
workspace, or when a workspace becomes **empty**. A sidebar needs exactly these to stay
correct.

- A request for a `window-closed` event was declined upstream
  ([PR #2199](https://github.com/nikitabobko/AeroSpace/pull/2199)), and other proposals for
  more events were closed without review. AeroSpace does not take issues directly; ideas go
  through Discussions, and most of them get no answer. That is the maintainer's choice, but
  it means we cannot wait for these events.
- Without them, AeroStage has to ask the window server twice a second whether the visible
  stage's windows are still there. It works, but it is a workaround. AeroStage WM adds one
  event, `workspace-windows-changed`, that covers all these cases and stays silent while the
  screen is locked; AeroStage then needs no check at all.
- AeroStage WM is a **thin fork**: AeroSpace's code with as few, well-separated changes as
  possible: new name, the extra `subscribe` event, a menu bar item that AeroStage can hide,
  windows returned to the screen on every regular quit, and a build script. It keeps AeroSpace's
  history, so new AeroSpace releases can be taken over by rebasing these changes.
- It has its **own name** because the MIT license covers the code but grants no rights to the
  name "AeroSpace", and because an app called AeroSpace with a different behavior would be
  confusing. Its CLI (`aerostage-wm`), bundle ID and internal paths differ so that it never
  collides with an installed AeroSpace. The config file stays the same, so existing
  AeroSpace configs keep working.

## Known limitations

- AeroSpace tiles every window to fill its stage; windows cannot be snapped to a side with
  the mouse. Arrange them with `mod-shift-h/j/k/l` and switch layouts with `mod-slash` or
  `mod-comma`. A window that floats above the others (marked in the sidebar) is tiled again
  via its context menu (**Tiling**) or with service mode (`mod-shift-semicolon`, then `f`).

- Some apps cannot be made narrower than a certain width (Firefox, for example, ~600 pt). With
  many windows side by side, such windows overlap their neighbor slightly. This is AeroSpace
  behavior with minimum window sizes and happens sooner in reserved mode. Use overlay mode or
  the accordion layout (`mod-comma`).

- After a restart of the Mac all windows start on one stage. The stage assignment is only
  restored when the window manager restarts while the windows stay open, because macOS gives
  windows new ids after a reboot.

- "Update Now" needs the Homebrew installation. With a build from source the update window
  links to the release page.

## Uninstall

```bash
brew uninstall --cask aerostage aerostage-wm          # keeps settings
brew uninstall --zap --cask aerostage aerostage-wm    # also removes settings
```

Without Homebrew: quit AeroStage (`aerostage quit`), delete `/Applications/AeroStage.app` and
run `defaults delete io.github.tech-maou.AeroStage`.

Then restore `~/.aerospace.toml` from the backup `~/.aerospace.toml.aerostage-backup` or adjust
the marked sections yourself. Neither uninstall removes the config or its backup.

## Development

```bash
scripts/test.sh      # tests (Swift Testing, works without Xcode)
scripts/bundle.sh    # builds build/AeroStage.app
scripts/install.sh   # builds, installs to /Applications, restarts
scripts/release.sh   # builds dist/AeroStage-v<version>.zip for a GitHub release
scripts/publish.sh   # dev → main, tag, signed zip, GitHub release, Homebrew cask
```

`publish.sh` needs the GitHub CLI (`gh auth login`) and the long-lived signing certificate
**"AeroStage Release"**. Releases are always signed with it, so macOS keeps the Screen
Recording and Accessibility permissions across updates (the permission is tied to the
certificate, not to a single build). Release notes come from the matching `## <version>`
section of the changelog.

`release.sh` prints the zip's SHA256 and updates `Casks/aerostage.rb` in the
[tap](https://github.com/Tech-Maou/homebrew-tap) if it is checked out next to this repository.
The app icon is drawn by `swift scripts/make-icons.swift` (it also draws AeroStage WM's icon).
Release notes are in the [changelog](CHANGELOG.md).

`bundle.sh` signs with **"AeroStage Release"** if present, otherwise **"AeroStage Dev"**,
otherwise ad-hoc. With a stable certificate the Screen Recording permission survives every
rebuild.

To create one:
1. Open **Keychain Access**.
2. Choose **Certificate Assistant → Create a Certificate**.
3. Name `AeroStage Dev`, identity type **Self-Signed Root**, certificate type **Code Signing**.

A different certificate can be set via `AEROSTAGE_SIGN_IDENTITY`.

Structure: `AeroStageCore` (models, logic, IPC), `AeroStageApp` (sidebar, state, AeroSpace
integration), `aerostage` (CLI). Details in the [specification](SPEC.md).

## License

AeroStage is released under the [MIT License](LICENSE).

The config template is based on AeroSpace's default config (MIT, © 2023 Nikita Bobko). See the
[third-party notices](THIRD-PARTY-NOTICES.md).

AeroStage WM, the window manager AeroStage is built for, is a fork of AeroSpace and keeps
AeroSpace's MIT license and copyright notice; see its repository.

## Acknowledgements

To [Nikita Bobko](https://github.com/nikitabobko) and all contributors of
[AeroSpace](https://github.com/nikitabobko/AeroSpace). Without AeroSpace and its CLI there
would be no AeroStage.
