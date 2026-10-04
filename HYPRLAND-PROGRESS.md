# Hyprland overview — progress log (EEST)

Test VM: CachyOS-KDE, Hyprland 0.56.2 (Lua), 3440x1440 @ 75 Hz, virtio GL.
Evidence screenshots: evidence-hypr/.

- 18:29 Hyprland backend (overview/Hyprland.qml) + shared actions in Mango.qml; shell.qml picks one.
- 18:29 Opens in VM on Noctalia: cards stacked, blurred wallpaper, live previews (t1-open2.png).
- 18:34 Zoom: 21 frames per 320 ms zoom (max ~24 at 75 Hz), worst 13-26 ms after the first. First zoom after start is slow (69-377 ms).
- 18:45 check 1 (scale 1.25 + QT_SCALE_FACTOR 1.2): zoom start lines up with the real screen (s1-zoomstart vs s1-desktop) — PASS
- 18:45 found + fixed ghost text in previews of see-through windows: capture asked for no-alpha pixels (XRGB), Hyprland filled the see-through parts with old screen content. Now asks for ARGB first (s1-fixed = before, s1-argb/s1-noclear = after, live text updates clean)
- 18:55 check 3 (Noctalia): 21 frames / 320 ms, worst 13-28 ms, first open after restart 14 ms — PASS
- 18:55 check 4: close mid-zoom, end, after hide all clean (s4-c1/c2/c3) — PASS
- 18:55 check 13 keys (real input via QMP/send-key): Super+O opens, Down+Enter, K+Esc, W+Space all work, submap back to default; click activates; middle-click closes a window and the overview stays open, card clean (s2-closed). Gestures: no touchpad in VM.
- 19:05 Icon fix (shared WindowTile.qml): apps with no desktop file showed a magenta "missing icon" checker; now app id → generic → no icon. 0 icon warnings (s14-many-iconfix).
- 19:05 Check 9 PASS (Noctalia): in the overview, screen/area/window screenshot keys all save a file (s9-*). Area picker (slurp) shows above the overview. Window mode grabs the window's spot on screen, so it shows the overview (same as on Mango).
- 19:05 Check 10 PASS: real uinput holds (3 s) of Super+O open/close exactly once, no flicker mid-hold (s10-hold-real1..3); held Esc closes once. virsh send-key can't hold (PS/2 delivers press at release) — that fooled the first try.
- 19:15 Check 11 PASS: opens above a fullscreen window, no peeking strip.
- 19:15 Check 12 fixed + PASS: first frame was a dark card with an icon (s12-blank-frame). Now waits (max 300 ms) for wallpaper + fresh window pictures before showing; 3 bursts no dark dip (s12-first-open-*).
- 19:15 Check 2 PASS: open grabs a fresh picture (was 20 s old); ended capture sessions restart (s2-*). Hidden workspaces show their last picture (Hyprland only draws the visible one) — not blank, but frozen.
- 19:15 Check 7 (reload part) PASS: hyprctl reload while closed and while open, previews stay live, Esc works (s7-*).
- 19:15 Check 8 PASS: wallpaper change shows in the next open.
- 19:20 Check 5/6 fixed: Hyprland blocks clicks to the bar while we hold the keyboard exclusively. Now: exclusive only while opening, then on-demand; after a bar popup closes, a short exclusive grab 100 ms later takes the keyboard back.
- 19:23 Check 6 PASS (Noctalia): clock popup shows above, launcher takes typing ("kit" → kitty, s6-launcher-typing-in-overview), Esc closes popup, next Esc closes overview.
- 19:24 Check 5 PASS (Noctalia): bar visible + clickable in overview, strip lines up (s5-bar-*).
- 19:25 Check 3 re-check after focus change: arrows + Enter, open/close x3 all fine.
- 19:26 Check 14: empty active workspace shows as a wallpaper card, Enter stays (s14-empty-active-ws).
- 19:28 Multi-monitor via headless 2nd output (scale 2): opens on the focused screen only (same as Mango), shows only that screen's workspaces (s14-mon2-*). Found + fixed: after moving screens the overview covered the 2nd screen's bar (fit into bar zones only at first map) — now fitted while closed too.
- 19:30 Found + fixed: Quickshell crashed (QWindow::setScreen) when it hot-reloaded our files with 2 screens. Overview now turns off file watching (an upgrade takes effect next login). Verified: file change → no reload, no crash.
20:03 DMS spotlight-close regain: fails when cursor sits over the bar area (1719,8), passes at screen centre — cause is Hyprland's Exclusive→OnDemand simulateMouseMovement. Paused for new gesture requirement.

