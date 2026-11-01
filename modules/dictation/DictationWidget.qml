pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

// Bottom-middle "bump" popup shown while dictating (OpenWhispr via Dictation service). Slides up
// ~5px above the bottom edge; shows an animated waveform + status (Listening… / Converting…).
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData
        // 0 = shown, 1 = hidden (slid down). Animated.
        property real offsetScale: Dictation.active ? 0 : 1

        screen: modelData
        name: "dictation"
        visible: offsetScale < 1
        exclusiveZone: 0

        WlrLayershell.layer: WlrLayer.Overlay

        anchors.bottom: true
        margins.bottom: 5
        implicitWidth: bump.implicitWidth
        implicitHeight: bump.implicitHeight

        Behavior on offsetScale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        StyledRect {
            id: bump

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            // Slide down off the (clipped) window when hidden.
            anchors.bottomMargin: -implicitHeight * win.offsetScale

            implicitWidth: row.implicitWidth + Tokens.padding.large * 2
            implicitHeight: row.implicitHeight + Tokens.padding.medium * 2

            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
            opacity: 1 - win.offsetScale

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: 2
            }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                // Waveform bars: driven by the microphone while listening (native PipeWire tap of
                // the default source, 4 cava bands), and a gentle idle pulse while converting.
                CavaProvider {
                    id: micCava

                    microphone: true
                    bars: 4
                }

                // Only hold the mic stream open while actually listening
                Loader {
                    active: Dictation.state === "listening"
                    sourceComponent: ServiceRef {
                        service: micCava
                    }
                }

                Row {
                    id: wave

                    readonly property bool live: Dictation.state === "listening"
                    readonly property bool playing: Dictation.state === "converting"
                    spacing: 3
                    // Fixed height (≥ the max animated bar height) so the pulsing bars don't
                    // resize the card every frame — otherwise the whole popup jitters vertically.
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: 4

                        delegate: StyledRect {
                            required property int index

                            readonly property real level: wave.live ? Math.min(1, micCava.values[index] ?? 0) : 0

                            width: 4
                            height: wave.live ? 7 + level * 15 : 7
                            radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Dictation.state === "converting" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary

                            Behavior on height {
                                enabled: wave.live
                                NumberAnimation {
                                    duration: 60
                                }
                            }

                            SequentialAnimation on height {
                                running: wave.playing
                                loops: Animation.Infinite

                                PauseAnimation {
                                    duration: index * 90
                                }
                                NumberAnimation {
                                    to: 22
                                    duration: 320
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 7
                                    duration: 320
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Dictation.statusText
                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Dictation.providerName
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
