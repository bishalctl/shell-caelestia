pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import Quickshell
import qs.services

// Small icon button: copies `textToCopy` to the clipboard (Quickshell.clipboardText) and
// confirms with a tick that pops in, holds briefly, then reverts to the copy icon. Re-clicking
// re-blinks and resets the revert timer, so repeated copies never feel stuck or ambiguous.
StyledRect {
    id: root

    required property string textToCopy
    property font iconFont: Tokens.font.icon.small

    property bool copied: false

    implicitWidth: implicitHeight
    implicitHeight: icon.implicitHeight + Tokens.padding.extraSmall
    radius: width / 2
    color: "transparent"

    StateLayer {
        color: root.copied ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        onClicked: {
            Quickshell.clipboardText = root.textToCopy;
            root.copied = true;
            blink.restart();
            revert.restart();
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: root.copied ? "check" : "content_copy"
        color: root.copied ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        fill: root.copied ? 1 : 0
        fontStyle: root.iconFont

        Behavior on color {
            ColorAnimation {
                duration: Tokens.anim.durations.small
            }
        }
    }

    SequentialAnimation {
        id: blink

        NumberAnimation {
            target: icon
            property: "scale"
            from: 0.5
            to: 1.25
            duration: Tokens.anim.durations.small
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: icon
            property: "scale"
            to: 1
            duration: Tokens.anim.durations.small
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: revert

        interval: 1400
        onTriggered: root.copied = false
    }
}
