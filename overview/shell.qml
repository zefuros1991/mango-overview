//@ pragma UseQApplication
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// niri-style overview for Mango: every tag (workspace) as a card stacked
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
	property alias mango: mango
	property bool open: false     // overview accepts input
	property bool shown: false    // overlay is on screen
	property bool animate: false  // camera/tile animations on
	property bool settled: false  // fully zoomed out: previews may go live
	property bool starting: false // waiting for the overlay's first frame
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

	Mango {
		id: mango
	}

	// ---- derived data ----
	readonly property var monitor: {
		for (const m of mango.monitors) if (m.name === monitorName) return m;
		return null;
	}
	readonly property real screenW: monitor ? monitor.width : 1
	readonly property real screenH: monitor ? monitor.height : 1
	readonly property real rowGap: screenH * 0.1
	readonly property var monClients: mango.clients.filter(c => c.monitor === monitorName)
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
	function rowY(tag) {
		return Math.max(0, tags.indexOf(tag)) * (screenH + rowGap);
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
	property real camY: targetCamera.y
	Behavior on camZ { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }
	Behavior on camX { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }
	Behavior on camY { enabled: ov.animate; NumberAnimation { duration: ov.animMs; easing.type: Easing.OutCubic } }
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
		const m = mango.focusedMonitor;
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
		mango.dispatch("setkeymode,overview");
		startTimer.restart(); // fallback if no frame is reported

	}

	function closeOverview(tag) {
		if (!open) return;
		open = false;
		settled = false;
		starting = false;
		mango.dispatch("setkeymode,default");
		zoomTag = tag ?? activeTag;
		mode = "zoomed";
		hideTimer.restart();
	}

	function toggle() {
		if (open) closeOverview();
		else openOverview();
	}

	function activate(tag, clientId) {
		if (!open) return;
		selTag = tag;
		selClient = clientId;
		if (clientId >= 0 && mango.clientById[clientId]) mango.dispatch("focusid", clientId);
		else mango.dispatch("view," + tag);
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
		const old = mango.clientById[selClient];
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
		function onFrameSwapped() { if (panel.width > 1) ov.startZoom(); }
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
		mango.dispatch("setkeymode,default");
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
		exclusionMode: ov.coverBar || !ov.shown ? ExclusionMode.Ignore : ExclusionMode.Normal
		exclusiveZone: 0
		// The bar's layer: popups opened from the bar map after us, so they show on top.
		WlrLayershell.layer: ov.aboveFullscreen ? WlrLayer.Overlay : WlrLayer.Top
		WlrLayershell.namespace: "mango-overview"
		// Keep focus until hidden: handing it back mid-zoom makes the compositor redo work and stutter.
		WlrLayershell.keyboardFocus: ov.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		Item {
			id: stage
			anchors.fill: parent
			visible: ov.shown
			focus: true

			// The plain wallpaper, always solid, so the real windows (already
			// moved back by the compositor) never show through while zooming in.
			Rectangle {
				anchors.fill: parent
				color: "black"
			}
			Image {
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
							text: card.modelData
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

				Repeater {
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
				readonly property var client: mango.clientById[ov.selClient] ?? null
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
