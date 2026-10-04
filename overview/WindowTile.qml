import QtQuick
import Quickshell
import Quickshell.Widgets
import MangoOverview.Capture

// One window inside the zoomable world. Coordinates are real screen pixels;
// the world's scale does the zooming.
Item {
	id: tile

	required property var ctl
	// "<tag>:<client id>"
	required property string modelData

	readonly property int tag: parseInt(modelData.split(":")[0])
	readonly property int clientId: parseInt(modelData.split(":")[1])
	readonly property var client: ctl.wm.clientById[clientId] ?? null
	readonly property bool selected: ctl.selClient === clientId && ctl.selTag === tag
	// While the overview opens, the zoomed-in windows wait for a new picture,
	// so the first frame never shows an old one (or none).
	property bool fresh: false
	readonly property bool ready: fresh
	Connections {
		target: tile.ctl
		function onStartingChanged() {
			if (!tile.ctl.starting) return;
			tile.fresh = false;
			if (tile.tag === tile.ctl.zoomTag) capture.captureFrame();
		}
	}
	readonly property real px: 1 / ctl.viewZ // one screen pixel, in world units
	readonly property var entry: client ? DesktopEntries.heuristicLookup(client.appid) : null
	// An app with no desktop file still gets an icon: its own app id if the
	// theme has one, else the generic one, else none at all. An unknown name
	// would draw the "missing icon" checkerboard.
	readonly property string iconSource: Quickshell.iconPath(entry?.icon ?? "", true)
		|| Quickshell.iconPath(client?.appid ?? "", true)
		|| Quickshell.iconPath("application-x-executable", true)

	// Held and dragged: the window follows the pointer, a little smaller.
	readonly property bool dragging: ctl.dragId === clientId && ctl.dragFrom === tag
	property real grabX: 0 // where the window was grabbed, in its own pixels
	property real grabY: 0

	visible: client !== null && ctl.monitor !== null
	x: dragging ? ctl.dragWX - grabX : client && ctl.monitor ? client.x - ctl.monitor.x : 0
	y: dragging ? ctl.dragWY - grabY : client && ctl.monitor ? ctl.rowY(tag) + client.y - ctl.monitor.y : 0
	width: client ? client.width : 0
	height: client ? client.height : 0
	z: dragging ? 10 : client && client.is_floating ? 2 : 1
	opacity: dragging ? 0.85 : 1
	transform: Scale {
		origin.x: tile.grabX
		origin.y: tile.grabY
		xScale: tile.dragging ? 0.8 : 1
		yScale: xScale
		Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
	}

	Behavior on x { enabled: ctl.animate && !tile.dragging; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }
	Behavior on y { enabled: ctl.animate && !tile.dragging; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }
	Behavior on width { enabled: ctl.animate; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }
	Behavior on height { enabled: ctl.animate; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }

	// Shown until the first frame arrives.
	Rectangle {
		anchors.fill: parent
		visible: !capture.hasContent
		color: Qt.rgba(0.1, 0.1, 0.12, 0.85)
		radius: 12 * tile.px

		IconImage {
			anchors.centerIn: parent
			// Fixed size, scaled: resizing an icon every frame redraws it every frame.
			implicitSize: 96
			scale: tile.px
			visible: source !== ""
			source: tile.iconSource
		}
	}

	// A window that moves or changes size while the overview is open (after a
	// drop) can stop sending pictures, and so can one that turns up in a new
	// row: start its capture again once it has settled.
	property bool paused: false
	readonly property string shape: client ? [tag, client.width, client.height].join() : ""
	onShapeChanged: if (ctl.settled) recapture.restart()
	Component.onCompleted: if (ctl.settled) recapture.restart()
	Timer {
		id: recapture
		interval: 300
		onTriggered: {
			tile.paused = true;
			tile.paused = false;
		}
	}

	WindowCapture {
		id: capture
		anchors.fill: parent
		identifier: tile.client ? tile.client.foreign_toplevel_id : ""
		live: tile.ctl.settled && !tile.paused
		onFrameArrived: tile.fresh = true
	}

	// Selection / hover outline, drawn just outside the window.
	Rectangle {
		anchors.fill: parent
		anchors.margins: -4 * tile.px
		color: "transparent"
		radius: 10 * tile.px
		border.width: 3 * tile.px
		border.color: tile.selected ? tile.ctl.accent : Qt.rgba(1, 1, 1, 0.6)
		opacity: tile.ctl.progress * (tile.selected ? 1 : mouse.containsMouse ? 0.6 : 0)
		Behavior on opacity { NumberAnimation { duration: 120 } }
	}

	// App icon badge on the bottom edge.
	IconImage {
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.bottom
		implicitSize: 40
		scale: tile.px
		opacity: tile.ctl.progress
		visible: opacity > 0 && source !== ""
		source: tile.iconSource
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		enabled: tile.ctl.open
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton
		// Keep the pointer while dragging, even off the window.
		preventStealing: true
		property point pressAt // in overlay pixels
		property bool dragged: false
		onPressed: event => {
			dragged = false;
			if (event.button !== Qt.LeftButton) return;
			pressAt = mapToItem(null, event.x, event.y);
			tile.grabX = event.x;
			tile.grabY = event.y;
		}
		onPositionChanged: event => {
			if (!(event.buttons & Qt.LeftButton)) return;
			const p = mapToItem(null, event.x, event.y);
			if (!dragged) {
				// A small wobble is still a click.
				if (Math.hypot(p.x - pressAt.x, p.y - pressAt.y) < 8) return;
				dragged = true;
				tile.ctl.dragSX = p.x;
				tile.ctl.dragSY = p.y;
				tile.ctl.dragStart(tile.clientId, tile.tag);
			}
			tile.ctl.dragSX = p.x;
			tile.ctl.dragSY = p.y;
		}
		onReleased: event => {
			if (dragged && event.button === Qt.LeftButton) tile.ctl.dragEnd();
		}
		onCanceled: tile.ctl.dragCancel()
		onClicked: event => {
			if (dragged) return;
			if (event.button === Qt.MiddleButton) tile.ctl.wm.closeWindow(tile.clientId);
			else tile.ctl.activate(tile.tag, tile.clientId);
		}
	}
}
