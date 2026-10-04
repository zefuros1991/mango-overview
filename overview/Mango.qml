import QtQuick
import Quickshell
import Quickshell.Io

// Live view of Mango's windows and monitors, kept fresh by `mmsg watch`.
Scope {
	id: mango

	// Off when running on another compositor.
	property bool active: true
	property var clients: []
	property var monitors: []

	readonly property var focusedMonitor: {
		for (const m of monitors) if (m.active) return m;
		return monitors.length > 0 ? monitors[0] : null;
	}

	readonly property var clientById: {
		const map = {};
		for (const c of clients) map[c.id] = c;
		return map;
	}

	// `mmsg dispatch <command> [client,<id>]`
	function dispatch(command, clientId) {
		const args = ["mmsg", "dispatch", command];
		if (clientId !== undefined) args.push("client," + clientId);
		Quickshell.execDetached(args);
	}

	// ---- actions (the same names as Hyprland.qml) ----
	function focusWindow(id) { dispatch("focusid", id); }
	function viewTag(tag) { dispatch("view," + tag); }
	function closeWindow(id) { dispatch("killclient", id); }
	// Tags 1..9.
	readonly property int maxTag: 9
	// Drop window `id` on tag `to`, next to window `targetId` on its `side`
	// (left/right/top/bottom), or anywhere if `targetId` is -1.
	// Mango has no "put it here" command, so the window is walked there one
	// step at a time: swap with the next column, leave or join a column
	// (stack), swap inside a column. Each step waits for the new layout.
	function moveWindow(id, from, to, targetId, side) {
		const c = clientById[id];
		if (!c) return;
		if (to !== from) dispatch("tag," + to, id); // also shows the tag
		else dispatch("view," + to);
		if (targetId < 0 || c.is_floating) return tidyLater(id);
		walk = { id: id, tag: to, target: targetId, side: side, steps: 0, wait: 0, stuck: 0, sig: "" };
		walkTimer.restart();
	}
	property var walk: null
	// The tiled windows of the dragged window's tag, as columns left to right,
	// each column top to bottom.
	function columnsOf(w) {
		const d = clientById[w.id];
		if (!d) return null;
		const list = clients.filter(c => c.tags.includes(w.tag) && c.monitor === d.monitor && !c.is_floating);
		const xs = [...new Set(list.map(c => c.x))].sort((a, b) => a - b);
		return xs.map(x => list.filter(c => c.x === x).sort((a, b) => a.y - b.y).map(c => c.id));
	}
	// The next step, "" when the window is in place, null if the layout
	// doesn't show both windows on the tag yet.
	function nextStep(w) {
		const cols = columnsOf(w);
		if (!cols) return null;
		const colOf = id => cols.findIndex(col => col.includes(id));
		const dc = colOf(w.id), tc = colOf(w.target);
		if (dc < 0 || tc < 0) return null;
		const alone = cols[dc].length === 1;
		if (w.side === "left" || w.side === "right") {
			const goal = w.side === "left" ? tc - 1 : tc + 1;
			if (!alone) return "scroller_stack," + (dc > tc || (dc === tc && w.side === "right") ? "right" : "left");
			if (dc === goal) return "";
			return "exchange_client," + (dc < goal ? "right" : "left");
		}
		// top / bottom: into the target's column, just above or below it.
		if (dc === tc) {
			const col = cols[dc], di = col.indexOf(w.id), ti = col.indexOf(w.target);
			const goal = w.side === "top" ? ti - 1 : ti + 1;
			if (di === goal) return "";
			return "exchange_stack_client," + (di > goal ? "prev" : "next");
		}
		if (!alone) return "scroller_stack," + (dc < tc ? "right" : "left");
		if (dc === tc - 1) return "scroller_stack,right";
		if (dc === tc + 1) return "scroller_stack,left";
		return "exchange_client," + (dc < tc ? "right" : "left");
	}
	Timer {
		id: walkTimer
		interval: 120
		repeat: true
		onTriggered: {
			const w = mango.walk;
			const done = () => {
				if (w) mango.tidyLater(w.id);
				mango.walk = null;
				walkTimer.stop();
			};
			if (!w || w.steps > 30) return done();
			const sig = JSON.stringify(mango.columnsOf(w));
			// Give the last step time to show up in the layout.
			if (w.steps > 0 && sig === w.sig && w.wait++ < 6) return;
			const step = mango.nextStep(w);
			if (step === null) {
				if (w.wait++ < 10) return;
				return done();
			}
			if (step === "") return done();
			// A step that changes nothing, again and again: stop trying.
			if (w.steps > 0 && sig === w.sig && ++w.stuck > 2) return done();
			w.sig = sig;
			w.wait = 0;
			w.steps++;
			mango.dispatch(step, w.id);
		}
	}

	// After a move Mango can leave the row half scrolled, a window hanging off
	// the left edge. Line it back up the way Mod+Left/Right would: focus the
	// moved window's neighbour, then the moved window again, so the pair fills
	// the screen. (zexos-scroll-snap does the same after a sideways swipe.)
	property int tidyId: -1
	function tidyLater(id) {
		tidyId = id;
		tidyTimer.restart();
	}
	Timer {
		id: tidyTimer
		interval: 150
		onTriggered: mango.tidy(mango.tidyId)
	}
	function tidy(id) {
		const me = clientById[id];
		if (!me || me.is_floating || me.is_fullscreen) return;
		const mon = monitors.find(m => m.name === me.monitor);
		if (!mon || mon.layout_symbol !== "S") return; // only the scroller layout
		const strip = clients.filter(c => c.monitor === me.monitor && !c.is_floating && !c.is_fullscreen
			&& !c.is_minimized && c.tags.some(t => me.tags.includes(t)));
		if (strip.length < 2) return;
		const edge = 20, slack = 4, gap = 9; // Mango's scroller defaults
		const left = mon.x + edge, right = mon.x + mon.width - edge;
		if (strip.some(c => Math.abs(c.x - left) <= slack) && strip.some(c => Math.abs(c.x + c.width - right) <= slack)) return;
		// Columns left to right; the moved window's neighbours.
		const xs = [...new Set(strip.map(c => c.x))].sort((a, b) => a - b);
		const i = xs.indexOf(me.x);
		const shown = c => Math.max(0, Math.min(c.x + c.width, right) - Math.max(c.x, left));
		const near = [xs[i - 1], xs[i + 1]].filter(x => x !== undefined)
			.map(x => strip.find(c => c.x === x))
			.filter(c => me.width + c.width + gap <= right - left + slack);
		if (near.length === 0) return;
		const n = near.reduce((a, b) => shown(b) > shown(a) ? b : a);
		// One shell, so the two focus changes run in this order.
		Quickshell.execDetached(["sh", "-c", "mmsg dispatch focusid client," + n.id + "; mmsg dispatch focusid client," + id]);
	}

	// The "overview" keymode holds the few keys that must still work while
	// the overview is open; every other compositor key is off.
	function setOverviewMode(on) { dispatch("setkeymode," + (on ? "overview" : "default")); }
	function tagName(tag) { return String(tag); }
	// Mango only picks the surface under the pointer when the pointer moves
	// or the layout is re-arranged, not when our layer grows to full screen,
	// so a swipe right after opening would still go to the window below.
	// Toggling the border twice re-arranges (nothing moves) and re-picks it.
	function refreshPointer() {
		dispatch("toggle_render_border");
		dispatch("toggle_render_border");
	}
	// Mango sends every change, so the data is always fresh.
	function refresh(done) { if (done) done(); }

	function parse(line) {
		try {
			return JSON.parse(line);
		} catch (e) {
			return null;
		}
	}

	Process {
		id: clientWatch
		running: mango.active
		command: ["mmsg", "watch", "all-clients"]
		stdout: SplitParser {
			onRead: line => {
				const data = mango.parse(line);
				if (data && data.clients) mango.clients = data.clients;
			}
		}
		onRunningChanged: if (!running && mango.active) restartTimer.start()
	}

	Process {
		id: monitorWatch
		running: mango.active
		command: ["mmsg", "watch", "all-monitors"]
		stdout: SplitParser {
			onRead: line => {
				const data = mango.parse(line);
				if (data && data.monitors) mango.monitors = data.monitors;
			}
		}
		onRunningChanged: if (!running && mango.active) restartTimer.start()
	}

	// If mango restarts (or mmsg dies), reconnect.
	Timer {
		id: restartTimer
		interval: 1000
		onTriggered: {
			if (!mango.active) return;
			clientWatch.running = true;
			monitorWatch.running = true;
		}
	}
}
