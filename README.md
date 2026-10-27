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

**Available (v1.0)**

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
  toggle floating/tiling, or close it; right-click a card to switch to or close the whole stage.
- **Dynamic numbering** like Stage Manager: stages appear and disappear automatically and
  the numbers close up without gaps. Classic fixed AeroSpace numbering is available too.
- When the last window of the visible stage is closed, minimized or moved away, AeroStage
  shows the stage above it (or the next one if it was the first).
- **Monitor priority list:** the sidebar appears on your preferred connected monitor (e.g.
  the external display, otherwise the built-in one). Other monitors such as a TV stay free.
- Real-time updates via the window manager's `subscribe` event stream. With AeroStage WM
  closed, minimized and moved windows arrive as events (`workspace-windows-changed`); with
  plain AeroSpace a lightweight window-server check twice a second covers the visible stage.
- **Customizable look:** background color, opacity and optional blur, title color and size,
  icon size.
- **Launch at login** for AeroStage and AeroSpace, switchable in the settings.
- Settings in four tabs: General, Appearance, Keyboard, AeroSpace.
- No Dock icon, never steals keyboard focus.

**Planned**

- Small fixes from daily use; ideas are welcome as issues.

Details are in the [specification](SPEC.md).

## Requirements

- macOS 14 Sonoma or later
- [AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM) (recommended) or
  [AeroSpace](https://github.com/nikitabobko/AeroSpace) 0.21 or later, with Accessibility
  permission

## Installation

### Homebrew (from the first release on)

```bash
brew install --cask tech-maou/tap/aerostage
```

The cask installs AeroStage WM as a dependency. AeroStage is not notarized by Apple because the
project does not use a paid Apple developer account, so the cask removes the quarantine
attribute to let macOS launch the app.

### From source

The Command Line Tools are enough (`xcode-select --install`); Xcode is not required.

```bash
git clone https://github.com/Tech-Maou/AeroStage.git
cd AeroStage
scripts/install.sh
```

`install.sh` builds the app, signs it, copies it to `/Applications` and launches it.

## Setup

1. Install [AeroStage WM](https://github.com/Tech-Maou/AeroStage-WM), launch it and allow it
   under **System Settings → Privacy & Security → Accessibility**. Quit and uninstall the
   original AeroSpace first; two window managers must not run at the same time.
2. Launch AeroStage. On first launch:
   - AeroStage creates `~/.aerospace.toml` if none exists.
   - In an existing config only the marked sections are changed (see below).
   - The current main monitor is added to the priority list, followed by the built-in display.
   - macOS asks for **Screen Recording** permission, which is needed for thumbnails.
3. Open the settings: right-click the sidebar → **Settings …**

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

All shortcuts use one modifier (`mod` below), chosen under **Settings → Keyboard**:

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
/Applications/AeroStage.app/Contents/Helpers/aerostage <command>
```

| Command | Effect |
|---|---|
| `focus <n>` / `move <n>` | Switch stage / move window |
| `new`, `next`, `prev` | New stage, next, previous |
| `toggle`, `settings` | Show/hide sidebar, open settings |
| `reload`, `status`, `quit` | Re-sync, show status, quit |

If AeroStage is not running, the CLI passes `focus`, `move`, `next` and `prev` straight to
AeroSpace, so the shortcuts keep working.

## Permissions

| Permission | Used for |
|---|---|
| Screen Recording | Window thumbnails |

Without it the sidebar shows app icons. Grant it under **System Settings → Privacy &
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
  possible (new name, extra `subscribe` events, a build script). It keeps AeroSpace's
  history, so new AeroSpace releases can be taken over by rebasing these changes.
- It has its **own name** because the MIT license covers the code but grants no rights to the
  name "AeroSpace", and because an app called AeroSpace with a different behavior would be
  confusing. Its CLI (`aerostage-wm`), bundle ID and internal paths differ so that it never
  collides with an installed AeroSpace. The config file stays the same, so existing
  AeroSpace configs keep working.

## Known limitations

- AeroSpace tiles every window to fill its stage; windows cannot be snapped to a side with
  the mouse. Arrange them with `mod-shift-h/j/k/l` and switch layouts with `mod-slash` or
  `mod-comma`. A window that floats above the others can be tiled again via its context
  menu (**Toggle Floating / Tiling**) or with service mode (`mod-shift-semicolon`, then `f`).

- Some apps cannot be made narrower than a certain width (Firefox, for example, ~600 pt). With
  many windows side by side, such windows overlap their neighbor slightly. This is AeroSpace
  behavior with minimum window sizes and happens sooner in reserved mode. Use overlay mode or
  the accordion layout (`mod-comma`).

## Uninstall

```bash
/Applications/AeroStage.app/Contents/Helpers/aerostage quit
rm -rf /Applications/AeroStage.app
defaults delete io.github.tech-maou.AeroStage
```

Then restore `~/.aerospace.toml` from the backup `~/.aerospace.toml.aerostage-backup` or adjust
the marked sections yourself.

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

`bundle.sh` signs with the code signing certificate **"AeroStage Dev"** if present, otherwise
ad-hoc. With a stable certificate the Screen Recording permission survives every rebuild.

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
