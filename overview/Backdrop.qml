import QtQuick
import QtQuick.Effects
import Quickshell

// The blurred wallpaper behind the overview, laid out over the whole screen.
// Two surfaces draw it (the overview itself and the strip under the bar), so
// both copies must be placed the same way to meet without a seam.
Item {
	id: backdrop

	required property string wallpaper
	// The screen's rectangle, in this item's coordinates.
	property real screenX: 0
	property real screenY: 0
	property real screenW: width
	property real screenH: height

	Image {
		id: wallImage
		// Oversized, so the blur has no see-through edges.
		x: backdrop.screenX - 80
		y: backdrop.screenY - 80
		width: backdrop.screenW + 160
		height: backdrop.screenH + 160
		source: backdrop.wallpaper
		fillMode: Image.PreserveAspectCrop
		// It gets blurred anyway: a small copy is much cheaper to blur every frame.
		sourceSize: Qt.size(640, 360)
		asynchronous: true
		visible: false
	}
	MultiEffect {
		anchors.fill: wallImage
		source: wallImage
		visible: Quickshell.env("MANGO_OVERVIEW_NOBLUR") !== "1"
		blurEnabled: true
		blurMax: 64
		blur: 1
		brightness: -0.05
	}
	Rectangle {
		anchors.fill: parent
		color: Qt.rgba(0, 0, 0, 0.2)
	}
}
