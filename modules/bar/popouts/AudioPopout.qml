pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property PopoutState popouts

    // Cap the popout so it never overflows the screen; the body scrolls past that.
    readonly property real maxHeight: (QsWindow.window?.screen?.height ?? 1080) * 0.7

    implicitWidth: Tokens.sizes.bar.audioWidth
    implicitHeight: Math.min(layout.implicitHeight + Tokens.padding.medium * 2, maxHeight)

    // ALSA reads are ref-gated: poll the hardware only while the popout is open.
    Component.onCompleted: Alsa.refCount++
    Component.onDestruction: Alsa.refCount--

    Flickable {
        id: flickable

        anchors.fill: parent
        anchors.topMargin: Tokens.padding.medium
        anchors.bottomMargin: Tokens.padding.medium
        contentWidth: width
        contentHeight: layout.implicitHeight
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: flickable
        }

        ColumnLayout {
            id: layout

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.medium

            DeviceSelect {
                label: Tr.trCtx("Output device", "audio output device")
                icon: "speaker"
                // notification_sink is the alert bus fanned out to every device, not a sensible default.
                nodes: Audio.sinks.filter(n => n?.name !== VirtualSink.notificationSinkName)
                currentName: Audio.sink?.name ?? ""
                onSelected: node => Audio.setAudioSink(node)
            }

            DeviceSelect {
                Layout.topMargin: Tokens.spacing.medium
                label: Tr.trCtx("Input device", "audio input device")
                icon: "mic"
                nodes: Audio.sources
                currentName: Audio.source?.name ?? ""
                inputDevice: true
                onSelected: node => Audio.setAudioSource(node)
            }

            VolumeRow {
                Layout.topMargin: Tokens.spacing.medium
                label: Audio.muted ? Tr.tr("Volume (muted)") : Tr.tr("Volume (%1%)").arg(Math.round(Audio.volume * 100))
                icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                muted: Audio.muted
                value: Audio.volume
                onMoved: v => Audio.setVolume(v)
                onToggleMute: Audio.setMuted(!Audio.muted)
                onStep: up => up ? Audio.incrementVolume() : Audio.decrementVolume()
            }

            VolumeRow {
                label: Audio.sourceMuted ? Tr.tr("Microphone (muted)") : Tr.tr("Microphone (%1%)").arg(Math.round(Audio.sourceVolume * 100))
                icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                muted: Audio.sourceMuted
                value: Audio.sourceVolume
                onMoved: v => Audio.setSourceVolume(v)
                onToggleMute: Audio.setSourceMuted(!Audio.sourceMuted)
                onStep: up => up ? Audio.incrementSourceVolume() : Audio.decrementSourceVolume()
            }

            // Music virtual sink routing: apps -> music_sink -> music_sink.output -> <physical device>.
            // The "Music" slider is the routed device's volume; music_sink's own volume is the
            // main slider above while music_sink is the default. Only shown when the graph has it.
            DeviceSelect {
                Layout.topMargin: Tokens.spacing.medium
                visible: VirtualSink.available
                label: Tr.tr("Music output device")
                icon: "music_note"
                nodes: VirtualSink.available ? VirtualSink.physicalSinks : []
                currentName: VirtualSink.musicOutput
                onSelected: node => VirtualSink.setMusicOutput(node)
            }

            VolumeRow {
                visible: VirtualSink.available
                label: VirtualSink.outputMuted ? Tr.tr("Music (muted)") : Tr.tr("Music (%1%)").arg(Math.round(VirtualSink.outputVolume * 100))
                icon: Icons.getVolumeIcon(VirtualSink.outputVolume, VirtualSink.outputMuted)
                muted: VirtualSink.outputMuted
                value: VirtualSink.outputVolume
                onMoved: v => VirtualSink.setOutputVolume(v)
                onToggleMute: VirtualSink.setOutputMuted(!VirtualSink.outputMuted)
                onStep: up => VirtualSink.setOutputVolume(VirtualSink.outputVolume + (up ? 1 : -1) * GlobalConfig.services.audioIncrement)
            }

            VolumeRow {
                visible: VirtualSink.available
                label: VirtualSink.notificationMuted ? Tr.tr("Notifications (muted)") : Tr.tr("Notifications (%1%)").arg(Math.round(VirtualSink.notificationVolume * 100))
                icon: VirtualSink.notificationMuted ? "notifications_off" : "notifications"
                muted: VirtualSink.notificationMuted
                value: VirtualSink.notificationVolume
                onMoved: v => VirtualSink.setNotificationVolume(v)
                onToggleMute: VirtualSink.setNotificationMuted(!VirtualSink.notificationMuted)
                onStep: up => VirtualSink.setNotificationVolume(VirtualSink.notificationVolume + (up ? 1 : -1) * GlobalConfig.services.audioIncrement)
            }

            // ALSA hardware mixer of the internal card (amixer), 0-100.
            StyledText {
                Layout.topMargin: Tokens.spacing.medium
                visible: Alsa.available
                text: Tr.tr("Hardware mixer")
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            }

            VolumeRow {
                visible: Alsa.available
                label: Tr.trCtx("Master (%1%)", "alsa mixer control").arg(Alsa.masterVolume)
                icon: Icons.getVolumeIcon(Alsa.masterVolume / 100, Alsa.masterMuted)
                muted: Alsa.masterMuted
                value: Alsa.masterVolume / 100
                max: 1
                onMoved: v => Alsa.setVolume("Master", v * 100)
                onToggleMute: Alsa.setMuted("Master", !Alsa.masterMuted)
                onStep: up => Alsa.setVolume("Master", Alsa.masterVolume + (up ? 5 : -5))
            }

            VolumeRow {
                visible: Alsa.available
                label: Tr.trCtx("Speaker (%1%)", "alsa mixer control").arg(Alsa.speakerVolume)
                icon: Icons.getVolumeIcon(Alsa.speakerVolume / 100, Alsa.speakerMuted)
                muted: Alsa.speakerMuted
                value: Alsa.speakerVolume / 100
                max: 1
                onMoved: v => Alsa.setVolume("Speaker", v * 100)
                onToggleMute: Alsa.setMuted("Speaker", !Alsa.speakerMuted)
                onStep: up => Alsa.setVolume("Speaker", Alsa.speakerVolume + (up ? 5 : -5))
            }

            VolumeRow {
                visible: Alsa.available
                // Display value falls back to the persisted volume while the jack reports 0
                // (nothing plugged in); the icon still shows the state.
                label: Tr.trCtx("Headphone/AUX (%1%)", "alsa mixer control").arg(Alsa.headphoneDisplayVolume)
                icon: Alsa.headphoneMuted ? "headset_off" : "headphones"
                muted: Alsa.headphoneMuted
                value: Alsa.headphoneDisplayVolume / 100
                max: 1
                onMoved: v => Alsa.setVolume("Headphone", v * 100)
                onToggleMute: Alsa.setMuted("Headphone", !Alsa.headphoneMuted)
                onStep: up => Alsa.setVolume("Headphone", Alsa.headphoneDisplayVolume + (up ? 5 : -5))
            }

            IconTextButton {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.medium
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.extraSmall
                text: Tr.tr("Open settings")
                icon: "settings"

                onClicked: root.popouts.detachRequested("audio")
            }
        }
    }

    // Label + dropdown of devices; each entry carries its "block from automatic switching" toggle.
    component DeviceSelect: ColumnLayout {
        id: deviceSelect

        property alias label: selectLabel.text
        property string icon
        property var nodes: []
        property string currentName
        property bool inputDevice

        signal selected(node: PwNode)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        // Raise the row while its menu is open so the dropdown draws over the rows below.
        z: select.expanded ? 1 : 0

        StyledText {
            id: selectLabel

            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            SplitButton {
                id: select

                Layout.fillWidth: true
                type: SplitButton.Tonal
                fallbackIcon: deviceSelect.icon
                fallbackText: Tr.trCtx("None", "no audio device selected")
                minLeftWidth: width - expandBtn.implicitWidth - spacing
                menuItems: deviceItems.instances
                stateLayer.onClicked: select.expanded = !select.expanded
                menu.onItemSelected: item => deviceSelect.selected(item.value)
                label.Layout.maximumWidth: minLeftWidth - iconLabel.implicitWidth - textRow.spacing - horizontalPadding * 2
                label.elide: Text.ElideRight

                // Menu assigns `active` directly on selection, which would break a plain binding;
                // a Binding element re-applies whenever the current device or the item set changes.
                Binding {
                    target: select
                    property: "active"
                    value: deviceItems.instances.find(i => i.value?.name === deviceSelect.currentName) ?? null
                }

                Variants {
                    id: deviceItems

                    model: [...deviceSelect.nodes].sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""))

                    MenuItem {
                        id: deviceItem

                        required property PwNode modelData
                        readonly property bool blocked: deviceSelect.inputDevice ? AudioDevices.isSourceBlocked(modelData.name) : AudioDevices.isSinkBlocked(modelData.name)

                        text: modelData.description || modelData.name
                        icon: deviceSelect.icon
                        value: modelData
                        trailingIcon: blocked ? "block" : "sync"
                        trailingClickable: true
                        trailingActive: blocked
                        trailingTooltip: blocked ? Tr.tr("Blocked from automatic switching — click to allow") : Tr.tr("Allow automatic switching — click to block")
                        onTrailingClicked: {
                            if (deviceSelect.inputDevice)
                                AudioDevices.toggleSourceBlocked(modelData.name);
                            else
                                AudioDevices.toggleSinkBlocked(modelData.name);
                        }
                    }
                }
            }
        }
    }

    // Label + mute button + wheel-steppable slider. Sliders are 0..maxVolume unless `max` says otherwise.
    component VolumeRow: ColumnLayout {
        id: volumeRow

        property alias label: volumeLabel.text
        property alias icon: muteButton.icon
        property bool muted
        property real value
        property real max: GlobalConfig.services.maxVolume

        signal moved(v: real)
        signal toggleMute
        signal step(up: bool)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            id: volumeLabel

            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                id: muteButton

                type: IconButton.Tonal
                isToggle: true
                checked: volumeRow.muted
                onClicked: volumeRow.toggleMute()
            }

            CustomMouseArea {
                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium * 3

                onWheel: event => {
                    if (event.angleDelta.y > 0)
                        volumeRow.step(true);
                    else if (event.angleDelta.y < 0)
                        volumeRow.step(false);
                }

                StyledSlider {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: parent.implicitHeight

                    to: volumeRow.max
                    value: volumeRow.value
                    onInteraction: value => volumeRow.moved(value)
                }
            }
        }
    }
}
