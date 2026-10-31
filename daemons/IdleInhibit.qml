pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.State
import qs.services

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        // qmllint disable uncreatable-type
        PanelWindow {
            // qmllint enable uncreatable-type
            id: inhibitorWindow

            required property ShellScreen modelData
            property bool surfaceReady: false

            screen: modelData
            visible: KeepAwake.inhibiting
            onVisibleChanged: {
                if (!visible)
                    surfaceReady = false;
            }
            // Idle inhibitors only count while their surface is mapped & visible.
            // A 0x0 window never maps as a layer surface, so Hyprland silently
            // ignores its inhibitor. Keep an input-transparent 1x1 surface above
            // fullscreen on each output so external idle daemons (e.g. hypridle)
            // are inhibited as well.
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            mask: Region {}

            WlrLayershell.namespace: "caelestia-idle-inhibitor"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            IdleInhibitor {
                enabled: KeepAwake.inhibiting && inhibitorWindow.surfaceReady
                window: inhibitorWindow
            }

            Connections {
                function onFrameSwapped(): void {
                    // Hyprland checks visibility when the inhibitor is created,
                    // but does not recheck when a layer surface maps. Wait until
                    // the first buffer is committed before creating the inhibitor.
                    inhibitorWindow.surfaceReady = inhibitorWindow.visible;
                }

                target: inhibitorWindow.contentItem.Window.window
            }
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return KeepAwake.enabled;
        }

        function isInhibiting(): bool {
            return KeepAwake.inhibiting;
        }

        function isFullscreenActive(): bool {
            return KeepAwake.fullscreenActive;
        }

        function toggle(): void {
            RuntimeState.inhibitIdle = !RuntimeState.inhibitIdle;
        }

        function enable(): void {
            RuntimeState.inhibitIdle = true;
        }

        function disable(): void {
            RuntimeState.inhibitIdle = false;
        }

        function toggleSleepOnly(): void {
            RuntimeState.inhibitSleepOnly = !RuntimeState.inhibitSleepOnly;
        }

        function getMode(): string {
            return KeepAwake.mode();
        }

        function setMode(mode: string): void {
            KeepAwake.setMode(mode);
        }

        function lockAndBlank(): void {
            KeepAwake.lockAndBlank();
        }

        target: "idleInhibitor"
    }
}
