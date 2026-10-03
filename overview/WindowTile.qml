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
	readonly property var client: ctl.mango.clientById[clientId] ?? null
	readonly property bool selected: ctl.selClient === clientId && ctl.selTag === tag
	readonly property real px: 1 / ctl.viewZ // one screen pixel, in world units
	readonly property var entry: client ? DesktopEntries.heuristicLookup(client.appid) : null

	visible: client !== null && ctl.monitor !== null
	x: client && ctl.monitor ? client.x - ctl.monitor.x : 0
	y: client && ctl.monitor ? ctl.rowY(tag) + client.y - ctl.monitor.y : 0
	width: client ? client.width : 0
	height: client ? client.height : 0
	z: client && client.is_floating ? 2 : 1

	Behavior on x { enabled: ctl.animate; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }
	Behavior on y { enabled: ctl.animate; NumberAnimation { duration: ctl.animMs; easing.type: Easing.OutCubic } }
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
			source: Quickshell.iconPath(tile.entry?.icon ?? "", "application-x-executable")
		}
	}

	WindowCapture {
		id: capture
		anchors.fill: parent
		identifier: tile.client ? tile.client.foreign_toplevel_id : ""
		live: tile.ctl.settled
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
		visible: opacity > 0
		source: Quickshell.iconPath(tile.entry?.icon ?? "", "application-x-executable")
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		enabled: tile.ctl.open
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton
		onClicked: event => {
			if (event.button === Qt.MiddleButton) tile.ctl.mango.dispatch("killclient", tile.clientId);
			else tile.ctl.activate(tile.tag, tile.clientId);
		}
	}
}
