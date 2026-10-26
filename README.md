# AeroStage

**A Stage Manager–style sidebar for the tiling window manager [AeroSpace](https://github.com/nikitabobko/AeroSpace).**

AeroStage shows every AeroSpace workspace as a "stage" in a slim sidebar at the edge of the
screen, like the strip of the macOS Stage Manager. You keep driving everything with the
keyboard through AeroSpace, but clicking a stage or a window works just as well.

> [!NOTE]
> AeroStage is an **unofficial companion app**. It is not part of AeroSpace and not maintained
> by its developers. AeroSpace has to be installed separately. Please report AeroStage issues
> here, not in the AeroSpace project.

## Features

**Available (v0.2)**

- Sidebar on the left or right, always visible. AeroSpace keeps its space free via gaps, on
  the sidebar's monitor only.
- One card per stage with **live window thumbnails**, also for stages in the background.
  Three views:
  - **Stacked Thumbnails** like in Stage Manager, the most recently used window in front
  - **Thumbnails in Layout**: the windows to scale at their actual position
  - **App Icons**
- Each card has a header with its number and apps, e.g. **"1.** Firefox, Mail, Code". The
  active stage is highlighted.
- Click a card to switch stages, click a thumbnail or icon to focus exactly that window.
- **Dynamic numbering** like Stage Manager: stages appear and disappear automatically and
  the numbers close up without gaps. Classic fixed AeroSpace numbering is available too.
- **Monitor priority list:** the sidebar appears on your preferred connected monitor (e.g.
  the external display, otherwise the built-in one). Other monitors such as a TV stay free.
- Real-time updates via `aerospace subscribe`, no state polling.
- Light and dark mode, no Dock icon, never steals keyboard focus.

**Planned**

- Phase 3: overlay mode (the sidebar slides in at the screen edge and floats above the
  windows), drag & drop between stages, context menus
- Phase 4: launch at login, complete settings, Homebrew release

Details are in the [specification](SPEC.md).

## Requirements

- macOS 14 Sonoma or later
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) 0.21 or later, with Accessibility
  permission

## Installation

### Homebrew (from the first release on)

```bash
brew install --cask tech-maou/tap/aerostage
```

The cask installs AeroSpace as a dependency. AeroStage is not notarized by Apple because the
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

1. Launch AeroSpace and allow it under **System Settings → Privacy & Security →
   Accessibility**.
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

    # >>> AeroStage: stages (managed) >>>
    …  # shortcuts for the stages
    # <<< AeroStage: stages <<<
```

Everything outside the markers stays untouched.
- Before its first change AeroStage saves a backup as `~/.aerospace.toml.aerostage-backup`.
- If your own config has no markers, AeroStage leaves it alone. Copy the two sections from
  [`DefaultConfig.swift`](Sources/AeroStageCore/DefaultConfig.swift) into it.
- Config management can be turned off completely in the settings.

## Usage

| Shortcut | Effect |
|---|---|
| `ctrl-alt-1` … `5` | Switch to the stage at position n. Count + 1 opens a new stage |
| `ctrl-alt-shift-1` … `5` | Move the focused window to the stage at position n |
| `ctrl-alt-n` | Move the window to a new stage and follow it |
| `alt-tab` / `alt-shift-tab` | Next / previous stage |
| `ctrl-alt-s` | Show or hide the sidebar |

All other AeroSpace shortcuts (focus, move, layouts, service mode) are kept, but with
`ctrl-alt` instead of `alt`: on many European keyboards `alt`+key types characters such as
`@`, `[`, `]`, `{`, `}`, `|` and `~`. The modifier can be changed in the settings, as can the
maximum number of stages (5, 7 or 9).

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

## Known limitations

- Some apps cannot be made narrower than a certain width (Firefox, for example, ~600 pt). With
  many windows side by side next to the reserved sidebar, such windows overlap their
  neighbor slightly. This is AeroSpace behavior with minimum window sizes. Use the accordion
  layout (`ctrl-alt-comma`), hide the sidebar (`ctrl-alt-s`) or, once available, overlay mode.

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
```

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

## Acknowledgements

To [Nikita Bobko](https://github.com/nikitabobko) and all contributors of
[AeroSpace](https://github.com/nikitabobko/AeroSpace). Without AeroSpace and its CLI there
would be no AeroStage.