## Drag-and-drop + gesture round (Oct 4–5, EEST)
- before 00:40 Built drag-and-drop: hold a preview, it follows the pointer; landing side highlighted (left/right/top/bottom); drop on another row moves it there, same row rearranges; "+" new row past the last; screen edges auto-scroll. Hyprland drop = park in special:mango-overview, focus target, layout preselect, move to workspace. Live 3-finger vertical swipe in the overview (SwipeTracker in the capture plugin).
- before 00:40 Fixed: previews frozen at the old size after a move — capture onFailed now asks for a new frame; ended sessions retry up to 6 times.
- 00:41 Hyprland+DMS: vertical 3-finger swipe in overview PASS, swipe right after a drag PASS, horizontal swipe on desktop PASS; horizontal swipe while open does nothing (by design — rows go up/down). Drags h1–h6 PASS, floating cross-row PASS, edge auto-scroll to new ws4 PASS, click focus PASS, middle-click close PASS, screenshot keys in overview PASS, Mod+O / Esc PASS.
- 00:45 Fixed: a floating window's drop showed a left/right side it never takes; now the whole row lights up (floating keeps its own spot). Noctalia: floating whole-row drag PASS (n2), cross-row PASS, previews live after zshell switch PASS.
- 00:48 Noctalia: middle-click closes the keyring dialog, no ghost (n6) PASS. Same-row drag → side by side PASS (n8).
- 00:49 Found: window dropped on a NEW row stayed a blank card (icon only). Its new capture session never sent a first frame. Fix: if a session gives no frame in 1 s, restart it (max 6). After fix new-row drop shows the picture (r2-*) PASS. Debug log line removed.
- 00:51 zshell switch dms (shell starts after overview, right order): wallpaper updated (check 8) PASS, previews live (check 7) PASS, bar visible (check 5) PASS.
- 00:52 DMS spotlight above overview, typing "kit" filters PASS (d3). Esc with cursor ON the bar closes spotlight, second Esc closes overview → keyboard regained PASS (the 20:03 failure is gone).
- 00:52 Check 10 (DMS): real uinput hold of Super+O 1.8 s — opens once, no flicker, stays open after release PASS.
- 00:55 Check 13/14 swipe (Hyprland DMS): first tries did nothing because the pointer was still on the DMS bar (swipes go to the surface under the pointer — same rule as the compositor). Pointer moved over the overview → vertical swipe scrolls rows (d14e). PASS
- 00:56 Check 14 MO2 (DMS): headless 2nd monitor, focus it, Super+O → overview opens on MO2 only, shows that monitor's workspace 3 with a live preview + new-row card; main monitor untouched (d14g) PASS.

## Mango × DMS (VM 192.168.122.55)

