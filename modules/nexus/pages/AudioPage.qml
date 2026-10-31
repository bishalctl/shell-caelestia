pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Audio")

    // ALSA reads are ref-gated: poll the hardware only while this page is open.
    Component.onCompleted: Alsa.refCount++
    Component.onDestruction: Alsa.refCount--

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Output
        SliderRow {
            first: true
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            label: Tr.trCtx("Output", "audio output")
            valueLabel: Strings.percentOne(value)
            value: Audio.volume
            enabled: !Audio.muted
            onMoved: v => Audio.setVolume(v)
        }

        ToggleRow {
            text: Tr.trCtx("Muted", "audio output muted")
            checked: Audio.muted
            onToggled: Audio.setMuted(checked)
        }

        AudioDeviceList {
            // notification_sink is the alert bus fanned out to every device, not a sensible default.
            nodes: Audio.sinks.filter(n => n?.name !== VirtualSink.notificationSinkName)
            currentId: Audio.sink?.id ?? -1
            iconName: "speaker"
            placeholderIcon: "speaker"
            placeholderText: Tr.trCtx("No output devices", "no audio outputs")
            blockable: true
            onSelected: node => Audio.setAudioSink(node)
        }

        // Input
        SliderRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
            label: Tr.trCtx("Input", "audio input")
            valueLabel: Strings.percentOne(value)
            value: Audio.sourceVolume
            enabled: !Audio.sourceMuted
            onMoved: v => Audio.setSourceVolume(v)
        }

        ToggleRow {
            text: Tr.trCtx("Muted", "audio input muted")
            checked: Audio.sourceMuted
            onToggled: Audio.setSourceMuted(checked)
        }

        AudioDeviceList {
            nodes: Audio.sources
            currentId: Audio.source?.id ?? -1
            iconName: "mic"
            placeholderIcon: "mic_off"
            placeholderText: Tr.trCtx("No input devices", "no audio inputs")
            blockable: true
            inputDevices: true
            onSelected: node => Audio.setAudioSource(node)
        }

        // Music virtual sink routing: apps -> music_sink -> music_sink.output -> <physical device>.
        // Only shown when the PipeWire graph actually has the virtual sinks.
        SectionHeader {
            visible: VirtualSink.available
            text: Tr.tr("Music routing")
        }

        SliderRow {
            visible: VirtualSink.available
            first: true
            icon: Icons.getVolumeIcon(VirtualSink.outputVolume, VirtualSink.outputMuted)
            label: Tr.tr("Music output: %1").arg(VirtualSink.musicOutputLabel)
            valueLabel: Strings.percentOne(value)
            value: VirtualSink.outputVolume
            enabled: !VirtualSink.outputMuted
            onMoved: v => VirtualSink.setOutputVolume(v)
        }

        ToggleRow {
            visible: VirtualSink.available
            text: Tr.trCtx("Muted", "music output muted")
            checked: VirtualSink.outputMuted
            onToggled: VirtualSink.setOutputMuted(checked)
        }

        AudioDeviceList {
            visible: VirtualSink.available
            nodes: VirtualSink.physicalSinks
            currentName: VirtualSink.musicOutput
            iconName: "music_note"
            placeholderIcon: "music_off"
            placeholderText: Tr.tr("No output devices")
            blockable: true
            onSelected: node => VirtualSink.setMusicOutput(node)
        }

        SliderRow {
            visible: VirtualSink.available
            Layout.topMargin: Tokens.spacing.medium
            first: true
            icon: VirtualSink.notificationMuted ? "notifications_off" : "notifications"
            label: Tr.tr("Notification volume")
            valueLabel: Strings.percentOne(value)
            value: VirtualSink.notificationVolume
            enabled: !VirtualSink.notificationMuted
            onMoved: v => VirtualSink.setNotificationVolume(v)
        }

        ToggleRow {
            visible: VirtualSink.available
            last: true
            text: Tr.trCtx("Muted", "notification sink muted")
            checked: VirtualSink.notificationMuted
            onToggled: VirtualSink.setNotificationMuted(checked)
        }

        // ALSA hardware mixer of the internal card (amixer); reads only run while a page shows it.
        SectionHeader {
            visible: Alsa.available
            text: Tr.tr("Hardware mixer")
        }

        Repeater {
            model: [
                {
                    control: "Master",
                    label: Tr.trCtx("Master", "alsa mixer control"),
                    icon: "speaker"
                },
                {
                    control: "Speaker",
                    label: Tr.trCtx("Speaker", "alsa mixer control"),
                    icon: "speaker"
                },
                {
                    control: "Headphone",
                    label: Tr.trCtx("Headphone/AUX", "alsa mixer control"),
                    icon: "headphones"
                }
            ]

            ColumnLayout {
                id: alsaRow

                required property var modelData
                required property int index
                readonly property int volume: modelData.control === "Master" ? Alsa.masterVolume : modelData.control === "Speaker" ? Alsa.speakerVolume : Alsa.headphoneDisplayVolume
                readonly property bool muted: modelData.control === "Master" ? Alsa.masterMuted : modelData.control === "Speaker" ? Alsa.speakerMuted : Alsa.headphoneMuted

                Layout.fillWidth: true
                visible: Alsa.available
                spacing: parent.spacing

                SliderRow {
                    first: alsaRow.index === 0
                    icon: alsaRow.modelData.icon
                    label: alsaRow.modelData.label
                    valueLabel: Strings.percentOne(value)
                    value: alsaRow.volume / 100
                    enabled: !alsaRow.muted
                    onMoved: v => Alsa.setVolume(alsaRow.modelData.control, v * 100)
                }

                ToggleRow {
                    last: alsaRow.index === 2
                    text: Tr.trCtx("Muted", "alsa control muted")
                    checked: alsaRow.muted
                    onToggled: Alsa.setMuted(alsaRow.modelData.control, checked)
                }
            }
        }

        // Per-app volumes
        NavRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true

            icon: "tune"
            text: Tr.tr("App volumes")
            subtext: Audio.streams.length === 0 ? Tr.tr("No apps playing audio") : Tr.trN("%n app playing audio", "%n apps playing audio", Audio.streams.length)
            onClicked: root.nState.openSubPage(1)
        }
    }
}
