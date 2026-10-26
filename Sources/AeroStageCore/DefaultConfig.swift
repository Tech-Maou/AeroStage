import Foundation

/// Template for `~/.aerospace.toml` if none exists yet.
/// Based on AeroSpace 0.21.3 default-config.toml; shortcuts and gaps are managed by AeroStage.
public enum DefaultConfig {
    public static let template = #"""
# AeroSpace configuration, created by AeroStage
# Based on AeroSpace 0.21.3 default-config.toml
# Docs: https://nikitabobko.github.io/AeroSpace/guide
#
# Gaps and keyboard shortcuts live in the sections marked "managed" and are rewritten by
# AeroStage (Settings → Keyboard). The modifier depends on the keyboard: alt like in
# AeroSpace for US layouts, ctrl-alt for layouts where alt+key types characters
# (German: alt-l = @, alt-5…9 = [ ] | { }).

config-version = 2

after-startup-command = []

# Off until the setup is complete
start-at-login = false

# Changes to this file are applied automatically on save
auto-reload-config = true

enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

automatically-unhide-macos-hidden-apps = false

# Empty: workspaces without windows disappear (Stage Manager behavior)
persistent-workspaces = []

on-mode-changed = []

focus-follows-mouse.enabled = false

key-mapping.preset = 'qwerty'

# >>> AeroStage: gaps (managed) >>>
gaps.inner.horizontal = 8
gaps.inner.vertical =   8
gaps.outer.left =       8
gaps.outer.bottom =     8
gaps.outer.top =        8
gaps.outer.right =      8
# <<< AeroStage: gaps <<<

[mode.main.binding]

    # >>> AeroStage: bindings (managed) >>>
    ctrl-alt-slash = 'layout tiles horizontal vertical'
    ctrl-alt-comma = 'layout accordion horizontal vertical'

    ctrl-alt-h = 'focus left'
    ctrl-alt-j = 'focus down'
    ctrl-alt-k = 'focus up'
    ctrl-alt-l = 'focus right'

    ctrl-alt-shift-h = 'move left'
    ctrl-alt-shift-j = 'move down'
    ctrl-alt-shift-k = 'move up'
    ctrl-alt-shift-l = 'move right'

    ctrl-alt-minus = 'resize smart -50'
    ctrl-alt-equal = 'resize smart +50'

    ctrl-alt-shift-semicolon = 'mode service'
    # <<< AeroStage: bindings <<<

    # >>> AeroStage: stages (managed) >>>
    # Rewritten by AeroStage on start
    ctrl-alt-1 = 'workspace 1'
    ctrl-alt-2 = 'workspace 2'
    ctrl-alt-3 = 'workspace 3'
    ctrl-alt-4 = 'workspace 4'
    ctrl-alt-5 = 'workspace 5'

    ctrl-alt-shift-1 = 'move-node-to-workspace 1'
    ctrl-alt-shift-2 = 'move-node-to-workspace 2'
    ctrl-alt-shift-3 = 'move-node-to-workspace 3'
    ctrl-alt-shift-4 = 'move-node-to-workspace 4'
    ctrl-alt-shift-5 = 'move-node-to-workspace 5'

    alt-tab = 'workspace next --wrap-around'
    alt-shift-tab = 'workspace prev --wrap-around'
    # <<< AeroStage: stages <<<

[mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main'] # reset layout
    f = ['layout floating tiling', 'mode main'] # toggle floating/tiling
    backspace = ['close-all-windows-but-current', 'mode main']

    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']
"""#
}
