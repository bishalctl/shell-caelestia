pragma Singleton
pragma ComponentBehavior: Bound

import "audio/Policy.js" as AudioPolicy
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

// Virtual-sink routing. Volume/mute/pin are native PwNode.audio writes; only device routing
// (which Quickshell's read-only PwLink can't do) shells out to pw-link.
//
// Graph (NixOS PipeWire config): app -> music_sink -> music_sink.output -> <selected physical>.
//   music_sink            the default output you select in "Output Devices" (apps land here)
//   music_sink.output     loopback, pinned to unity (the "quiet at 100%" fix)
//   <selected physical>   the device music actually comes out of; its volume IS the "Music" slider
//   notification_sink      -> notification_sink.output -> ALL physical sinks (alert bus)
//
// Output selection is a small state machine: persisted across reboots, auto-switches to a newly
// connected device, and falls back through an MRU stack when one disconnects.
// Blocked devices are never automatic candidates, but remain manually selectable.
Singleton {
    id: root

    readonly property string musicSinkName: "music_sink"
    readonly property string notificationSinkName: "notification_sink"
    readonly property string musicLoopbackName: "music_sink.output"
    readonly property string notificationLoopbackName: "notification_sink.output"

    readonly property PwNode musicSink: Audio.sinks.find(n => n?.name === root.musicSinkName) ?? null
    readonly property PwNode notificationSink: Audio.sinks.find(n => n?.name === root.notificationSinkName) ?? null
    readonly property PwNode musicLoopback: Audio.streams.find(n => n?.name === root.musicLoopbackName) ?? null
    readonly property PwNode notificationLoopback: Audio.streams.find(n => n?.name === root.notificationLoopbackName) ?? null

    // Real output devices = sinks minus our virtual ones.
    readonly property list<PwNode> physicalSinks: Audio.sinks.filter(n => n && n.name !== root.musicSinkName && n.name !== root.notificationSinkName)

    readonly property bool available: musicSink !== null || notificationSink !== null

    // node.name of the physical device music currently routes to (persisted).
    property string musicOutput: ""
    // Most-recently-used preference order for fallback when devices disconnect (persisted).
    property var outputStack: []

    readonly property PwNode musicOutputNode: physicalSinks.find(n => n?.name === root.musicOutput) ?? null
    // "Output: <name>" label (B)
    readonly property string musicOutputLabel: musicOutputNode?.description ?? musicOutputNode?.name ?? Tr.trCtx("None", "no music output device")

    // The "Music" slider (C) is the SELECTED OUTPUT DEVICE's volume — not music_sink's.
    readonly property real outputVolume: musicOutputNode?.audio?.volume ?? 0
    readonly property bool outputMuted: !!musicOutputNode?.audio?.muted

    readonly property real notificationVolume: notificationSink?.audio?.volume ?? 0
    readonly property bool notificationMuted: !!notificationSink?.audio?.muted

    // music_sink's own volume. Its persistence lives in AudioPersist's PAIR state
    // (per selected output), not here — this is just the live value for the UI.
    readonly property real musicSinkVolume: musicSink?.audio?.volume ?? 0

    property bool _stateLoaded: false
    property bool _inited: false
    property var _prevSinkNames: []
    property real _savedNotifVol: -1
    // The notification sink's saved volume is restored exactly ONCE (when it first becomes
    // ready), never re-applied afterwards — otherwise every notification/device change would
    // clobber a volume the user just set on the slider.
    property bool _notifVolRestored: false
    property bool _relinkPending: false
    property bool _resetMusicRoute: false
    readonly property var musicLinks: Pipewire.links.values.filter(link => link.source === root.musicLoopback)

    // ── Selected-output volume/mute (C) ──────────────────────────────────────────
    function setOutputVolume(v: real): void {
        if (musicOutputNode?.ready && musicOutputNode?.audio) {
            musicOutputNode.audio.muted = false;
            musicOutputNode.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, v));
            // Pair key (music_sink + this output) — separate from the device's direct volume.
            AudioPersist.outputVolumeSet(root.musicOutput, musicOutputNode.audio.volume);
        }
    }

    function setOutputMuted(m: bool): void {
        if (musicOutputNode?.ready && musicOutputNode?.audio) {
            musicOutputNode.audio.muted = m;
            AudioPersist.outputMutedSet(root.musicOutput, m);
        }
    }

    // ── Notification (alert bus) ─────────────────────────────────────────────────
    function setNotificationVolume(v: real): void {
        if (notificationSink?.ready && notificationSink?.audio) {
            notificationSink.audio.muted = false;
            notificationSink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, v));
        }
    }

    function setNotificationMuted(m: bool): void {
        if (notificationSink?.ready && notificationSink?.audio)
            notificationSink.audio.muted = m;
    }

    // Pin the loopback "*.output" routing streams to unity gain + unmuted (the "quiet at 100%" fix).
    function pinLoopbacks(): void {
        if (musicLoopback?.ready && musicLoopback?.audio) {
            musicLoopback.audio.muted = false;
            if (Math.abs((musicLoopback.audio.volume ?? 1) - 1) > 0.001)
                musicLoopback.audio.volume = 1;
        }
        if (notificationLoopback?.ready && notificationLoopback?.audio) {
            notificationLoopback.audio.muted = false;
            if (Math.abs((notificationLoopback.audio.volume ?? 1) - 1) > 0.001)
                notificationLoopback.audio.volume = 1;
        }
    }

    // User manually picks a music output device.
    function setMusicOutput(node: PwNode): void {
        if (node?.name) {
            // Explicitly reselecting the current device remains a force-refresh.
            root._resetMusicRoute = root._resetMusicRoute || root.musicOutput === node.name;
            _selectOutput(node.name);
        }
    }

    // Apply a selection: record it (MRU front), route music_sink.output -> it, persist.
    function _selectOutput(name: string): void {
        console.log(`[VirtualSink] route music -> ${name}`);
        root.musicOutput = name;
        root.outputStack = AudioPolicy.recent(root.outputStack, name);
        // Serialize relinks: Process cannot start another command while running.
        root.ensureMusicRoute();
        root.save();
    }

    // Selection state machine. Decides which physical device music routes to whenever the device
    // set changes (and at startup), then applies it when an eligible device exists.
    function _reconcileOutput(): void {
        if (!_stateLoaded || !AudioDevices.loaded)
            return;

        const curr = physicalSinks.map(n => n.name).filter(Boolean);
        const target = AudioPolicy.musicOutput(root.musicOutput, curr, root._prevSinkNames, root.outputStack, AudioDevices.blockedSinks, root._inited);
        root._prevSinkNames = curr;

        // Re-route on change, and once on first init even if unchanged (boot may not be linked yet).
        // Empty means no eligible device; retain history, but never route to a blocked fallback.
        if (target !== root.musicOutput || !_inited)
            _selectOutput(target);
    }

    function linkNotificationToAll(): void {
        const names = physicalSinks.map(n => n.name).filter(Boolean);
        if (names.length === 0)
            return;
        notifLinkProc.command = ["sh", "-c", root._relinkScript(root.notificationLoopbackName, names)];
        notifLinkProc.running = true;
    }

    // Reconcile actual ports, not just the saved selection. Leave healthy links
    // alone: starting a game or repairing a missing channel must not interrupt audio.
    function _relinkScript(out: string, targets: var): string {
        const quote = value => "'" + value.replace(/'/g, "'\\''") + "'";
        const pairs = [];
        for (const tgt of targets) {
            pairs.push([`${out}:output_FL`, `${tgt}:playback_FL`]);
            pairs.push([`${out}:output_FR`, `${tgt}:playback_FR`]);
        }
        let s = `links=$(pw-link -l 2>/dev/null | awk -v o=${quote(out)} '/^[^[:space:]]/ { src = index($1, o ":output_") == 1 ? $1 : ""; next } /\\|->/ && src != "" { print src, $2 }');\n`;
        s += 'while read -r src tgt; do\n[ -n "$src" ] || continue\n';
        if (pairs.length > 0)
            s += `case "$src $tgt" in ${pairs.map(p => quote(p.join(" "))).join("|")}) continue ;; esac\n`;
        s += 'pw-link -d "$src" "$tgt" 2>/dev/null\ndone <<CAELESTIA_LINKS\n$links\nCAELESTIA_LINKS\n';
        for (const pair of pairs)
            s += `printf '%s\\n' "$links" | grep -Fx -- ${quote(pair.join(" "))} >/dev/null || pw-link ${quote(pair[0])} ${quote(pair[1])} 2>/dev/null\n`;
        s += "exit 0\n";
        return s;
    }

    function ensureMusicRoute(): void {
        root._relinkPending = true;
        relinkDebounce.restart();
    }

    function _runRelink(): void {
        if (relinkProc.running || !root._relinkPending)
            return;
        root._relinkPending = false;
        const reset = root._resetMusicRoute ? "(\n" + root._relinkScript(root.musicLoopbackName, []) + ")\n" : "";
        root._resetMusicRoute = false;
        relinkProc.command = ["sh", "-c", reset + root._relinkScript(root.musicLoopbackName, root.musicOutput ? [root.musicOutput] : [])];
        relinkProc.running = true;
    }

    function checkMusicRoute(): void {
        if (!root._stateLoaded || !AudioDevices.loaded || !root.musicLoopback?.ready)
            return;
        const links = root.musicLinks;
        if (!root.musicOutput) {
            if (links.length > 0)
                root.ensureMusicRoute();
            return;
        }
        if (!root.musicOutputNode?.ready)
            return;
        // Existing ports can survive a failed negotiation. Those links must be
        // recreated; simply checking that their names exist is not enough.
        if (links.some(link => link.state === PwLinkState.Error || link.state === PwLinkState.Unlinked))
            root._resetMusicRoute = true;
        if (root._resetMusicRoute || links.length !== 2 || links.some(link => link.target !== root.musicOutputNode))
            root.ensureMusicRoute();
    }

    function save(): void {
        if (!root._stateLoaded)
            return;
        stateFile.setText(JSON.stringify({
            musicOutput: root.musicOutput,
            outputStack: root.outputStack,
            notificationVolume: root.notificationVolume
        }));
    }

    // Restore the notification sink's saved volume EXACTLY ONCE, when it first becomes ready.
    // After that the user owns the slider — we never write the volume again, so notifications/
    // device changes can't snap it back to the boot value. (music_sink's volume is restored
    // per-pair by AudioPersist.)
    function _restoreVolumes(): void {
        if (!_notifVolRestored && _savedNotifVol >= 0 && notificationSink?.ready && notificationSink?.audio) {
            notificationSink.audio.volume = _savedNotifVol;
            _notifVolRestored = true;
        }
    }

    // Sinks changed (device connect/disconnect): re-decide the output, re-fan notifications, pin
    // loopbacks. _reconcileOutput reads _inited to tell the first (restore) pass from runtime ones.
    function _update(): void {
        if (!_stateLoaded || !AudioDevices.loaded)
            return;
        pinLoopbacks();
        _reconcileOutput();
        linkNotificationToAll();
        _restoreVolumes();
        _inited = true;
    }

    // New app/game streams can recreate ports or disturb WirePlumber's links.
    // Repair the selected route without restoring/changing any user volumes.
    function _onStreams(): void {
        if (!_stateLoaded)
            return;
        pinLoopbacks();
        _restoreVolumes();
        root.checkMusicRoute();
    }

    onNotificationVolumeChanged: saveDebounce.restart()
    onMusicLinksChanged: routeCheck.restart()

    PwObjectTracker {
        objects: root.musicLinks
    }

    // Any sink change (device connect/disconnect, BT profile switch) re-evaluates the selection.
    // Driven off Audio.sinks directly because a bound list<> property's own change signal isn't
    // always emitted reliably. Debounced so Bluetooth renegotiation bursts don't spam pw-link.
    Connections {
        function onLoadedChanged(): void {
            sinksDebounce.restart();
        }

        target: AudioDevices
    }

    Connections {
        function onSinksChanged(): void {
            sinksDebounce.restart();
        }

        // Loopback "*.output" nodes live in Audio.streams.
        function onStreamsChanged(): void {
            streamsDebounce.restart();
        }

        target: Audio
    }

    Timer {
        id: sinksDebounce

        interval: 250
        onTriggered: root._update()
    }

    Timer {
        id: streamsDebounce

        interval: 250
        onTriggered: root._onStreams()
    }

    Process {
        id: relinkProc

        onRunningChanged: {
            if (!running && root._relinkPending)
                relinkDebounce.restart();
        }
    }

    Timer {
        id: relinkDebounce

        interval: 50
        onTriggered: root._runRelink()
    }

    Timer {
        id: routeCheck

        interval: 150
        onTriggered: root.checkMusicRoute()
    }

    Timer {
        // Native graph check only; no subprocess when the stereo route is healthy.
        interval: 2000
        running: root._stateLoaded && root.musicLoopback !== null
        repeat: true
        onTriggered: root.checkMusicRoute()
    }

    Process {
        id: notifLinkProc
    }

    Timer {
        id: saveDebounce

        interval: 500
        onTriggered: root.save()
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/audio-virtualsink.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c.musicOutput)
                    root.musicOutput = c.musicOutput;
                if (Array.isArray(c.outputStack))
                    root.outputStack = AudioPolicy.names(c.outputStack);
                root._savedNotifVol = c.notificationVolume ?? -1;
            } catch (e) {}
            root._stateLoaded = true;
            sinksDebounce.restart();
        }
        onLoadFailed: {
            root._stateLoaded = true;
            sinksDebounce.restart();
        }
    }
}
