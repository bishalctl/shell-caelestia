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

    readonly property real nonAnimHeight: layout.implicitHeight + (KeepAwake.active ? activeChip.implicitHeight + activeChip.anchors.topMargin : 0) + Tokens.padding.extraLargeIncreased

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
                color: KeepAwake.active ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "coffee"
                    color: KeepAwake.active ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
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
                        if (KeepAwake.enabled)
                            return Tr.trCtx("Preventing lock, screen off & sleep", "idle inhibitor");
                        if (KeepAwake.fullscreenActive)
                            return Tr.trCtx("Fullscreen: preventing lock, screen off & sleep", "idle inhibitor");
                        if (KeepAwake.sleepOnly)
                            return Tr.trCtx("Locks & blanks normally, never sleeps", "idle inhibitor");
                        return Tr.trCtx("Normal power management", "idle inhibitor");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: RuntimeState.inhibitIdle
                onToggled: RuntimeState.inhibitIdle = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: Tr.trCtx("Automatic when fullscreen", "idle inhibitor")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledSwitch {
                checked: GlobalConfig.general.idle.inhibitWhenFullscreen
                onToggled: GlobalConfig.general.idle.inhibitWhenFullscreen = checked
            }
        }

        // Sleep-only mode: idle lock/screen off still fire, only suspend is blocked —
        // for leaving jobs running in the background behind a locked screen.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: Tr.trCtx("Block sleep only", "idle inhibitor")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledSwitch {
                checked: RuntimeState.inhibitSleepOnly
                onToggled: RuntimeState.inhibitSleepOnly = checked
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
        anchors.bottomMargin: KeepAwake.active ? Tokens.padding.large : -implicitHeight
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large

        opacity: KeepAwake.active ? 1 : 0
        scale: KeepAwake.active ? 1 : 0.5

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
                    text: KeepAwake.fullscreenActive && !KeepAwake.enabled ? Tr.trCtx("Automatic · fullscreen", "idle inhibitor") : Tr.tr("Active since %1").arg(Tr.formatDateTime(new Date(RuntimeState.inhibitingIdleSince), Units.twelveHourClock ? "hh:mm a" : "hh:mm"))
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.9)).build()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            IconTextButton {
                visible: KeepAwake.sleepOnly
                type: IconTextButton.Tonal
                icon: "lock"
                text: Tr.trCtx("Lock now", "idle inhibitor")
                font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.9)).build()
                onClicked: KeepAwake.lockAndBlank()
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
