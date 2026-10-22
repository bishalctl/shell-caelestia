pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Internal
import qs.services
import qs.services as Services

Scope {
    id: root

    required property Lock lock
    // Enforce Keep Awake locally too: a compositor inhibitor can take a frame
    // to map, and some timeout entries may opt out of protocol inhibitors.
    // Qualify the service to distinguish it from Quickshell.Wayland's type.
    readonly property bool enabled: !Services.IdleInhibitor.inhibiting && (!GlobalConfig.general.idle.inhibitWhenAudio || !Players.list.some(p => p.isPlaying))

    // Sleep-type actions are the ones additionally blocked in sleep-only inhibit
    // mode; lock/dpms timeouts keep firing there.
    function isSleepAction(action: var): bool {
        const s = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /suspend|hibernate/i.test(s);
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(action);
        else
            Quickshell.execDetached(action);
    }

    Connections {
        function onLockAndBlankRequested(): void {
            root.lock.lock.locked = true;
            dpmsTimer.restart();
        }

        target: Services.IdleInhibitor
    }

    Timer {
        id: dpmsTimer

        // Let the lock surfaces map (and their screencopy capture run) before blanking
        interval: 500
        onTriggered: Hypr.dispatch("dpms off")
    }

    LogindManager {
        onAboutToSleep: {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }
        onLockRequested: root.lock.lock.locked = true
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData
            readonly property bool watching: root.enabled && (modelData.enabled ?? true) && !(Services.IdleInhibitor.sleepOnly && root.isSleepAction(modelData.idleAction))

            enabled: watching
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: {
                // Ignore a queued timeout after inhibition starts, but always
                // allow return actions (e.g. restoring a blanked display).
                if (!isIdle || watching)
                    root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction);
            }
        }
    }
}
