pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Grid of system tray items, opened from the "systray" status icon. Left click activates,
// right click opens the item's menu (the existing traymenu popouts) or secondary-activates.
Column {
    id: root

    required property PopoutState popouts

    readonly property int cellSize: Tokens.sizes.bar.innerWidth
    readonly property int columns: Math.min(Math.max(items.count, 1), 5)

    spacing: Tokens.spacing.small

    StyledText {
        text: Tr.tr("System tray")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Grid {
        columns: root.columns
        spacing: Tokens.spacing.small

        Repeater {
            id: items

            // Same filter (and therefore the same indices) as the traymenu popouts in Content.qml
            model: ScriptModel {
                values: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            Item {
                id: cell

                required property SystemTrayItem modelData
                required property int index

                implicitWidth: root.cellSize
                implicitHeight: root.cellSize

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3onSurface
                    opacity: mouse.containsMouse ? 0.08 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                ColouredIcon {
                    id: trayIcon

                    anchors.fill: parent
                    anchors.margins: Math.round(root.cellSize * 0.2)
                    source: Icons.getTrayIcon(cell.modelData.id, cell.modelData.icon)
                    colour: Colours.palette.m3secondary
                    layer.enabled: Config.bar.tray.recolour
                }

                // Only when the icon really can't be resolved
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: trayIcon.status === Image.Null || trayIcon.status === Image.Error
                    text: "extension"
                    color: Colours.palette.m3secondary
                    fontStyle: Tokens.font.icon.medium
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: event => {
                        if (event.button === Qt.LeftButton)
                            cell.modelData.activate();
                        else if (cell.modelData.hasMenu)
                            root.popouts.currentName = `traymenu${cell.index}`;
                        else
                            cell.modelData.secondaryActivate();
                    }
                }
            }
        }
    }

    StyledText {
        visible: items.count === 0
        text: Tr.tr("No tray items")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
