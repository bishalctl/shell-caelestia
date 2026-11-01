import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config

// A monochrome SVG from assets/icons tinted like a MaterialIcon of the given style.
// The SVG is drawn white and recoloured, so any theme colour works.
Item {
    id: root

    required property string name
    property color color: "white"
    property font fontStyle: Tokens.font.icon.small
    // Icon fonts size the glyph a little under the em box; match that
    property real size: fontStyle.pointSize * 4 / 3

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image

        anchors.fill: parent
        source: Quickshell.shellPath(`assets/icons/${root.name}.svg`)
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: image
        source: image
        colorization: 1
        colorizationColor: root.color

        Behavior on colorizationColor {
            ColorAnimation {
                duration: 200
            }
        }
    }
}
