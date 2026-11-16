import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    readonly property real nonAnimHeight: layout.implicitHeight + (KeepAwake.enabled ? activeChip.implicitHeight + activeChip.anchors.topMargin : 0) + Tokens.padding.extraLargeIncreased

    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

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
                color: KeepAwake.enabled ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "coffee"
                    color: KeepAwake.enabled ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.trCtx("Keep awake", "idle inhibitor")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!KeepAwake.enabled)
                            return Tr.trCtx("Normal power management", "idle inhibitor");
                        if (KeepAwake.allowLock && KeepAwake.allowScreenBlank)
                            return Tr.trCtx("Can lock & blank; never sleeps", "idle inhibitor");
                        if (KeepAwake.allowLock)
                            return Tr.trCtx("Can lock; screen stays on", "idle inhibitor");
                        if (KeepAwake.allowScreenBlank)
                            return Tr.trCtx("Can blank; stays unlocked", "idle inhibitor");
                        return Tr.trCtx("Screen stays on & unlocked", "idle inhibitor");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                objectName: "keepAwakeSwitch"
                checked: RuntimeState.inhibitIdle
                onToggled: RuntimeState.inhibitIdle = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium
            visible: KeepAwake.enabled

            StyledText {
                Layout.fillWidth: true
                text: Tr.trCtx("Can lock", "idle inhibitor")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledSwitch {
                objectName: "keepAwakeAllowLockSwitch"
                checked: KeepAwake.allowLock
                onToggled: PersistentState.keepAwakeAllowLock = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium
            visible: KeepAwake.enabled

            StyledText {
                Layout.fillWidth: true
                text: Tr.trCtx("Can screen blank", "idle inhibitor")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledSwitch {
                objectName: "keepAwakeAllowScreenBlankSwitch"
                checked: KeepAwake.allowScreenBlank
                onToggled: PersistentState.keepAwakeAllowScreenBlank = checked
            }
        }
    }

    Loader {
        id: activeChip

        asynchronous: true
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.large
        anchors.bottomMargin: KeepAwake.enabled ? Tokens.padding.large : -implicitHeight
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large

        opacity: KeepAwake.enabled ? 1 : 0
        scale: KeepAwake.enabled ? 1 : 0.5

        Component.onCompleted: active = Qt.binding(() => opacity > 0)

        sourceComponent: RowLayout {
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: activeText.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: activeText.implicitHeight + Tokens.padding.small

                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                StyledText {
                    id: activeText

                    anchors.centerIn: parent
                    // TRANSLATORS: %1 = a clock time, e.g. 14:30
                    text: Tr.tr("Active since %1").arg(Tr.formatDateTime(new Date(RuntimeState.inhibitingIdleSince), Units.twelveHourClock ? "hh:mm a" : "hh:mm"))
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.9)).build()
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Behavior on anchors.bottomMargin {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
