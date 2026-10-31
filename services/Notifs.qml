pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n.popup)

    // Popup display mode, derived from persistent state: "default" full cards, "peek" a small
    // app-icon badge only, "dnd" no popups at all (history still accrues). DND is upstream's
    // PersistentState.doNotDisturb so the quick toggle, shortcut and IPC keep working; peek is ours.
    readonly property bool dnd: PersistentState.doNotDisturb
    readonly property bool peek: !dnd && PersistentState.notifPeek
    readonly property string mode: dnd ? "dnd" : peek ? "peek" : "default"

    // Notification sound, independent of the display mode. Other parts of the shell (e.g. a
    // dictation module whose mic would pick the chime up) can set soundSuppressed to mute it.
    readonly property bool soundEnabled: PersistentState.notifSound
    property bool soundSuppressed
    readonly property string soundFile: GlobalConfig.notifs.soundPath || Quickshell.shellPath("assets/sounds/notification.wav")

    property bool loaded

    function cycleMode(): void {
        if (dnd) {
            PersistentState.notifPeek = false;
            PersistentState.doNotDisturb = false;
        } else if (peek) {
            PersistentState.doNotDisturb = true;
            PersistentState.notifPeek = false;
        } else {
            PersistentState.notifPeek = true;
        }
    }

    function setMode(m: string): void {
        PersistentState.doNotDisturb = m === "dnd";
        PersistentState.notifPeek = m === "peek";
    }

    function toggleSound(): void {
        PersistentState.notifSound = !PersistentState.notifSound;
    }

    // Cooldown-debounced so a burst of notifications doesn't stack chimes.
    function playSound(): void {
        if (!soundEnabled || soundSuppressed || soundCooldown.running)
            return;
        const args = ["pw-play"];
        if (GlobalConfig.notifs.soundTarget)
            args.push("--target", GlobalConfig.notifs.soundTarget);
        args.push(soundFile);
        Quickshell.execDetached(args);
        soundCooldown.restart();
    }

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1))
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        if (PersistentState.doNotDisturb || ShellState.anySidebarOpen())
            return false;
        if (GlobalConfig.notifs.fullscreen === NotifsFullscreen.Off && hasFullscreen())
            return false;
        return true;
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Connections {
        function onDoNotDisturbChanged(): void {
            if (!GlobalConfig.utilities.toasts.dndChanged)
                return;

            if (PersistentState.doNotDisturb)
                Toaster.toast(Tr.tr("Do not disturb enabled"), Tr.tr("Popup notifications are now disabled"), "do_not_disturb_on");
            else if (PersistentState.notifPeek)
                Toaster.toast(Tr.tr("Peek mode"), Tr.tr("Notifications show as a small badge"), "notifications_paused");
            else
                Toaster.toast(Tr.tr("Do not disturb disabled"), Tr.tr("Popup notifications are now enabled"), "do_not_disturb_off");
        }

        function onNotifPeekChanged(): void {
            if (!GlobalConfig.utilities.toasts.dndChanged || PersistentState.doNotDisturb)
                return;

            if (PersistentState.notifPeek)
                Toaster.toast(Tr.tr("Peek mode"), Tr.tr("Notifications show as a small badge"), "notifications_paused");
            else
                Toaster.toast(Tr.tr("Peek mode disabled"), Tr.tr("Popup notifications are shown in full"), "notifications_active");
        }

        target: PersistentState
    }

    Timer {
        id: soundCooldown

        interval: 300
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    image: n.image,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                notification: notif
            });
            root.list = [comp, ...root.list];
            root.playSound();
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            for (const notif of data) {
                const properties = Object.assign({}, notif);

                // Backwards compatibility for old notifications
                if (properties.notificationId === undefined && properties.id !== undefined)
                    properties.notificationId = properties.id;

                delete properties.id;
                root.list.push(notifComp.createObject(root, properties));
            }
            root.list.sort((a, b) => b.time - a.time);
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "toggleDnd"
        description: "Toggle do not disturb"
        onPressed: {
            PersistentState.doNotDisturb = !PersistentState.doNotDisturb;
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return PersistentState.doNotDisturb;
        }

        function toggleDnd(): void {
            PersistentState.doNotDisturb = !PersistentState.doNotDisturb;
        }

        function enableDnd(): void {
            PersistentState.doNotDisturb = true;
        }

        function disableDnd(): void {
            PersistentState.doNotDisturb = false;
        }

        function getMode(): string {
            return root.mode;
        }

        function setMode(m: string): void {
            root.setMode(m);
        }

        function cycleMode(): void {
            root.cycleMode();
        }

        function isSoundEnabled(): bool {
            return root.soundEnabled;
        }

        function toggleSound(): void {
            root.toggleSound();
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
