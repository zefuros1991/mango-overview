import QtQuick
import Quickshell
import Quickshell.Io

// Live view of Mango's windows and monitors, kept fresh by `mmsg watch`.
Scope {
	id: mango

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

	function parse(line) {
		try {
			return JSON.parse(line);
		} catch (e) {
			return null;
		}
	}

	Process {
		id: clientWatch
		running: true
		command: ["mmsg", "watch", "all-clients"]
		stdout: SplitParser {
			onRead: line => {
				const data = mango.parse(line);
				if (data && data.clients) mango.clients = data.clients;
			}
		}
		onRunningChanged: if (!running) restartTimer.start()
	}

	Process {
		id: monitorWatch
		running: true
		command: ["mmsg", "watch", "all-monitors"]
		stdout: SplitParser {
			onRead: line => {
				const data = mango.parse(line);
				if (data && data.monitors) mango.monitors = data.monitors;
			}
		}
		onRunningChanged: if (!running) restartTimer.start()
	}

	// If mango restarts (or mmsg dies), reconnect.
	Timer {
		id: restartTimer
		interval: 1000
		onTriggered: {
			clientWatch.running = true;
			monitorWatch.running = true;
		}
	}
}
