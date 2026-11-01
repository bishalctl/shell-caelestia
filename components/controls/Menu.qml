pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.modules.drawers

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property int attachSideX: Menu.Right
    property int attachSideY: Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: Menu.Top
    property real marginX
    property real marginY

    readonly property alias panel: menu
    property list<MenuItem> items
    property MenuItem active: items[0] ?? null
    property bool expanded
    // Don't take hover for the full-window overlay (lets hover-driven hosts, e.g. bar popouts,
    // keep seeing the cursor while the menu is open).
    property bool hoverPassthrough
    // Square the left corners so the menu reads as an extension of the surface it flies out of.
    property bool flushLeft

    signal itemSelected(item: MenuItem)

    parent: {
        const win = QsWindow.window;
        const contentWin = win as ContentWindow; // If inside the drawer content window, put it inside the interaction wrapper so hover works
        return contentWin ? contentWin.interactionWrapper : (win as QsWindow).contentItem;
    }
    anchors.fill: parent

    enabled: expanded
    hoverEnabled: expanded && !hoverPassthrough
    cursorShape: expanded ? Qt.ArrowCursor : undefined
    onClicked: expanded = false

    opacity: expanded ? 1 : 0
    layer.enabled: opacity < 1

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        x: {
            CUtils.dependency(watcher.transform); // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            const x = item.mapToItem(root.parent, off, 0).x + root.marginX;
            // Keep the menu on screen (long entries would otherwise run past the window edge)
            return Math.max(0, Math.min(x, root.parent.width - width));
        }
        y: {
            CUtils.dependency(watcher.transform); // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            const y = item.mapToItem(root.parent, 0, off).y + root.marginY;
            return Math.max(0, Math.min(y, root.parent.height - height));
        }

        radius: Tokens.rounding.large
        level: 2

        implicitWidth: Math.max(200, column.implicitWidth + column.anchors.margins * 2)
        implicitHeight: column.implicitHeight + column.anchors.margins * 2

        transform: Scale {
            yScale: root.expanded ? 1 : 0.1
            origin.y: root.thisSideY === Menu.Bottom ? menu.height : 0

            Behavior on yScale {
                Anim {}
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: !root.hoverPassthrough
            onWheel: e => e.accepted = true
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            topLeftRadius: root.flushLeft ? 0 : radius
            bottomLeftRadius: root.flushLeft ? 0 : radius
            color: Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: column

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                spacing: 0

                Repeater {
                    id: repeater

                    model: root.items

                    StyledRect {
                        id: item

                        required property int index
                        required property MenuItem modelData
                        readonly property bool active: modelData === root?.active

                        Layout.fillWidth: true
                        implicitWidth: menuOptionRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: menuOptionRow.implicitHeight + Tokens.padding.medium * 2

                        radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                        topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                        topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                        bottomLeftRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius
                        bottomRightRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius

                        color: Qt.alpha(Colours.palette.m3tertiaryContainer, active ? 1 : 0)

                        Behavior on radius {
                            Anim {}
                        }

                        StateLayer {
                            topLeftRadius: parent.topLeftRadius
                            topRightRadius: parent.topRightRadius
                            bottomLeftRadius: parent.bottomLeftRadius
                            bottomRightRadius: parent.bottomRightRadius

                            color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            disabled: !root.expanded
                            onClicked: {
                                // modelData can be transiently null while a dynamic item list rebuilds
                                if (!item.modelData)
                                    return;
                                root.itemSelected(item.modelData);
                                root.active = item.modelData;
                                item.modelData.clicked();
                                root.expanded = false;
                            }
                        }

                        RowLayout {
                            id: menuOptionRow

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: item.modelData?.icon ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData?.text ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            }

                            Loader {
                                asynchronous: true
                                Layout.alignment: Qt.AlignVCenter
                                active: (item.modelData?.trailingIcon?.length ?? 0) > 0
                                visible: active

                                sourceComponent: item.modelData?.trailingClickable ? trailingButton : trailingIcon
                            }

                            Component {
                                id: trailingIcon

                                MaterialIcon {
                                    text: item.modelData?.trailingIcon ?? ""
                                    color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                }
                            }

                            Component {
                                id: trailingButton

                                StyledRect {
                                    implicitWidth: implicitHeight
                                    implicitHeight: trailingBtnIcon.implicitHeight + Tokens.padding.small * 2
                                    radius: Tokens.rounding.full
                                    color: item.modelData?.trailingActive ? Colours.palette.m3errorContainer : "transparent"

                                    QQC.ToolTip.visible: trailingBtnLayer.containsMouse && (item.modelData?.trailingTooltip?.length ?? 0) > 0
                                    QQC.ToolTip.text: item.modelData?.trailingTooltip ?? ""

                                    StateLayer {
                                        id: trailingBtnLayer

                                        disabled: !root.expanded
                                        onClicked: item.modelData?.trailingClicked()
                                    }

                                    MaterialIcon {
                                        id: trailingBtnIcon

                                        anchors.centerIn: parent
                                        text: item.modelData?.trailingIcon ?? ""
                                        color: item.modelData?.trailingActive ? Colours.palette.m3onErrorContainer : item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
