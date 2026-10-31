pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.State

// Keep-awake policy. The modes themselves live in RuntimeState (inhibitIdle,
// inhibitSleepOnly) so they survive a shell restart like upstream's keep awake;
// this singleton derives what is actually being inhibited right now and keeps
// the two manual modes mutually exclusive.
Singleton {
    id: root

    // Full mode: inhibits every idle timeout (no lock, no screen off, no sleep).
    readonly property bool enabled: RuntimeState.inhibitIdle
    // Sleep-only mode: lock and screen off still fire on idle, but sleep-type
    // timeouts (suspend/hibernate) are blocked — for background jobs.
    readonly property bool sleepOnly: RuntimeState.inhibitSleepOnly
    // Controller input need not reach the compositor's idle timer. Protect the
    // entire fullscreen session instead, including cutscenes and paused games.
    readonly property bool fullscreenActive: GlobalConfig.general.idle.inhibitWhenFullscreen && hasVisibleFullscreen()
    readonly property bool inhibiting: enabled || fullscreenActive
    readonly property bool active: inhibiting || sleepOnly

    // Handled by IdleMonitors (which owns the lock): locks the session, then blanks
    signal lockAndBlankRequested

    function lockAndBlank(): void {
        lockAndBlankRequested();
    }

    function setMode(mode: string): void {
        RuntimeState.inhibitIdle = mode === "full";
        RuntimeState.inhibitSleepOnly = mode === "sleepOnly";
    }

    function mode(): string {
        return enabled ? "full" : sleepOnly ? "sleepOnly" : "off";
    }

    // Sleep-type actions are the ones additionally blocked in sleep-only mode;
    // lock/dpms timeouts keep firing there. Matches both raw commands
    // (["systemctl", "suspend-then-hibernate"]) and SessionManager aliases
    // (["suspendThenHibernate"]).
    function isSleepAction(action: var): bool {
        const s = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /suspend|hibernate/i.test(s);
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

    Connections {
        function onInhibitIdleChanged(): void {
            if (RuntimeState.inhibitIdle) {
                RuntimeState.inhibitSleepOnly = false;
                RuntimeState.inhibitingIdleSince = new Date().getTime();
            }
        }

        function onInhibitSleepOnlyChanged(): void {
            if (RuntimeState.inhibitSleepOnly) {
                RuntimeState.inhibitIdle = false;
                RuntimeState.inhibitingIdleSince = new Date().getTime();
            }
        }

        target: RuntimeState
    }
}
