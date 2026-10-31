pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Compact, FIXED-SIZE vertical workspace switcher: up arrow / current workspace number / down
// arrow. Unlike Workspaces it never grows or shrinks with occupancy, so it can't shove the rest
// of the bar around. The number is the active workspace of this bar's monitor (perMonitor) or
// the focused one. Arrows step to the previous/next workspace; scrolling over it is handled in
// Bar.handleWheel (keyed on the "workspaceArrows" entry id).
StyledRect {
    id: root

    required property ShellScreen screen

    readonly property int activeWsId: (Config.bar.workspaces.perMonitor ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.activeWorkspace?.id ?? 1

    // dir: -1 = previous (up), +1 = next (down). Never step below workspace 1.
    function step(dir: int): void {
        if (dir < 0 && activeWsId <= 1)
            return;
        const rel = `r${dir > 0 ? "+" : "-"}1`;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${rel}" })` : `workspace ${rel}`);
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.small * 2

    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall / 2

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: "keyboard_arrow_up"
            disabled: root.activeWsId <= 1
            onClicked: root.step(-1)
        }

        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.max(implicitHeight, num.implicitWidth + Tokens.padding.small)
            implicitHeight: num.implicitHeight + Tokens.padding.extraSmall

            radius: Tokens.rounding.full
            color: Colours.palette.m3primary

            StyledText {
                id: num

                anchors.centerIn: parent
                animate: true
                text: `${root.activeWsId}`
                color: Colours.palette.m3onPrimary
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            }
        }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: "keyboard_arrow_down"
            onClicked: root.step(1)
        }
    }
}
