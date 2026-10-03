# mango-overview

A zoom-out overview for the [Mango](https://github.com/mangowm/mango) Wayland
compositor, in the style of niri's overview. Every workspace (Mango calls them
tags) becomes a card stacked under the others, with **live previews** of the
windows on it, over your wallpaper blurred.

It runs on stock [Quickshell](https://quickshell.org) next to whatever desktop
shell you use (Noctalia, DankMaterialShell, or none). Live previews come from a
small add-on in `capture/` that speaks the standard `ext-image-copy-capture`
Wayland protocol, so nothing else is patched.

## Use

| Do this | It does |
|---|---|
| Mod+O / four fingers up | open or close |
| arrows, WASD, HJKL, three fingers | move between windows and workspaces |
| mouse wheel | next / previous workspace |
| Enter, Space, click | go to that window |
| 1–9 | jump to that workspace |
| middle click | close that window |
| Esc, click on empty space | close, stay where you were |

## Install

**Ready-made (Arch):** `cd packaging/arch/mango-overview-bin && makepkg -si`

**Build it yourself (Arch):** `cd packaging/arch/mango-overview && makepkg -si`

**Any distro:** needs Qt 6.5+, Quickshell, CMake, wayland-protocols.

```sh
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
sudo cmake --install build
```

## Mango setup

```ini
# autostart: start it before your shell (Noctalia, DMS...), so the shell's
# menus open on top of the overview
exec-once=mango-overview

# keys and gestures (default mode)
bind=SUPER,o,spawn,mango-overview toggle
gesturebind=none,up,4,spawn,mango-overview open

# while the overview is open it switches Mango to the "overview" key mode
keymode=overview
bind=SUPER,o,spawn,mango-overview toggle
bind=SUPER,Escape,spawn_shell,mango-overview close; mmsg dispatch setkeymode,default
gesturebind=none,left,3,spawn,mango-overview right
gesturebind=none,right,3,spawn,mango-overview left
gesturebind=none,up,3,spawn,mango-overview down
gesturebind=none,down,3,spawn,mango-overview up
gesturebind=none,down,4,spawn,mango-overview close
# normal binds are off in this mode, so repeat any you want, e.g. screenshots
bind=SUPER+SHIFT,s,spawn,grim -g "$(slurp)" - | wl-copy
keymode=default
```

Commands: `mango-overview toggle | open | close | left | right | up | down | activate`.

## Settings (environment variables)

| Variable | Default | What |
|---|---|---|
| `MANGO_OVERVIEW_ZOOM` | `0.42` | how far it zooms out |
| `MANGO_OVERVIEW_ANIM_MS` | `320` | animation length |
| `MANGO_OVERVIEW_ACCENT` | your Qt highlight colour | selection colour |
| `MANGO_OVERVIEW_WALLPAPER_CMD` | asks Noctalia, then DMS | command that prints the wallpaper path |
| `MANGO_OVERVIEW_BAR_EDGE` | `top` | where your bar is (`top`, `bottom`, `left`, `right`), so zooming lines up |
| `MANGO_OVERVIEW_COVER_BAR` | off | `1` draws over the bar instead of leaving it visible and clickable |
| `MANGO_OVERVIEW_DEBUG` | off | `1` logs frame timings of each zoom |

## License

GPL-3.0-or-later
