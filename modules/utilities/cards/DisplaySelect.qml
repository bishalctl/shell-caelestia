pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Picks the XWayland/X11 RandR primary output (for legacy X11 apps). Connected outputs are
// shown as selectable chips straight from Xrandr.outputs; the list is re-queried whenever the
// panel opens rather than polled.
StyledRect {
    id: root

    required property ScreenState screenState

    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    Component.onCompleted: Xrandr.refresh()

    Connections {
        function onUtilitiesChanged(): void {
            if (root.screenState.utilities)
                Xrandr.refresh();
        }

        function onSidebarChanged(): void {
            if (root.screenState.sidebar)
                Xrandr.refresh();
        }

        target: root.screenState
    }

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "desktop_windows"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Primary display")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (Xrandr.outputs.length === 0)
                            return Tr.tr("No displays detected");
                        if (Xrandr.primary)
                            // TRANSLATORS: %1 = X11 output name, e.g. DP-1
                            return Tr.tr("Primary: %1").arg(Xrandr.primary);
                        return Tr.tr("Tap a display to set it primary");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }

        // One chip per connected output; the current primary is highlighted
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: Xrandr.outputs.length > 0

            Repeater {
                model: Xrandr.outputs

                delegate: StyledRect {
                    id: chip

                    required property var modelData
                    readonly property bool isPrimary: modelData.primary

                    implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2

                    radius: Tokens.rounding.full
                    color: isPrimary ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                    StateLayer {
                        color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        onClicked: Xrandr.setPrimary(chip.modelData.name)
                    }

                    RowLayout {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignVCenter
                            text: chip.isPrimary ? "check" : "desktop_windows"
                            color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: chip.modelData.name
                            color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                        }
                    }
                }
            }
        }
    }
}
