//@ pragma UseQApplication
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import MangoOverview.Capture

// niri-style overview for Mango and Hyprland: every tag (workspace) as a card stacked
// top to bottom, live window previews, zoom out on open and back in on pick.
ShellRoot {
	id: ov

	// ---- settings (environment) ----
	readonly property real overviewZoom: Number(Quickshell.env("MANGO_OVERVIEW_ZOOM") || 0.42)
	readonly property int animMs: Number(Quickshell.env("MANGO_OVERVIEW_ANIM_MS") || 320)
	// Leave the bar (Noctalia, DMS, waybar...) visible and clickable. Set to 1 to draw over it.
	readonly property bool coverBar: Quickshell.env("MANGO_OVERVIEW_COVER_BAR") === "1"
	// Which edge the bar is on, so the zoom lines up with the real windows.
	readonly property string barEdge: Quickshell.env("MANGO_OVERVIEW_BAR_EDGE") || "top"
	readonly property color accent: Quickshell.env("MANGO_OVERVIEW_ACCENT") || sysPalette.highlight

	// ---- state ----
	// The compositor: Mango.qml or Hyprland.qml, both with the same properties and actions.
	readonly property var wm: onHyprland ? hyprland : mango
	property bool open: false     // overview accepts input
	property bool shown: false    // overlay is on screen
	property bool animate: false  // camera/tile animations on
	property bool settled: false  // fully zoomed out: previews may go live
	property bool starting: false // waiting for the overlay's first frame
	// Hyprland sends no clicks to other surfaces (the bar) while a layer holds
	// the keyboard exclusively. So take the keyboard while opening, then hold it
	// on demand: it stays with us, but a click on the bar reaches the bar.
	property bool grabKeys: true
	property bool revealed: false // overlay drawn: wallpaper and first window pictures are in
	// A fullscreen window sits above the bar's layer, so then we must go higher too.
	property bool aboveFullscreen: false
	property string mode: "zoomed" // "zoomed" (looks like the desktop) or "overview"
	property int zoomTag: 1       // tag the camera zooms into when mode is "zoomed"
	property string monitorName: ""
	property int selTag: 1
	property int selClient: -1    // -1: empty tag selected
	property string wallpaper: ""

	SystemPalette {
		id: sysPalette
		colorGroup: SystemPalette.Active
	}

	// Unset reads as undefined, not "".
	readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
	Mango {
		id: mango
		active: !ov.onHyprland
	}
	Hyprland {
		id: hyprland
		active: ov.onHyprland
		// A bar popup closed: the keyboard goes back to the windows, so take it
		// again (a short exclusive grab moves it to us).
		onLayerClosed: ns => {
			if (!ov.open || ov.grabKeys) return;
			regrabTimer.restart();
		}
		// Also when a window takes the keyboard later (DMS's launcher fades out
		// first, and Hyprland refocuses the window only once the fade ends).
		// Not while another popup is open: that one should keep typing.
		onWindowFocused: {
			if (!ov.open || ov.grabKeys || !ov.settled || hyprland.popupOpen) return;
			regrabTimer.restart();
		}
	}
	// After Hyprland has handed the keyboard back to a window.
	Timer {
		id: regrabTimer
		interval: 100
		onTriggered: {
			if (!ov.open || hyprland.popupOpen) return;
			ov.grabKeys = true;
			releaseTimer.restart();
		}
	}
	Timer {
		id: releaseTimer
		interval: 100
		onTriggered: if (ov.settled) ov.grabKeys = false
	}

	// ---- derived data ----
	readonly property var monitor: {
		for (const m of wm.monitors) if (m.name === monitorName) return m;
		return null;
	}
	readonly property real screenW: monitor ? monitor.width : 1
	readonly property real screenH: monitor ? monitor.height : 1
	readonly property real rowGap: screenH * 0.1
	readonly property var monClients: wm.clients.filter(c => c.monitor === monitorName)
	readonly property int activeTag: {
		if (monitor) for (const t of monitor.tags) if (t.is_active) return t.index;
		return 1;
	}
	// Tags with windows, plus the one on screen.
	readonly property var tags: {
		const set = new Set([activeTag]);
		for (const c of monClients) for (const t of c.tags) set.add(t);
		return [...set].sort((a, b) => a - b);
	}
	readonly property var tileKeys: {
		const keys = [];
		for (const c of monClients) for (const t of c.tags) keys.push(t + ":" + c.id);
		return keys;
	}

	function windowsOf(tag) {
		return monClients.filter(c => c.tags.includes(tag)).sort((a, b) => (a.x - b.x) || (a.y - b.y));
	}
	// A tag not in the list (the new row offered while dragging) goes after the last row.
	function rowY(tag) {
		const i = tags.indexOf(tag);
		return (i < 0 ? tags.length : i) * (screenH + rowGap);
	}
	function clamp(v, lo, hi) {
		return Math.max(lo, Math.min(hi, v));
	}

	// ---- camera: world point (camX, camY) sits at the screen centre, scaled by camZ ----
	readonly property var targetCamera: {
		if (!monitor) return { z: 1, x: 0, y: 0 };
		if (mode === "zoomed") return { z: 1, x: screenW / 2, y: rowY(zoomTag) + screenH / 2 };

		const z = overviewZoom;
		let minX = 0, maxX = screenW;
		let selX = screenW / 2;
		for (const c of windowsOf(selTag)) {
			const x = c.x - monitor.x;
			minX = Math.min(minX, x);
			maxX = Math.max(maxX, x + c.width);
			if (c.id === selClient) selX = x + c.width / 2;
		}
		const pad = 48 / z;
		minX -= pad;
		maxX += pad;
		const half = screenW / 2 / z;
		const x = maxX - minX <= 2 * half ? (minX + maxX) / 2 : clamp(selX, minX + half, maxX - half);
		return { z: z, x: x, y: rowY(selTag) + screenH / 2 };
	}
	property real camZ: targetCamera.z
	property real camX: targetCamera.x
	property real camY: targetCamera.y + swipeY
	Behavior on camZ { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }
	Behavior on camX { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }
	// While the fingers drag, the camera follows them directly.
	Behavior on camY { enabled: ov.animate && !ov.swiping; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }

	// ---- 3-finger touchpad swipe: the rows follow the fingers, then snap ----
	// Finger travel (touchpad units) that moves the view by one row.
	readonly property real swipeRow: Number(Quickshell.env("MANGO_OVERVIEW_SWIPE_DISTANCE")) || 300
	property bool swiping: false  // a vertical swipe is moving the rows
	property real swipeY: 0       // camera offset from the selected row, world pixels
	property bool swipeLive: false // 3 fingers down while open
	property real swipeDX: 0
	property real swipeDY: 0
	property real swipeRaw: 0     // rows travelled from the selected row, before the stretch at the ends
	property var swipeTrail: []   // recent [time, rows] samples, for the flick speed
	function swipeBegin(fingers) {
		swipeLive = fingers === 3 && open && settled && !dragging;
		swipeDX = swipeDY = swipeRaw = 0;
		swipeTrail = [];
	}
	function swipeMove(dx, dy) {
		if (!swipeLive) return;
		if (!swiping) {
			// Decide the direction once, like the compositor does: sideways swipes are not ours.
			swipeDX += dx;
			swipeDY += dy;
			if (Math.abs(swipeDX) + Math.abs(swipeDY) < 10) return;
			if (Math.abs(swipeDX) > Math.abs(swipeDY)) {
				swipeLive = false;
				return;
			}
			swiping = true;
			dy = swipeDY;
		}
		// Natural direction: fingers up, rows up, so the next row comes in from below.
		const step = -dy / swipeRow;
		swipeRaw += step;
		const now = Date.now();
		swipeTrail = swipeTrail.filter(p => now - p[0] < 100).concat([[now, swipeRaw]]);
		swipeY = swipeRows(swipeRaw) * (screenH + rowGap);
	}
	// Past the first or last row the view stretches a little and pulls back.
	function swipeRows(raw) {
		const i = Math.max(0, tags.indexOf(selTag));
		const lo = -i, hi = tags.length - 1 - i, give = 0.25;
		if (raw < lo) return lo - give * (1 - Math.exp((raw - lo) / give));
		if (raw > hi) return hi + give * (1 - Math.exp((hi - raw) / give));
		return raw;
	}
	function swipeEnd() {
		const was = swiping;
		swipeLive = false;
		if (!was) return;
		const i = Math.max(0, tags.indexOf(selTag));
		// A quick flick goes on a little further than where the fingers stopped:
		// speed over the last 100 ms (none if the fingers rested before lifting).
		const now = Date.now();
		const recent = swipeTrail.filter(p => now - p[0] < 100);
		const vel = recent.length > 1 ? (swipeRaw - recent[0][1]) / Math.max(0.03, (now - recent[0][0]) / 1000) : 0;
		const fling = clamp(vel * 0.25, -1, 1);
		const target = clamp(Math.round(i + swipeRows(swipeRaw) + fling), 0, tags.length - 1);
		swiping = false;
		// Move the selection and drop the offset together: the camera then
		// glides from where the fingers left it to the new row.
		const tag = tags[target];
		if (tag !== selTag) selectTag(tag);
		swipeY = 0;
	}
	function swipeCancel() {
		swipeLive = false;
		swiping = false;
		swipeY = 0;
	}
	// ---- drag and drop: hold a window, drag it, drop it on a row or next to a window ----
	property int dragId: -1       // the window being dragged, -1: none
	property int dragFrom: -1     // its tag
	property real dragSX: 0       // pointer, in overlay pixels
	property real dragSY: 0
	readonly property bool dragging: dragId >= 0
	// The pointer in world pixels (follows the camera too).
	readonly property real dragWX: (dragSX - centreX) / viewZ + camX
	readonly property real dragWY: (dragSY - centreY) / viewZ + camY
	// An empty row after the last one, to drop a window on a new tag.
	readonly property int newTag: {
		const last = tags.length > 0 ? tags[tags.length - 1] : 0;
		return last + 1 <= wm.maxTag ? last + 1 : -1;
	}
	readonly property var dragRows: dragging && newTag > 0 ? tags.concat([newTag]) : tags
	// Where the window would land: { tag, target (window id or -1), side, x, y, w, h (highlight) }.
	readonly property var drop: dragging ? dropAt(dragWX, dragWY) : null
	function dropAt(wx, wy) {
		if (!monitor || dragRows.length === 0) return null;
		const step = screenH + rowGap;
		const i = clamp(Math.floor((wy + rowGap / 2) / step), 0, dragRows.length - 1);
		const tag = dragRows[i];
		const ry = rowY(tag);
		const wins = windowsOf(tag).filter(c => c.id !== dragId && !c.is_floating);
		// A floating window keeps floating, so it can only pick the row, not a side.
		const self = windowsOf(dragFrom).find(c => c.id === dragId);
		if (wins.length === 0 || (self && self.is_floating)) return { tag: tag, target: -1, side: "", x: 0, y: ry, w: screenW, h: screenH };
		// The window under the pointer, else the nearest one.
		let best = null, bestD = Infinity, box = null;
		for (const c of wins) {
			const b = { x: c.x - monitor.x, y: ry + c.y - monitor.y, w: c.width, h: c.height };
			const dx = Math.max(b.x - wx, 0, wx - b.x - b.w);
			const dy = Math.max(b.y - wy, 0, wy - b.y - b.h);
			const d = dx * dx + dy * dy;
			if (d < bestD) {
				bestD = d;
				best = c;
				box = b;
			}
		}
		// Which edge the pointer is nearest to, relative to the window's shape.
		const rx = (wx - box.x - box.w / 2) / (box.w / 2);
		const ry2 = (wy - box.y - box.h / 2) / (box.h / 2);
		const side = Math.abs(rx) >= Math.abs(ry2) ? (rx < 0 ? "left" : "right") : (ry2 < 0 ? "top" : "bottom");
		const h = { tag: tag, target: best.id, side: side, x: box.x, y: box.y, w: box.w, h: box.h };
		if (side === "left" || side === "right") h.w = box.w / 2;
		else h.h = box.h / 2;
		if (side === "right") h.x += box.w / 2;
		if (side === "bottom") h.y += box.h / 2;
		return h;
	}
	function dragStart(id, tag) {
		if (!open || dragging) return;
		swipeCancel();
		dragFrom = tag;
		dragId = id;
	}
	function dragEnd() {
		if (!dragging) return;
		const d = drop;
		const id = dragId, from = dragFrom;
		dragId = -1;
		if (d && !(d.tag === from && d.target < 0) && open) {
			wm.moveWindow(id, from, d.tag, d.target, d.side);
			selTag = d.tag;
			selClient = id;
			afterDrop.left = 4;
			afterDrop.restart();
		} else if (!tags.includes(selTag)) {
			selectTag(tags.includes(from) ? from : activeTag);
		}
	}
	function dragCancel() {
		if (!dragging) return;
		dragId = -1;
		if (!tags.includes(selTag)) selectTag(activeTag);
	}
	// Rows can be renumbered under us (Mango's tag_gather closes the gap a
	// moved or closed window leaves), so when the selected row is gone, follow
	// the selected window to its row, else go to the one on screen.
	onTagsChanged: {
		if (dragging || tags.includes(selTag)) return;
		const c = wm.clientById[selClient];
		const t = c ? c.tags.find(x => tags.includes(x)) : undefined;
		if (t !== undefined) selTag = t;
		else selectTag(activeTag);
	}
	// Hyprland sends no event when the other windows are resized to make
	// room, so read the layout again a few times after a drop.
	Timer {
		id: afterDrop
		property int left: 0
		interval: 350
		repeat: true
		onTriggered: {
			ov.wm.refresh();
			if (--left <= 0) stop();
		}
	}
	// Holding the window near the top or bottom edge scrolls to the next row.
	Timer {
		interval: 450
		repeat: true
		running: ov.dragging
		onTriggered: {
			const zone = panel.height * 0.12;
			const i = ov.dragRows.indexOf(ov.selTag);
			let next = i;
			if (ov.dragSY < zone) next = i - 1;
			else if (ov.dragSY > panel.height - zone) next = i + 1;
			if (next !== i && next >= 0 && next < ov.dragRows.length) ov.selectTag(ov.dragRows[next]);
		}
	}

	// 0 = looks like the desktop, 1 = fully zoomed out.
	readonly property real progress: clamp((1 - camZ) / (1 - overviewZoom), 0, 1)
	// Mango speaks compositor pixels; Qt may draw in its own (QT_SCALE_FACTOR). viewZ maps one to the other.
	readonly property real qtW: panel.screen ? panel.screen.width : screenW
	readonly property real qtH: panel.screen ? panel.screen.height : screenH
	readonly property real viewZ: camZ * qtW / screenW
	// The overlay leaves the bar's strip free, so it is smaller than the screen.
	// Where the real screen's top-left sits inside the overlay:
	readonly property real offX: barEdge === "left" ? panel.width - qtW : barEdge === "right" ? 0 : (panel.width - qtW) / 2
	readonly property real offY: barEdge === "top" ? panel.height - qtH : barEdge === "bottom" ? 0 : (panel.height - qtH) / 2
	// The camera centre: the real screen centre when zoomed in (so it looks like
	// the desktop), the free area's centre when zoomed out (like niri).
	readonly property real centreX: offX + qtW / 2 + (panel.width / 2 - offX - qtW / 2) * progress
	readonly property real centreY: offY + qtH / 2 + (panel.height / 2 - offY - qtH / 2) * progress

	// ---- actions ----
	function openOverview() {
		if (open) return;
		if (opening) return;
		opening = true;
		// Fresh positions first (Hyprland has no event for a resize).
		wm.refresh(() => {
			opening = false;
			openNow();
		});
	}
	property bool opening: false
	function openNow() {
		if (open) return;
		const m = wm.focusedMonitor;
		if (!m) return;
		monitorName = m.name;
		selTag = activeTag;
		const focused = monClients.find(c => c.is_focused && c.tags.includes(selTag));
		const first = windowsOf(selTag)[0];
		selClient = focused ? focused.id : first ? first.id : -1;

		aboveFullscreen = monClients.some(c => c.is_fullscreen && c.tags.includes(selTag));
		animate = false;
		zoomTag = selTag;
		mode = "zoomed";
		open = true;
		shown = true;
		starting = true;
		revealed = false;
		grabKeys = true;
		// Forget layers counted as open before (a bar restarted meanwhile).
		if (onHyprland) hyprland.openLayers = {};
		wm.setOverviewMode(true);
		readyDeadline = Date.now() + 300;
		readyTimer.restart();

	}

	function closeOverview(tag) {
		if (!open) return;
		swipeCancel();
		dragCancel();
		open = false;
		settled = false;
		starting = false;
		wm.setOverviewMode(false);
		zoomTag = tag ?? activeTag;
		mode = "zoomed";
		hideTimer.restart();
	}

	// Mango repeats a bind while its key is held (after ~600 ms, then every
	// 40 ms), so a held Mod+O would open and close over and over. The first
	// press counts; calls that follow close behind it are the key repeating.
	// Each repeat starts a new `qs ipc` process, so on a busy machine they
	// arrive late or in bursts (gaps up to ~900 ms seen in a VM): a call
	// within 1 s of the previous one is taken as the key still held.
	property double lastToggle: 0
	function toggle() {
		if (!onHyprland) {
			const now = Date.now(), gap = now - lastToggle;
			lastToggle = now;
			if (gap < 1000) return;
		}
		if (open) closeOverview();
		else openOverview();
	}

	function activate(tag, clientId) {
		if (!open) return;
		selTag = tag;
		selClient = clientId;
		if (clientId >= 0 && wm.clientById[clientId]) wm.focusWindow(clientId);
		else wm.viewTag(tag);
		closeOverview(tag);
	}

	function moveH(step) {
		const list = windowsOf(selTag);
		if (list.length === 0) return;
		const i = list.findIndex(c => c.id === selClient);
		selClient = list[clamp(i < 0 ? 0 : i + step, 0, list.length - 1)].id;
	}

	function selectTag(tag) {
		// Keep the same horizontal spot: pick the window nearest to the old one.
		const old = wm.clientById[selClient];
		const oldX = old && old.tags.includes(selTag) ? old.x + old.width / 2 : (monitor ? monitor.x + screenW / 2 : 0);
		selTag = tag;
		let best = null, bestD = Infinity;
		for (const c of windowsOf(tag)) {
			const d = Math.abs(c.x + c.width / 2 - oldX);
			if (d < bestD) {
				bestD = d;
				best = c;
			}
		}
		selClient = best ? best.id : -1;
	}

	function moveV(step) {
		const i = tags.indexOf(selTag);
		const next = tags[clamp(i + step, 0, tags.length - 1)];
		if (next !== undefined && next !== selTag) selectTag(next);
	}

	function jumpTag(tag) {
		if (tags.includes(tag)) selectTag(tag);
		else activate(tag, -1);
	}

	// Start zooming only once the overlay is really on screen, so the first
	// frames of the animation are not lost to mapping the window.
	function startZoom() {
		if (!starting || !open) return;
		starting = false;
		animate = true;
		mode = "overview";
		settleTimer.restart();
	}
	Timer {
		id: startTimer
		interval: 100
		onTriggered: ov.startZoom()
	}
	Connections {
		target: stage.Window.window
		// Only once the full-size overlay is on screen, not the closed pixel.
		function onFrameSwapped() { if (panel.width > 1 && ov.revealed) ov.startZoom(); }
	}

	// Until the wallpaper and the zoomed-in windows' pictures are in, the overlay
	// stays see-through (the real desktop shows), so the first frame is never a
	// blank or half-drawn screen. Gives up waiting after 300 ms.
	property real readyDeadline: 0
	function readyToShow() {
		if (wallImg.status === Image.Loading) return false;
		for (let i = 0; i < tileRep.count; i++) {
			const t = tileRep.itemAt(i);
			if (t && t.visible && t.tag === zoomTag && !t.ready) return false;
		}
		return true;
	}
	Timer {
		id: readyTimer
		interval: 16
		repeat: true
		onTriggered: {
			if (!ov.starting || !ov.open) {
				stop();
				return;
			}
			if (!ov.readyToShow() && Date.now() < ov.readyDeadline) return;
			stop();
			ov.revealed = true;
			wm.refreshPointer();
			startTimer.restart(); // fallback if no frame is reported
		}
	}
	// MANGO_OVERVIEW_DEBUG=1: log frame count and slowest frame while zooming.
	FrameAnimation {
		property real worst: 0
		property int frames: 0
		readonly property bool zooming: ov.animate && ov.shown && (ov.progress > 0.001 && ov.progress < 0.999)
		running: Quickshell.env("MANGO_OVERVIEW_DEBUG") === "1" && ov.shown
		onTriggered: {
			if (zooming) {
				worst = Math.max(worst, frameTime);
				frames++;
			} else if (frames > 0) {
				console.log("zoom frames", frames, "slowest ms", (worst * 1000).toFixed(1));
				worst = 0;
				frames = 0;
			}
		}
	}
	// Live previews copy every frame on the CPU, so they wait until the zoom is done.
	Timer {
		id: settleTimer
		interval: ov.animMs
		onTriggered: {
			if (!ov.open) return;
			ov.settled = true;
			if (ov.onHyprland) ov.grabKeys = false;
			// Check the wallpaper is still current (the shell or wallpaper may
			// have changed). Not earlier: starting a process during the zoom
			// costs frames.
			wallpaperProc.running = true;
		}
	}

	Timer {
		id: hideTimer
		interval: ov.animMs + 30
		onTriggered: {
			if (ov.open) return;
			ov.shown = false;
			ov.animate = false;
		}
	}

	Process {
		id: wallpaperProc
		command: ["sh", Quickshell.shellPath("wallpaper.sh")]
		stdout: StdioCollector {
			onStreamFinished: {
				const path = text.trim();
				if (path) ov.wallpaper = "file://" + path;
			}
		}
	}

	Component.onCompleted: {
		// No reload when our files change (a package upgrade): Quickshell can
		// crash moving windows between screens mid-reload. The new version
		// starts with the next login.
		Quickshell.watchFiles = false;
		wm.setOverviewMode(false);
		wallpaperProc.running = true;
	}

	IpcHandler {
		target: "overview"

		function toggle(): void { ov.toggle(); }
		function open(): void { ov.openOverview(); }
		function close(): void { ov.closeOverview(); }
		function left(): void { if (ov.open) ov.moveH(-1); }
		function right(): void { if (ov.open) ov.moveH(1); }
		function up(): void { if (ov.open) ov.moveV(-1); }
		function down(): void { if (ov.open) ov.moveV(1); }
		function activate(): void { ov.activate(ov.selTag, ov.selClient); }
	}

	// The blurred wallpaper again, full screen but below the windows: only the
	// bar's strip (which the overview leaves free) shows it, behind the bar.
	PanelWindow {
		visible: ov.shown && !ov.coverBar
		screen: panel.screen
		color: "transparent"
		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}
		exclusionMode: ExclusionMode.Ignore
		WlrLayershell.layer: WlrLayer.Bottom
		WlrLayershell.namespace: "mango-overview-backdrop"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
		mask: Region {}

		Backdrop {
			anchors.fill: parent
			opacity: ov.progress
			wallpaper: ov.wallpaper
		}
	}

	// While open, Hyprland's own shortcuts and touchpad gestures stand down
	// (except binds with dont_inhibit and gestures with disable_inhibit), so a
	// three-finger swipe drags the overview and doesn't also switch the
	// workspace behind it. Only counts while the overview has the keyboard.
	ShortcutInhibitor {
		window: panel
		enabled: ov.onHyprland && ov.shown
	}

	PanelWindow {
		id: panel

		// Always mapped, shrunk to one see-through pixel while closed. The
		// compositor stacks surfaces of one layer by age, so a shell started
		// after us (say, after a shell switch) keeps its always-mapped popups
		// (DMS's middle island) above the overview instead of under it.
		visible: true
		screen: {
			const screens = Quickshell.screens;
			for (let i = 0; i < screens.length; i++) if (screens[i].name === ov.monitorName) return screens[i];
			return screens[0];
		}
		color: "transparent"
		anchors {
			top: true
			bottom: ov.shown
			left: true
			right: ov.shown
		}
		implicitWidth: 1
		implicitHeight: 1
		mask: ov.shown ? null : noInput
		Region { id: noInput }
		// Normal with a zero zone: the compositor fits us inside other panels' zones.
		// Over a fullscreen window the bar is hidden but keeps its zone, so
		// cover the whole screen or the window peeks through the bar's strip.
		// Normal while closed too: moving to another screen makes a new surface,
		// and Hyprland only fits a surface into the zones when it is first mapped.
		exclusionMode: ov.coverBar || ov.aboveFullscreen ? ExclusionMode.Ignore : ExclusionMode.Normal
		exclusiveZone: 0
		// The bar's layer: popups opened from the bar map after us, so they show on top.
		WlrLayershell.layer: ov.aboveFullscreen ? WlrLayer.Overlay : WlrLayer.Top
		WlrLayershell.namespace: "mango-overview"
		// Keep focus until hidden: handing it back mid-zoom makes the compositor redo work and stutter.
		WlrLayershell.keyboardFocus: !ov.shown ? WlrKeyboardFocus.None : ov.grabKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

		Item {
			id: stage
			anchors.fill: parent
			visible: ov.shown
			opacity: ov.starting && !ov.revealed ? 0 : 1
			focus: true

			SwipeTracker {
				onBegan: fingers => ov.swipeBegin(fingers)
				onMoved: (dx, dy) => ov.swipeMove(dx, dy)
				onEnded: ov.swipeEnd()
			}

			// The plain wallpaper, always solid, so the real windows (already
			// moved back by the compositor) never show through while zooming in.
			Rectangle {
				anchors.fill: parent
				color: "black"
			}
			Image {
				id: wallImg
				x: ov.offX
				y: ov.offY
				width: ov.qtW
				height: ov.qtH
				source: ov.wallpaper
				fillMode: Image.PreserveAspectCrop
				sourceSize: Qt.size(ov.qtW, ov.qtH)
				asynchronous: true
			}
			// Blurred wallpaper on top, fading in as we zoom out.
			Backdrop {
				anchors.fill: parent
				opacity: ov.progress
				wallpaper: ov.wallpaper
				screenX: ov.offX
				screenY: ov.offY
				screenW: ov.qtW
				screenH: ov.qtH
			}

			// Click on empty space: go back.
			MouseArea {
				anchors.fill: parent
				enabled: ov.open
				onClicked: ov.closeOverview()
			}

			// The zoomable world: tag cards and windows at real pixel size.
			Item {
				id: world
				x: ov.centreX - ov.camX * ov.viewZ
				y: ov.centreY - ov.camY * ov.viewZ
				scale: ov.viewZ
				transformOrigin: Item.TopLeft

				Repeater {
					model: ScriptModel {
						values: ov.tags
					}

					delegate: Item {
						id: card
						required property int modelData
						readonly property bool selected: ov.selTag === modelData
						readonly property real px: 1 / ov.viewZ

						x: 0
						y: ov.rowY(modelData)
						width: ov.screenW
						height: ov.screenH
						opacity: ov.progress
						visible: opacity > 0

						Behavior on y { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }

						// The tag's wallpaper, with rounded corners.
						Image {
							id: cardWall
							anchors.fill: parent
							source: ov.wallpaper
							fillMode: Image.PreserveAspectCrop
							sourceSize: Qt.size(panel.width, panel.height)
							asynchronous: true
							visible: false
						}
						Rectangle {
							id: cardMask
							anchors.fill: parent
							radius: 18 * card.px
							visible: false
							layer.enabled: true
						}
						MultiEffect {
							anchors.fill: parent
							source: cardWall
							maskEnabled: true
							maskSource: cardMask
							maskThresholdMin: 0.5
							maskSpreadAtMin: 1
							brightness: card.selected ? 0 : -0.25
							Behavior on brightness { NumberAnimation { duration: 150 } }
						}
						Rectangle {
							anchors.fill: parent
							anchors.margins: -2 * card.px
							radius: 20 * card.px
							color: "transparent"
							border.width: 2 * card.px
							border.color: card.selected ? Qt.alpha(ov.accent, 0.8) : Qt.rgba(1, 1, 1, 0.15)
						}

						// Tag number above the card.
						Text {
							anchors.left: parent.left
							anchors.bottom: parent.top
							anchors.bottomMargin: 10 * card.px
							text: ov.wm.tagName(card.modelData)
							color: card.selected ? ov.accent : Qt.rgba(1, 1, 1, 0.7)
							// Fixed size, scaled: a changing font size re-lays out the text every frame.
							font.pixelSize: 22
							scale: card.px
							transformOrigin: Item.BottomLeft
							font.bold: true
						}

						MouseArea {
							anchors.fill: parent
							enabled: ov.open
							onClicked: ov.activate(card.modelData, -1)
						}
					}
				}

				// The new row offered while dragging.
				Rectangle {
					readonly property real px: 1 / ov.viewZ
					visible: ov.dragging && ov.newTag > 0
					x: 0
					y: ov.rowY(ov.newTag)
					width: ov.screenW
					height: ov.screenH
					radius: 18 * px
					color: Qt.rgba(1, 1, 1, 0.05)
					border.width: 2 * px
					border.color: Qt.rgba(1, 1, 1, 0.3)
					opacity: ov.progress

					Text {
						anchors.centerIn: parent
						text: "+"
						color: Qt.rgba(1, 1, 1, 0.5)
						font.pixelSize: 96
						scale: parent.px
					}
				}

				// Where the dragged window will land.
				Rectangle {
					readonly property real px: 1 / ov.viewZ
					readonly property var d: ov.drop
					visible: d !== null && !(d.tag === ov.dragFrom && d.target < 0)
					z: 5
					x: d ? d.x : 0
					y: d ? d.y : 0
					width: d ? d.w : 0
					height: d ? d.h : 0
					radius: 14 * px
					color: Qt.alpha(ov.accent, 0.25)
					border.width: 4 * px
					border.color: ov.accent
					Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
					Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
					Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
					Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
				}

				Repeater {
					id: tileRep
					model: ScriptModel {
						values: ov.tileKeys
					}

					delegate: WindowTile {
						ctl: ov
					}
				}
			}

			// Title of the selected window.
			Rectangle {
				readonly property var client: ov.wm.clientById[ov.selClient] ?? null
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.bottom: parent.bottom
				anchors.bottomMargin: 36
				width: Math.min(titleText.implicitWidth + 40, parent.width * 0.6)
				height: 40
				radius: 20
				color: Qt.rgba(0, 0, 0, 0.55)
				opacity: ov.progress
				visible: client !== null && opacity > 0

				Text {
					id: titleText
					anchors.centerIn: parent
					width: Math.min(implicitWidth, parent.parent.width * 0.6 - 40)
					elide: Text.ElideRight
					text: parent.client ? parent.client.title : ""
					color: "white"
					font.pixelSize: 15
				}
			}

			// Mouse wheel and touchpad: vertical = tags, horizontal = windows.
			// On top, but takes no clicks, so windows stay clickable.
			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.NoButton
				enabled: ov.open
				property real accX: 0
				property real accY: 0

				onWheel: event => {
					const touch = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
					const dx = touch ? event.pixelDelta.x : event.angleDelta.x / 120 * 80;
					const dy = touch ? event.pixelDelta.y : event.angleDelta.y / 120 * 80;
					const step = 80;
					accX += dx;
					accY += dy;
					// Use one axis at a time so a diagonal swipe doesn't do both.
					if (Math.abs(accY) >= step && Math.abs(accY) >= Math.abs(accX)) {
						ov.moveV(accY < 0 ? 1 : -1);
						accX = 0;
						accY = 0;
					} else if (Math.abs(accX) >= step) {
						ov.moveH(accX < 0 ? 1 : -1);
						accX = 0;
						accY = 0;
					}
				}
			}

			Keys.onPressed: event => {
				if (!ov.open) return;
				const k = event.key;
				if (k === Qt.Key_Escape) ov.closeOverview();
				else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ov.activate(ov.selTag, ov.selClient);
				else if (k === Qt.Key_Left || k === Qt.Key_A || k === Qt.Key_H) ov.moveH(-1);
				else if (k === Qt.Key_Right || k === Qt.Key_D || k === Qt.Key_L) ov.moveH(1);
				else if (k === Qt.Key_Up || k === Qt.Key_W || k === Qt.Key_K) ov.moveV(-1);
				else if (k === Qt.Key_Down || k === Qt.Key_S || k === Qt.Key_J) ov.moveV(1);
				else if (k >= Qt.Key_1 && k <= Qt.Key_9) ov.jumpTag(k - Qt.Key_0);
				else return;
				event.accepted = true;
			}
		}
	}
}
