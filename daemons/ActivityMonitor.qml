pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Services

// A timeout needs both compositor input and controller input to be idle.
// Controller activity wakes a blank screen through the usual return action;
// it never injects input, changes focus, or authenticates a locked session.
Scope {
    id: root

    property bool enabled: true
    property real timeout: 0
    property bool respectInhibitors: true
    readonly property bool isIdle: enabled && inputMonitor.isIdle && !controllerTimeout.running

    IdleMonitor {
        id: inputMonitor

        enabled: root.enabled
        timeout: root.timeout
        respectInhibitors: root.respectInhibitors
    }

    Timer {
        id: controllerTimeout

        interval: Math.max(1, root.timeout * 1000)
    }

    Connections {
        function onActivity(): void {
            if (root.enabled)
                controllerTimeout.restart();
        }

        target: ControllerActivity
    }
}
