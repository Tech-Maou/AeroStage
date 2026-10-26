# Changelog

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
