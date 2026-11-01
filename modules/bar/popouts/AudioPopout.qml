pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Bar audio popout. Structure (unchanged from the original fork popout):
//   Main Sound   - output device picker + volume
//   Main Mic     - input device picker + volume
//   Applications - per-stream volumes
//   Music Virtual Sync Output - music_sink routed output picker + its volume, notification volume
//   ALSA Hardware Controls    - Master / Speaker / Headphone (collapsible)
//   Open settings
// Device pickers open a menu that flies out to the RIGHT of the popout (never over it).
Item {
    id: root

    required property PopoutState popouts

    property bool showAlsa: false

    readonly property real maxVol: GlobalConfig.services.maxVolume
    // Cap the popout height; everything past this scrolls inside the Flickable.
    readonly property real maxHeight: (QsWindow.window?.screen?.height ?? 1080) * 0.7
    readonly property bool scrollable: column.implicitHeight > flick.height

    function volIcon(vol: real, muted: bool): string {
        if (muted || vol <= 0.001)
            return "volume_off";
        if (vol <= 0.01)
            return "volume_mute";
        if (vol <= 0.5)
            return "volume_down";
        return "volume_up";
    }

    implicitWidth: 380
    implicitHeight: Math.min(column.implicitHeight, maxHeight)

    // ALSA reads only run while the popout is open; pin the virtual-sink loopbacks on open too.
    Component.onCompleted: {
        Alsa.refCount++;
        VirtualSink.pinLoopbacks();
    }
    Component.onDestruction: {
        Alsa.refCount--;
        if (root.popouts.flyout)
            root.popouts.flyout = null;
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        interactive: root.scrollable
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: flick
        }

        ColumnLayout {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            // Leave room for the scrollbar so it never sits on top of the content
            anchors.rightMargin: root.scrollable ? Tokens.padding.large : 0
            spacing: Tokens.spacing.small

            // ── Output (default speaker) ────────────────────────────────────────
            Card {
                CardTitle {
                    text: Tr.tr("Main Sound")
                }

                DeviceSelect {
                    icon: "speaker"
                    prefix: Tr.tr("Output")
                    // Physical devices + the Music Virtual Sink (so it can be the system default,
                    // routing every app's audio through music_sink). notification_sink is hidden —
                    // it's the alert bus (fanned out to all sinks), not a sensible default.
                    nodes: Audio.sinks.filter(n => n && n.name !== VirtualSink.notificationSinkName)
                    currentName: Audio.sink?.name ?? ""
                    currentLabel: Audio.sink?.description || Audio.sink?.name || ""
                    onSelected: node => Audio.setAudioSink(node)
                }

                VolumeRow {
                    icon: root.volIcon(Audio.volume, Audio.muted)
                    muted: Audio.muted
                    value: Audio.volume
                    max: root.maxVol
                    onMoved: v => Audio.setVolume(v)
                    onToggle: {
                        if (Audio.sink?.ready && Audio.sink?.audio)
                            Audio.setMuted(!Audio.muted);
                    }
                }
            }

            // ── Input (default microphone) ──────────────────────────────────────
            Card {
                CardTitle {
                    text: Tr.tr("Main Mic")
                }

                DeviceSelect {
                    icon: "mic"
                    prefix: Tr.tr("Input")
                    nodes: Audio.sources
                    currentName: Audio.source?.name ?? ""
                    currentLabel: Audio.source?.description || Audio.source?.name || ""
                    inputDevice: true
                    onSelected: node => Audio.setAudioSource(node)
                }

                VolumeRow {
                    icon: Audio.sourceMuted ? "mic_off" : "mic"
                    muted: Audio.sourceMuted
                    value: Audio.sourceVolume
                    max: root.maxVol
                    onMoved: v => Audio.setSourceVolume(v)
                    onToggle: {
                        if (Audio.source?.ready && Audio.source?.audio)
                            Audio.setSourceMuted(!Audio.sourceMuted);
                    }
                }
            }

            // ── Per-application streams ─────────────────────────────────────────
            Card {
                id: appsCard

                readonly property var appStreams: Audio.streams.filter(s => s && s.name !== VirtualSink.musicLoopbackName && s.name !== VirtualSink.notificationLoopbackName)

                visible: appsCard.appStreams.length > 0

                CardTitle {
                    text: Tr.tr("Applications")
                }

                Repeater {
                    model: appsCard.appStreams

                    ColumnLayout {
                        id: streamItem

                        required property PwNode modelData

                        Layout.fillWidth: true
                        spacing: 0

                        SubLabel {
                            text: Audio.getStreamName(streamItem.modelData)
                        }

                        VolumeRow {
                            icon: root.volIcon(streamItem.modelData.audio?.volume ?? 0, streamItem.modelData.audio?.muted ?? false)
                            muted: streamItem.modelData.audio?.muted ?? false
                            value: streamItem.modelData.audio?.volume ?? 0
                            max: root.maxVol
                            onMoved: v => Audio.setStreamVolume(streamItem.modelData, v)
                            onToggle: Audio.setStreamMuted(streamItem.modelData, !(streamItem.modelData.audio?.muted ?? false))
                        }
                    }
                }
            }

            // ── Virtual sinks (music / notification routing) ────────────────────
            Card {
                visible: VirtualSink.available

                CardTitle {
                    text: Tr.tr("Music Virtual Sync Output")
                }

                DeviceSelect {
                    icon: "music_note"
                    prefix: Tr.tr("Output")
                    nodes: VirtualSink.physicalSinks
                    currentName: VirtualSink.musicOutput
                    currentLabel: VirtualSink.musicOutputLabel
                    onSelected: node => VirtualSink.setMusicOutput(node)
                }

                // This slider controls the SELECTED OUTPUT DEVICE's volume, not music_sink's.
                VolumeRow {
                    icon: root.volIcon(VirtualSink.outputVolume, VirtualSink.outputMuted)
                    muted: VirtualSink.outputMuted
                    value: VirtualSink.outputVolume
                    max: root.maxVol
                    onMoved: v => VirtualSink.setOutputVolume(v)
                    onToggle: VirtualSink.setOutputMuted(!VirtualSink.outputMuted)
                }

                SubLabel {
                    Layout.topMargin: Tokens.spacing.small
                    text: Tr.tr("Notification")
                }

                VolumeRow {
                    icon: VirtualSink.notificationMuted ? "notifications_off" : "notifications"
                    muted: VirtualSink.notificationMuted
                    value: VirtualSink.notificationVolume
                    max: root.maxVol
                    onMoved: v => VirtualSink.setNotificationVolume(v)
                    onToggle: VirtualSink.setNotificationMuted(!VirtualSink.notificationMuted)
                }
            }

            // ── ALSA hardware controls ──────────────────────────────────────────
            Card {
                visible: Alsa.available

                SectionHeader {
                    title: Tr.tr("ALSA Hardware Controls")
                    expanded: root.showAlsa
                    onToggled: root.showAlsa = !root.showAlsa
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: root.showAlsa

                    SubLabel {
                        text: Tr.trCtx("Master", "alsa mixer control")
                    }

                    VolumeRow {
                        icon: root.volIcon(Alsa.masterVolume / 100, Alsa.masterMuted)
                        muted: Alsa.masterMuted
                        value: Alsa.masterVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Master", v * 100)
                        onToggle: Alsa.setMuted("Master", !Alsa.masterMuted)
                    }

                    SubLabel {
                        text: Tr.trCtx("Speaker", "alsa mixer control")
                    }

                    VolumeRow {
                        icon: root.volIcon(Alsa.speakerVolume / 100, Alsa.speakerMuted)
                        muted: Alsa.speakerMuted
                        value: Alsa.speakerVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Speaker", v * 100)
                        onToggle: Alsa.setMuted("Speaker", !Alsa.speakerMuted)
                    }

                    SubLabel {
                        text: Tr.trCtx("Headphone/AUX", "alsa mixer control")
                    }

                    VolumeRow {
                        // Display volume: falls back to the persisted value while the jack
                        // reports 0 (nothing plugged in); the icon still shows the state.
                        icon: Alsa.headphoneMuted ? "headset_off" : "headphones"
                        muted: Alsa.headphoneMuted
                        value: Alsa.headphoneDisplayVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Headphone", v * 100)
                        onToggle: Alsa.setMuted("Headphone", !Alsa.headphoneMuted)
                    }
                }
            }

            // ── Settings ────────────────────────────────────────────────────────
            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.small
                text: Tr.tr("Open settings")
                icon: "settings"
                onClicked: root.popouts.detachRequested("audio")
            }
        }
    }

    // ── Reusable inline components ───────────────────────────────────────────────

    component Card: StyledRect {
        default property alias cdata: cardCol.data

        Layout.fillWidth: true
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
        implicitHeight: cardCol.implicitHeight + Tokens.padding.large * 2

        ColumnLayout {
            id: cardCol

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small
        }
    }

    component CardTitle: StyledText {
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    component SubLabel: StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        font: Tokens.font.label.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    // Mute toggle + drag-only slider + percentage. No wheel wrapper on purpose,
    // so scrolling the popout never changes a volume.
    component VolumeRow: RowLayout {
        id: vr

        property alias icon: vrBtn.icon
        property bool muted
        property real value
        property real max: 1

        signal moved(real v)
        signal toggle

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        IconButton {
            id: vrBtn

            type: IconButton.Tonal
            isToggle: true
            checked: vr.muted
            onClicked: vr.toggle()
        }

        StyledSlider {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Tokens.padding.medium * 3

            from: 0
            to: vr.max
            value: vr.value
            onInteraction: v => vr.moved(v)
        }

        StyledText {
            id: pct

            Layout.preferredWidth: pctMetrics.width
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(vr.value * 100)}%`
            font: Tokens.font.label.medium
            color: Colours.palette.m3onSurfaceVariant

            TextMetrics {
                id: pctMetrics

                font: pct.font
                text: "100%"
            }
        }
    }

    // "Output: <device>" pill. Click opens the device menu to the RIGHT of the popout;
    // each entry carries its own "block from automatic switching" toggle.
    component DeviceSelect: StyledRect {
        id: ds

        property string icon
        property string prefix
        property var nodes: []
        property string currentName
        property string currentLabel
        property bool inputDevice

        signal selected(node: PwNode)

        Layout.fillWidth: true
        implicitHeight: dsRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: dsMenu.expanded ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

        StateLayer {
            radius: ds.radius
            onClicked: dsMenu.expanded = !dsMenu.expanded
        }

        RowLayout {
            id: dsRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: ds.icon
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: `${ds.prefix}: ${ds.currentLabel || Tr.tr("None")}`
                elide: Text.ElideRight
                font: Tokens.font.body.small
            }

            MaterialIcon {
                text: "chevron_right"
                color: Colours.palette.m3onSurfaceVariant
                rotation: dsMenu.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }
            }
        }

        Menu {
            id: dsMenu

            attachTo: ds
            hoverPassthrough: true
            // Fly out beside the popout: left edge of the menu at the popout's right edge,
            // top aligned with this row.
            attachSideX: Menu.Right
            thisSideX: Menu.Left
            attachSideY: Menu.Top
            thisSideY: Menu.Top
            marginX: root.width - ds.mapToItem(root, ds.width, 0).x + Tokens.padding.large + Tokens.spacing.small
            items: dsItems.instances
            onItemSelected: item => ds.selected(item.value)
            // Keep the popout alive while the cursor is over the flyout
            onExpandedChanged: root.popouts.flyout = expanded ? panel : (root.popouts.flyout === panel ? null : root.popouts.flyout)
        }

        // Menu assigns `active` directly on selection, which would break a plain binding;
        // a Binding element re-applies whenever the current device or the item set changes.
        Binding {
            target: dsMenu
            property: "active"
            value: dsItems.instances.find(i => i.value?.name === ds.currentName) ?? null
        }

        Variants {
            id: dsItems

            model: [...ds.nodes].sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""))

            MenuItem {
                required property PwNode modelData
                readonly property bool blocked: ds.inputDevice ? AudioDevices.isSourceBlocked(modelData.name) : AudioDevices.isSinkBlocked(modelData.name)

                text: modelData.description || modelData.name
                icon: ds.icon
                value: modelData
                trailingIcon: blocked ? "block" : "sync"
                trailingClickable: true
                trailingActive: blocked
                trailingTooltip: blocked ? Tr.tr("Blocked from automatic switching — click to allow") : Tr.tr("Allow automatic switching — click to block")
                onTrailingClicked: {
                    if (ds.inputDevice)
                        AudioDevices.toggleSourceBlocked(modelData.name);
                    else
                        AudioDevices.toggleSinkBlocked(modelData.name);
                }
            }
        }
    }

    component SectionHeader: StyledRect {
        id: sh

        property string title
        property bool expanded

        signal toggled

        Layout.fillWidth: true
        implicitHeight: shRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: "transparent"

        StateLayer {
            radius: sh.radius
            onClicked: sh.toggled()
        }

        RowLayout {
            id: shRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "expand_more"
                rotation: sh.expanded ? 0 : -90
                color: Colours.palette.m3onSurfaceVariant

                Behavior on rotation {
                    Anim {}
                }
            }

            StyledText {
                text: sh.title
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
