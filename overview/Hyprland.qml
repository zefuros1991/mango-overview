import QtQuick
import Quickshell
import Quickshell.Io

// Live view of Hyprland's windows and monitors, in the same shape as
// Mango.qml, so the overview doesn't care which compositor it runs on.
// Hyprland's event socket says when something changed; `hyprctl -j` then
// reads the whole state in one go.
Scope {
	id: wm

	// Off when running on another compositor.
	property bool active: true
	property var clients: []
	property var monitors: []
	property var workspaceNames: ({})

	// A layer surface (a bar popup, say) went away.
	signal layerClosed(string namespace)
	// Hyprland gave the keyboard to a window.
	signal windowFocused()
	// Shell layers (popups, launchers) opened since we started and still open.
	property var openLayers: ({})
	readonly property bool popupOpen: Object.keys(openLayers).length > 0

	readonly property var focusedMonitor: {
		for (const m of monitors) if (m.active) return m;
		return monitors.length > 0 ? monitors[0] : null;
	}

	readonly property var clientById: {
		const map = {};
		for (const c of clients) map[c.id] = c;
		return map;
	}

	readonly property string socketDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

	// Window addresses are too big for an int, so each gets a small number
	// for its life. The tiles and the selection use that number.
	property var idOf: ({})
	property int nextId: 1
	function idFor(address) {
		let id = idOf[address];
		if (id === undefined) {
			id = nextId++;
			idOf[address] = id;
		}
		return id;
	}
	function addressOf(id) {
		const c = clientById[id];
		return c ? c.address : "";
	}

	// ---- actions (the same names as Mango.qml) ----
	// Hyprland 0.56 with a Lua config: `hyprctl dispatch` runs Lua.
	function lua(code) {
		if (!active) return;
		Quickshell.execDetached(["hyprctl", "dispatch", code]);
	}
	function focusWindow(id) {
		const a = addressOf(id);
		if (a) lua('hl.dsp.focus({ window = "address:' + a + '" })');
	}
	function viewTag(tag) {
		lua("hl.dsp.focus({ workspace = " + tag + " })");
	}
	function closeWindow(id) {
		const a = addressOf(id);
		if (a) lua('hl.dsp.window.close({ window = "address:' + a + '" })');
	}
	// Workspaces 1..99 can be made by moving a window there.
	readonly property int maxTag: 99
	// Several Lua dispatches in one go, in order.
	function luaBatch(list) {
		if (!active || list.length === 0) return;
		Quickshell.execDetached(["hyprctl", "--batch", list.map(c => "dispatch " + c).join(" ; ")]);
	}
	// Drop window `id` on workspace `to`, next to window `targetId` on its
	// `side` (left/right/top/bottom), or anywhere if `targetId` is -1.
	// Dwindle splits the focused window, and "preselect" picks the side of
	// that split. So: lift the window out (to a hidden special workspace, so
	// this also works within one workspace), focus the target, preselect the
	// side and put the window back. Then focus it, like after a niri drop.
	function moveWindow(id, from, to, targetId, side) {
		const a = addressOf(id), t = addressOf(targetId);
		if (!a) return;
		const move = ws => 'hl.dsp.window.move({ workspace = ' + ws + ', follow = false, window = "address:' + a + '" })';
		const c = clientById[id];
		if (!t || (c && c.is_floating)) {
			if (to !== from) luaBatch([move(to), 'hl.dsp.focus({ window = "address:' + a + '" })']);
			return;
		}
		const dir = { left: "l", right: "r", top: "u", bottom: "d" }[side] ?? "r";
		luaBatch([
			move('"special:mango-overview"'),
			'hl.dsp.focus({ window = "address:' + t + '" })',
			'hl.dsp.layout("preselect ' + dir + '")',
			move(to),
			'hl.dsp.focus({ window = "address:' + a + '" })'
		]);
	}
	// The "overview" submap holds the few keys that must still work while
	// the overview is open; every other compositor key is off.
	function setOverviewMode(on) {
		lua('hl.dsp.submap("' + (on ? "overview" : "reset") + '")');
	}
	// Hyprland re-picks the surface under the pointer by itself.
	function refreshPointer() {}
	function tagName(tag) {
		return workspaceNames[tag] ?? String(tag);
	}

	// Read the state now, then call `done`. Hyprland sends no event when a
	// window is only resized, so the overview asks for fresh data on open.
	property var waiting: []
	function refresh(done) {
		if (done) waiting.push(done);
		if (!query.running) query.running = true;
		else again = true;
	}
	property bool again: false

	function apply(text) {
		const parts = text.split("\n\n\n");
		if (parts.length < 3) return false;
		let cl, mo, ws;
		try {
			cl = JSON.parse(parts[0]);
			mo = JSON.parse(parts[1]);
			ws = JSON.parse(parts[2]);
		} catch (e) {
			return false;
		}

		const names = {};
		for (const w of ws) if (w.id > 0 || !w.name.startsWith("special")) names[w.id] = w.name;

		const monName = {};
		const mons = [];
		for (const m of mo) {
			monName[m.id] = m.name;
			// hyprctl gives the mode in real pixels; windows are in scaled ones.
			const turned = m.transform % 2 === 1;
			const w = Math.round((turned ? m.height : m.width) / m.scale);
			const h = Math.round((turned ? m.width : m.height) / m.scale);
			mons.push({
				name: m.name,
				x: m.x,
				y: m.y,
				width: w,
				height: h,
				scale: m.scale,
				active: m.focused,
				tags: [{ index: m.activeWorkspace.id, is_active: true }]
			});
		}

		const list = [];
		const seen = {};
		for (const c of cl) {
			// Not on a normal workspace (special or none), or a hidden tab of a group.
			if (!c.mapped || c.hidden || !c.workspace || c.workspace.id <= 0 && (c.workspace.name || "").startsWith("special")) continue;
			if (c.workspace.id === -1) continue;
			const id = idFor(c.address);
			seen[c.address] = true;
			list.push({
				id: id,
				address: c.address,
				foreign_toplevel_id: c.stableId,
				tags: [c.workspace.id],
				monitor: monName[c.monitor] ?? "",
				x: c.at[0],
				y: c.at[1],
				width: c.size[0],
				height: c.size[1],
				is_floating: c.floating,
				// fullscreen is a bit mask: 1 maximized, 2 fullscreen.
				is_fullscreen: (c.fullscreen & 2) !== 0,
				is_focused: c.focusHistoryID === 0,
				appid: c.class || c.initialClass || "",
				title: c.title
			});
		}
		// Forget windows that are gone.
		const ids = {};
		for (const a in idOf) if (seen[a]) ids[a] = idOf[a];
		idOf = ids;

		workspaceNames = names;
		monitors = mons;
		clients = list;
		return true;
	}

	Process {
		id: query
		command: ["hyprctl", "-j", "--batch", "clients;monitors;workspaces"]
		stdout: StdioCollector {
			onStreamFinished: wm.apply(text)
		}
		onRunningChanged: {
			if (running) return;
			if (wm.again) {
				wm.again = false;
				running = true;
				return;
			}
			const cbs = wm.waiting;
			wm.waiting = [];
			for (const cb of cbs) cb();
		}
	}

	// Many events come in bursts (a window opening sends several), so wait a moment.
	Timer {
		id: debounce
		interval: 40
		onTriggered: wm.refresh()
	}

	Socket {
		id: events
		path: wm.socketDir + "/.socket2.sock"
		connected: wm.active
		parser: SplitParser {
			onRead: line => {
				// Layers are not windows: nothing to re-read.
				if (line.startsWith("closelayer>>") || line.startsWith("openlayer>>")) {
					const opened = line.startsWith("o");
					const ns = line.slice(line.indexOf(">>") + 2);
					if (ns.startsWith("mango-overview")) return;
					const layers = Object.assign({}, wm.openLayers);
					const n = (layers[ns] || 0) + (opened ? 1 : -1);
					if (n > 0) layers[ns] = n; else delete layers[ns];
					wm.openLayers = layers;
					if (!opened) wm.layerClosed(ns);
					return;
				}
				if (line.startsWith("activewindowv2>>") && line.length > 16) wm.windowFocused();
				// Title changes are frequent and only the title pill shows them.
				if (line.startsWith("activewindow>>") || line.startsWith("windowtitle>>")) {
					if (!debounce.running) debounce.start();
					return;
				}
				debounce.restart();
			}
		}
		onConnectedChanged: {
			if (!wm.active) return;
			if (!connected) reconnect.start();
			else wm.refresh();
		}
	}

	// If Hyprland restarts, or on `hyprctl reload`, reconnect.
	Timer {
		id: reconnect
		interval: 1000
		onTriggered: events.connected = true
	}

	Component.onCompleted: if (active) refresh()
}
