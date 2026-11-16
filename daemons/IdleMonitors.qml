pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

    Variants {
        model: GlobalConfig.general.idle.timeouts.values

        ActivityMonitor {
            required property var modelData

            readonly property bool watching: {
                if (!root.enabled || !(modelData.enabled ?? true))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                if (KeepAwake.blocksAction(modelData.idleAction))
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
