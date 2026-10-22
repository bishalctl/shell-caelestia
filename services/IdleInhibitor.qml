pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config

Singleton {
    id: root

    // Full mode: inhibits every idle timeout (no lock, no screen off, no sleep).
    property alias enabled: props.enabled
    // Sleep-only mode: lock and screen off still fire on idle, but sleep-type
    // timeouts (suspend/hibernate) are blocked — for background jobs.
    property alias sleepOnly: props.sleepOnly
    // Controller input need not reach the compositor's idle timer. Protect the
    // entire fullscreen session instead, including cutscenes and paused games.
    readonly property bool fullscreenActive: GlobalConfig.general.idle.inhibitWhenFullscreen && hasVisibleFullscreen()
    readonly property bool inhibiting: props.enabled || fullscreenActive
    readonly property bool active: inhibiting || props.sleepOnly
    readonly property alias enabledSince: props.enabledSince

    // Handled by IdleMonitors (which owns the lock): locks the session, then blanks
    signal lockAndBlankRequested

    function lockAndBlank(): void {
        lockAndBlankRequested();
    }

    function workspaceHasFullscreen(workspace: var): bool {
        return workspace?.toplevels.values.some(t => {
            const client = t.lastIpcObject;
            // fullscreenClient also covers games using fake/client-only
            // fullscreen. Hyprland's maximized state (1) is not fullscreen.
            return client?.mapped !== false && !client?.hidden && (client?.fullscreen > 1 || client?.fullscreenClient > 1);
        }) ?? false;
    }

    function hasVisibleFullscreen(): bool {
        return Hypr.monitors.values.some(monitor => {
            if (monitor.lastIpcObject.disabled)
                return false;
            if (workspaceHasFullscreen(monitor.activeWorkspace))
                return true;

            // A game on another monitor or an open special workspace still
            // counts; fullscreen windows on hidden workspaces do not.
            const specialName = monitor.lastIpcObject.specialWorkspace?.name;
            return !!specialName && workspaceHasFullscreen(Hypr.workspaces.values.find(ws => ws.name === specialName));
        });
    }

    PersistentProperties {
        id: props

        property bool enabled
        property bool sleepOnly
        property date enabledSince

        onEnabledChanged: {
            if (enabled) {
                sleepOnly = false;
                enabledSince = new Date();
            }
        }

        onSleepOnlyChanged: {
            if (sleepOnly) {
                enabled = false;
                enabledSince = new Date();
            }
        }

        reloadableId: "idleInhibitor"
    }

    Variants {
        model: Quickshell.screens

        // qmllint disable uncreatable-type
        PanelWindow {
            // qmllint enable uncreatable-type
            id: inhibitorWindow

            required property ShellScreen modelData
            property bool surfaceReady: false

            screen: modelData
            visible: root.inhibiting
            onVisibleChanged: {
                if (!visible)
                    surfaceReady = false;
            }
            // Idle inhibitors only count while their surface is mapped & visible.
            // Keep an input-transparent surface above fullscreen on each output
            // so external idle daemons (e.g. hypridle) are inhibited as well.
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            mask: Region {}

            WlrLayershell.namespace: "caelestia-idle-inhibitor"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            IdleInhibitor {
                enabled: root.inhibiting && inhibitorWindow.surfaceReady
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
            return props.enabled;
        }

        function isInhibiting(): bool {
            return root.inhibiting;
        }

        function isFullscreenActive(): bool {
            return root.fullscreenActive;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        function toggleSleepOnly(): void {
            props.sleepOnly = !props.sleepOnly;
        }

        function getMode(): string {
            return props.enabled ? "full" : props.sleepOnly ? "sleepOnly" : "off";
        }

        function setMode(mode: string): void {
            props.enabled = mode === "full";
            props.sleepOnly = mode === "sleepOnly";
        }

        function lockAndBlank(): void {
            root.lockAndBlank();
        }

        target: "idleInhibitor"
    }
}
