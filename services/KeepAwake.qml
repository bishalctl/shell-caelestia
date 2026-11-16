pragma Singleton

import QtQuick
import Quickshell
import Caelestia.State

Singleton {
    id: root

    readonly property bool enabled: RuntimeState.inhibitIdle
    readonly property bool allowLock: PersistentState.keepAwakeAllowLock
    readonly property bool allowScreenBlank: PersistentState.keepAwakeAllowScreenBlank
    // A Wayland inhibitor blocks both lock and blanking, so only use one when
    // neither is allowed. Selective inhibition is enforced by IdleMonitors.
    readonly property bool inhibiting: enabled && !allowLock && !allowScreenBlank

    function isSleepAction(action: var): bool {
        const command = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /suspend|hibernate|hybrid-sleep/i.test(command);
    }

    function isLockAction(action: var): bool {
        const command = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /^(lock|loginctl lock-sessions?)(\s|$)/.test(command);
    }

    function isScreenBlankAction(action: var): bool {
        const command = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /\bdpms\s+off\b/.test(command);
    }

    function blocksAction(action: var): bool {
        if (!enabled)
            return false;
        if (isSleepAction(action))
            return true;
        if (isLockAction(action))
            return !allowLock;
        if (isScreenBlankAction(action))
            return !allowScreenBlank;
        // Sleep, hibernation and other idle actions remain blocked in every
        // Keep Awake combination. Only locking and blanking can be opted in.
        return true;
    }

    Connections {
        function onInhibitIdleChanged(): void {
            if (RuntimeState.inhibitIdle)
                RuntimeState.inhibitingIdleSince = Date.now();
        }

        target: RuntimeState
    }
}
