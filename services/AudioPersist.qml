pragma Singleton
pragma ComponentBehavior: Bound

import "audio/Policy.js" as AudioPolicy
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.services
import qs.utils

// Persistent volumes + mute states, keyed by identifiers that survive reboots
// (PipeWire node.name, application.name, ALSA control name — never numeric ids).
//
// Model (v2 schema in audio-volumes.json):
//   pairs[<phys>]   the music chain state for (music_sink -> <phys device>):
//                     phys/physMuted   the routed device's volume ("Music" slider)
//                     vsink/vsinkMuted music_sink's own volume (Main Sound while
//                                      music_sink is the default)
//                   Each route target remembers its own pair — switching outputs
//                   restores that pair, defaulting to phys=100% / vsink=40%.
//   main[<sink>]    a physical sink used DIRECTLY as the default output. Restore
//                   its own saved volume, or 40%; never derive it from a pair.
//   sources[<src>]  input devices; apps[<app>] per-application streams;
//                   alsa[<control>] hardware mixer controls. Restored only if saved.
//
// Ownership rule for one device reachable both ways: while the device itself is
// the default sink, main[] owns its node volume; while music_sink is the default,
// the pair owns it. Context switches re-assert the owning value.
//
// Saves happen only on shell-initiated changes (the setters in Audio/VirtualSink/
// Alsa call the *Set hooks), never by observing node volumes — so our own restores
// and transient device states can't clobber what the user set. Restores are
// debounced behind settle timers so default-sink flips during device churn apply
// nothing until the dust settles (the race that killed v1).
Singleton {
    id: root

    // { pairs: {}, main: {}, sources: {}, apps: {}, alsa: {} } — reassigned on
    // change so bindings (e.g. the Headphone display fallback in Alsa) stay reactive.
    property var state: ({
            pairs: {},
            main: {},
            sources: {},
            apps: {},
            alsa: {}
        })
    property bool loaded: false
    // token -> {node, vol (-1 = leave), muted (undefined = leave), output}
    property var _pending: ({})
    property int _pumpTicks: 0
    property var _appliedStreams: ({})
    property int _streamTicks: 0

    function _set(section: string, key: string, fields: var): void {
        if (!key)
            return;
        // An outstanding restore must not overwrite a slider the user just moved.
        const pending = Object.assign({}, root._pending);
        for (const token of Object.keys(pending)) {
            const name = pending[token].node?.name;
            const deviceChanged = (section === "main" || section === "sources") && name === key;
            const mainChanged = (fields.vsink !== undefined || fields.vsinkMuted !== undefined) && name === VirtualSink.musicSinkName;
            const outputChanged = (fields.phys !== undefined || fields.physMuted !== undefined) && name === key;
            if (deviceChanged || section === "pairs" && (mainChanged || outputChanged))
                delete pending[token];
        }
        root._pending = pending;
        const s = Object.assign({}, root.state);
        s[section] = Object.assign({}, s[section]);
        s[section][key] = Object.assign({}, s[section][key] ?? {}, fields);
        root.state = s;
        saveDebounce.restart();
    }

    // ── Save hooks (called from the volume/mute setters only) ────────────────────

    // Default-sink writes: attribute by context — music_sink's own volume belongs
    // to the current pair; a physical sink used directly belongs to main[].
    function sinkVolumeSet(node: PwNode, vol: real): void {
        if (!node?.name)
            return;
        if (node.name === VirtualSink.musicSinkName)
            _set("pairs", VirtualSink.musicOutput, {
                vsink: vol,
                vsinkMuted: false // volume setters unmute
            });
        else if (node.name !== VirtualSink.notificationSinkName)
            _set("main", node.name, {
                vol,
                muted: false
            });
    }

    function sinkMutedSet(node: PwNode, muted: bool): void {
        if (!node?.name)
            return;
        if (node.name === VirtualSink.musicSinkName)
            _set("pairs", VirtualSink.musicOutput, {
                vsinkMuted: muted
            });
        else if (node.name !== VirtualSink.notificationSinkName)
            _set("main", node.name, {
                muted
            });
    }

    // The "Music" slider: the routed physical device, keyed by pair.
    function outputVolumeSet(outputName: string, vol: real): void {
        // The physical node is shared hardware. In direct-output mode it belongs
        // to main[], even if the same device is selected in the MVS dropdown.
        if (Audio.sink?.name === outputName) {
            _set("main", outputName, {
                vol,
                muted: false
            });
            return;
        }
        _set("pairs", outputName, {
            phys: vol,
            physMuted: false
        });
    }

    function outputMutedSet(outputName: string, muted: bool): void {
        if (Audio.sink?.name === outputName) {
            _set("main", outputName, {
                muted
            });
            return;
        }
        _set("pairs", outputName, {
            physMuted: muted
        });
    }

    function sourceVolumeSet(node: PwNode, vol: real): void {
        if (node?.name)
            _set("sources", node.name, {
                vol,
                muted: false
            });
    }

    function sourceMutedSet(node: PwNode, muted: bool): void {
        if (node?.name)
            _set("sources", node.name, {
                muted
            });
    }

    function streamVolumeSet(node: PwNode, vol: real): void {
        if (!node?.isSink || node.name === VirtualSink.musicLoopbackName || node.name === VirtualSink.notificationLoopbackName)
            return;
        _set("apps", Audio.getStreamName(node), {
            vol,
            muted: false
        });
    }

    function streamMutedSet(node: PwNode, muted: bool): void {
        if (!node?.isSink || node.name === VirtualSink.musicLoopbackName || node.name === VirtualSink.notificationLoopbackName)
            return;
        _set("apps", Audio.getStreamName(node), {
            muted
        });
    }

    function alsaVolumeSet(control: string, vol: real): void {
        _set("alsa", control, {
            vol
        });
    }

    function alsaMutedSet(control: string, muted: bool): void {
        _set("alsa", control, {
            muted
        });
    }

    function recallAlsa(control: string): var {
        return root.state.alsa[control];
    }

    // ── Restore: pending applies wait for the node to become ready ──────────────
    function _schedule(token: string, node: PwNode, vol: real, muted: var): void {
        if (!root.loaded || !node)
            return;
        const p = Object.assign({}, root._pending);
        p[token] = {
            node,
            vol,
            muted,
            output: VirtualSink.musicOutput
        };
        root._pending = p;
        root._pumpTicks = 0;
        pump.start();
    }

    function _applyNow(token: string, entry: var): void {
        const a = entry.node.audio;
        if (entry.vol >= 0)
            a.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, entry.vol));
        if (entry.muted !== undefined)
            a.muted = !!entry.muted;
        console.log(`[AudioPersist] restore ${token} -> ${entry.vol >= 0 ? Math.round(entry.vol * 100) + "%" : "keep"}${entry.muted !== undefined ? (entry.muted ? " muted" : " unmuted") : ""}`);
    }

    function _pump(): void {
        const rest = {};
        for (const token of Object.keys(root._pending)) {
            const entry = root._pending[token];
            try {
                if (!entry.node)
                    continue; // device vanished while pending
                // A delayed restore is valid only while its device still owns
                // this context. Rapid dropdown changes must not leak old pairs.
                if (token === "vsink" && (entry.node !== VirtualSink.musicSink || entry.output !== VirtualSink.musicOutput))
                    continue;
                if (token.startsWith("pair:") && (entry.node !== VirtualSink.musicOutputNode || entry.output !== VirtualSink.musicOutput || entry.node === Audio.sink))
                    continue;
                if (token.startsWith("main:") && entry.node !== Audio.sink)
                    continue;
                if (token.startsWith("source:") && entry.node !== Audio.source)
                    continue;
                if (entry.node.ready && entry.node.audio)
                    _applyNow(token, entry);
                else
                    rest[token] = entry;
            } catch (e) {} // node destroyed mid-check: drop it
        }
        root._pending = rest;
        if (Object.keys(rest).length === 0 || ++root._pumpTicks > 40)
            pump.stop();
    }

    // ── Restore logic ────────────────────────────────────────────────────────────

    // The music chain: pair (music_sink -> current output). Applies vsink to
    // music_sink always; phys to the routed device unless that device is
    // simultaneously the direct default sink (then main[] owns its node).
    function applyPair(): void {
        if (!root.loaded)
            return;
        const out = VirtualSink.musicOutput;
        if (!out)
            return;
        const p = AudioPolicy.pair(root.state.pairs[out]);
        if (VirtualSink.musicSink)
            _schedule("vsink", VirtualSink.musicSink, p.vsink, p.vsinkMuted);
        const node = VirtualSink.musicOutputNode;
        if (node && Audio.sink?.name !== node.name)
            _schedule(`pair:${out}`, node, p.phys, p.physMuted);
    }

    function applyMainSink(): void {
        if (!root.loaded)
            return;
        const s = Audio.sink;
        if (!s?.name || s.name === VirtualSink.notificationSinkName)
            return;
        if (s.name === VirtualSink.musicSinkName) {
            // Back on the music chain: the pair re-owns the routed device.
            applyPair();
            return;
        }
        const m = AudioPolicy.direct(root.state.main[s.name]);
        _schedule(`main:${s.name}`, s, m.vol, m.muted);
    }

    function applySource(): void {
        if (!root.loaded)
            return;
        const s = Audio.source;
        if (!s?.name)
            return;
        const m = root.state.sources[s.name];
        if (m)
            _schedule(`source:${s.name}`, s, m.vol ?? -1, m.muted);
    }

    // ── Application streams: restore once per stream, when it first appears ─────
    function _applyStreams(): void {
        if (!root.loaded)
            return;
        let waiting = false;
        for (const s of Audio.streams) {
            if (!s?.isSink || s.name === VirtualSink.musicLoopbackName || s.name === VirtualSink.notificationLoopbackName)
                continue;
            if (root._appliedStreams[s.id])
                continue;
            if (!s.ready || !s.audio) {
                waiting = true;
                continue;
            }
            root._appliedStreams[s.id] = true;
            const m = root.state.apps[Audio.getStreamName(s)];
            if (m)
                _applyNow(`app:${Audio.getStreamName(s)}`, {
                    node: s,
                    vol: m.vol ?? -1,
                    muted: m.muted
                });
        }
        if (waiting && ++root._streamTicks < 40)
            streamsDebounce.restart();
    }

    // ── Triggers: settle-debounced so transient default flips apply nothing ─────
    function _init(): void {
        root.loaded = true;
        // Catch selections that were announced before our state file loaded.
        pairSettle.restart();
        sinkSettle.restart();
        sourceSettle.restart();
        streamsDebounce.restart();
        // Pull the Alsa singleton in at startup so hardware volumes restore at boot,
        // not on first popout open (its reads are otherwise ref-gated).
        Alsa.restoreSaved();
    }

    Connections {
        function onSinkChanged(): void {
            sinkSettle.restart();
        }

        function onSourceChanged(): void {
            sourceSettle.restart();
        }

        function onStreamsChanged(): void {
            root._streamTicks = 0;
            streamsDebounce.restart();
        }

        target: Audio
    }

    Connections {
        // Fires on manual pick, MRU fallback and boot restore alike. The pw-link
        // rerouting is async — settle before touching volumes.
        function onMusicOutputChanged(): void {
            pairSettle.restart();
        }

        function onMusicOutputNodeChanged(): void {
            pairSettle.restart();
        }

        function onMusicSinkChanged(): void {
            pairSettle.restart();
        }

        target: VirtualSink
    }

    Timer {
        id: sinkSettle

        interval: 400
        onTriggered: root.applyMainSink()
    }

    Timer {
        id: sourceSettle

        interval: 400
        onTriggered: root.applySource()
    }

    Timer {
        id: pairSettle

        interval: 300
        onTriggered: root.applyPair()
    }

    Timer {
        id: pump

        interval: 250
        repeat: true
        onTriggered: root._pump()
    }

    Timer {
        id: streamsDebounce

        interval: 300
        onTriggered: root._applyStreams()
    }

    Timer {
        id: saveDebounce

        interval: 500
        onTriggered: stateFile.setText(JSON.stringify(Object.assign({
            version: 2
        }, root.state)))
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/audio-volumes.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c?.version === 2) {
                    for (const sec of ["pairs", "main", "sources", "apps", "alsa"])
                        if (c[sec] && typeof c[sec] === "object")
                            root.state[sec] = c[sec];
                    root.state = Object.assign({}, root.state);
                } else if (c && typeof c === "object") {
                    // v1 flat file: salvage the harmless sections (alsa/source/app);
                    // drop sink:/music: — those were the race-poisoned ones.
                    const s = Object.assign({}, root.state);
                    for (const key of Object.keys(c)) {
                        const v = c[key];
                        if (!(v >= 0))
                            continue;
                        if (key.startsWith("alsa:"))
                            s.alsa[key.slice(5)] = {
                                vol: v
                            };
                        else if (key.startsWith("source:"))
                            s.sources[key.slice(7)] = {
                                vol: v
                            };
                        else if (key.startsWith("app:"))
                            s.apps[key.slice(4)] = {
                                vol: v
                            };
                    }
                    root.state = s;
                }
            } catch (e) {}
            root._init();
        }
        onLoadFailed: root._init()
    }
}
