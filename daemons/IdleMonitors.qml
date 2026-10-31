pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.modules.lock

Scope {
    id: root

    required property Lock lock
    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    readonly property bool isCharging: !UPower.onBattery
    readonly property bool enabled: {
        // Enforce Keep Awake locally too: a compositor inhibitor can take a frame
        // to map, and some timeout entries may opt out of protocol inhibitors.
        if (KeepAwake.inhibiting)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenCharging && isCharging)
            return false;
        return true;
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else if (!SessionManager.exec(action))
            Quickshell.execDetached(action);
    }

    Connections {
        function onAboutToSleep(): void {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }

        function onLockRequested(): void {
            root.lock.lock.locked = true;
        }

        function onUnlockRequested(): void {
            root.lock.lock.unlock();
        }

        target: SessionManager
    }

    Connections {
        function onLockAndBlankRequested(): void {
            root.lock.lock.locked = true;
            dpmsTimer.restart();
        }

        target: KeepAwake
    }

    Timer {
        id: dpmsTimer

        // Let the lock surfaces map (and their screencopy capture run) before blanking
        interval: 500
        onTriggered: root.handleIdleAction("dpms off")
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts.values

        IdleMonitor {
            required property var modelData

            readonly property bool watching: {
                if (!root.enabled || !(modelData.enabled ?? true))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                // Sleep-only mode: lock/dpms timeouts keep firing, sleep ones don't
                if (KeepAwake.sleepOnly && KeepAwake.isSleepAction(modelData.idleAction))
                    return false;
                return true;
            }

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