- 01:00 m1 PASS — previews live on every row, including the scroller window that sits off-screen.
- 01:01 mg1 PASS — dropped 3 onto tag 2, right of 4: it moved there and landed on the right.
- 01:01 mg2 PASS — same-row drop of 3 left of 4; the left-half highlight showed mid-drag.
- 01:02 mg3 PASS — bottom drop: 4 stacked under 3 (bottom-half highlight).
- 01:02 mg4 PASS — floating 5 → tag 1; whole-row highlight; still floating afterwards.
- 01:02 mg5 PASS — drop on the "+" card past the last row: 2 went to new tag 3, preview live.
- 01:03 mg6 PASS — click focuses window 4, overview closes, keymode back to default.
- 01:03 mg7 PASS — middle-click closed a spare kitty, no ghost, overview stayed open.
- 01:03 mg8 PASS — 3 fingers up/down in the overview: rows follow the fingers mid-swipe (screenshot) and snap.
- 01:05 mg9/10 PASS — 3 fingers left/right in the overview move the selection one window per swipe (Mango gesturebind, a step, not live; that is the README setup).
- before 01:15 Fixed (Mango): with tag_gather on, a drop renumbers the rows; the selection used to jump mid-drag. Now it stays put while dragging and follows the moved window after the renumber.
- before 01:15 mg13–mg18 PASS — drop on an empty row (mg14), previews live after `mmsg dispatch reload_config` (mg15), screenshot keys in the overview (check 9), above a fullscreen window (check 11).
- before 01:15 Check 10 (Mango) found: Mango repeats a held bind (~600 ms, then every 40 ms) and each repeat starts a new `qs ipc`; gaps of 190–300 ms, stalls up to 891 ms in the VM, so the old 800/250 ms filter still flickered. Fix: on Mango a toggle within 1 s of the last call is ignored (Hyprland unchanged). VM overview keymode got the screenshot binds (backup /tmp/keybinds.bak on the VM).

## Mango × Noctalia (VM 192.168.122.55)

- before 01:26 mn1 PASS — wallpaper change shows on next open (check 8); bar visible (check 5).
- before 01:26 mn2 PASS — middle-click closes a window, overview stays open, no ghost.
- before 01:26 mn4 PASS same-row drop right; mn5 PASS top drop; mn6 PASS edge auto-scroll drop; mn7 PASS cross-row drop beside a window; mn8 PASS floating window to another tag (stays floating); mn9 PASS drop on "+" new row.
- before 01:26 mn10 PASS click focus; mn11/12 PASS live vertical 3-finger swipe (mid-swipe frame); mn13 PASS 3-finger left/right moves the selection.
- before 01:26 mn14 PASS screenshot keys in overview (check 9).
- before 01:26 Check 10 PASS with the 1 s filter: 8/8 holds alternate open/close, no flicker; taps 1.2 s apart all toggle.
- before 01:26 mn15 PASS above a fullscreen window (check 11).
- 01:26 mn16 PASS launcher above the overview, typing filters (checks 5/6). mn17 PASS bar clock click opens the calendar above the overview.

## Mango × DMS, second round (after the 1 s filter)

- 01:27 zshell switch dms: overview (pid 33844) starts before DMS (37662) — right order (check 6).
- 01:27 md1/md2 PASS previews live after the switch (check 7); DMS wallpaper blurred and current (check 8).
- 01:28 md3/md4 PASS Spotlight above the overview, typing works; Esc closes only Spotlight. md5 PASS bar clock opens DMS dashboard.
- 01:28 Check 10 PASS: 4 holds alternate overview/default/overview/default, brightness steady.
- 01:29 md6/md7 PASS 7 windows on one row: new kitties show as icons, all live within ~4 s (check 14 many windows).
- 01:29 md8 PASS cross-row drop (top side, highlight matched). md9 PASS same-row left drop (left-half highlight). Middle-click close 13 → 12 windows PASS.
- 01:30 md12 PASS live vertical swipe (partial frames, then snap). 01:31 md13 PASS 3-finger left/right moves the selection.
- after 01:31 Cleanup: spare kitties closed. All Mango and Hyprland checks on both shells PASS.
- 01:33 Found + fixed: install rules missed overview/Hyprland.qml (dev runs from the repo hid it). Test install into a temp folder now has all 5 QML files + capture plugin. QML on VM .55 is byte-identical to the commit.
