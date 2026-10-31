pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// ALSA hardware mixer (Master / Speaker / Headphone) for the internal sound card.
// Quickshell only exposes PipeWire, so the raw ALSA controls need `amixer`. Volumes
// are 0-100. Reads are ref-gated (only while the audio popout is open); writes are
// optimistic + debounced so dragging a slider doesn't spawn an amixer storm.
Singleton {
    id: root

    // Internal card. NixOS names it "Generic_1"; hw:<name> is stable across reboots
    // (unlike the numeric index, which shifts when USB audio devices come and go).
    readonly property string card: "hw:Generic_1"

    property bool available: false

    property int masterVolume: 100
    property bool masterMuted: false
    property int speakerVolume: 100
    property bool speakerMuted: false
    property int headphoneVolume: 100
    property bool headphoneMuted: false

    property int refCount
    property bool _restoreWanted: false
    property var _pendingVol: []

    // Slider position for Headphone/AUX: the control reads 0 while nothing is plugged
    // into the jack, so fall back to the last persisted volume — the row's icon still
    // shows the disconnected/muted state.
    readonly property int headphoneDisplayVolume: headphoneVolume > 0 ? headphoneVolume : Math.round(Math.max(0, (AudioPersist.state.alsa["Headphone"]?.vol ?? 0) * 100))

    function setVolume(control: string, percent: int): void {
        const clamped = Math.max(0, Math.min(100, Math.round(percent)));
        // Optimistic local update for a responsive slider; the periodic refresh reconciles.
        if (control === "Master")
            root.masterVolume = clamped;
        else if (control === "Speaker")
            root.speakerVolume = clamped;
        else if (control === "Headphone")
            root.headphoneVolume = clamped;
        _pendingVol = ["amixer", "-D", root.card, "set", control, `${clamped}%`];
        volDebounce.restart();
        AudioPersist.alsaVolumeSet(control, clamped / 100);
    }

    function setMuted(control: string, muted: bool): void {
        if (control === "Master")
            root.masterMuted = muted;
        else if (control === "Speaker")
            root.speakerMuted = muted;
        else if (control === "Headphone")
            root.headphoneMuted = muted;
        muteProc.command = ["amixer", "-D", root.card, "set", control, muted ? "mute" : "unmute"];
        muteProc.running = true;
        AudioPersist.alsaMutedSet(control, muted);
    }

    function refresh(): void {
        getProc.running = true;
    }

    // Called by AudioPersist once its state file is loaded: read the hardware, then
    // apply the persisted volumes ONCE (in getProc's handler). Also serves as the
    // boot-time read — normal reads are ref-gated behind the popout being open.
    function restoreSaved(): void {
        _restoreWanted = true;
        refresh();
    }

    function _applySaved(): void {
        const cmds = [];
        for (const c of ["Master", "Speaker", "Headphone"]) {
            const saved = AudioPersist.recallAlsa(c);
            if (!saved)
                continue;
            const hw = c === "Master" ? root.masterVolume : c === "Speaker" ? root.speakerVolume : root.headphoneVolume;
            const hwMuted = c === "Master" ? root.masterMuted : c === "Speaker" ? root.speakerMuted : root.headphoneMuted;
            if (saved.vol >= 0) {
                const pct = Math.max(0, Math.min(100, Math.round(saved.vol * 100)));
                if (pct !== hw) {
                    cmds.push(`amixer -D ${root.card} set ${c} ${pct}% 2>/dev/null`);
                    // Optimistic; the next periodic read reconciles.
                    if (c === "Master")
                        root.masterVolume = pct;
                    else if (c === "Speaker")
                        root.speakerVolume = pct;
                    else
                        root.headphoneVolume = pct;
                }
            }
            if (saved.muted !== undefined && !!saved.muted !== hwMuted) {
                cmds.push(`amixer -D ${root.card} set ${c} ${saved.muted ? "mute" : "unmute"} 2>/dev/null`);
                if (c === "Master")
                    root.masterMuted = !!saved.muted;
                else if (c === "Speaker")
                    root.speakerMuted = !!saved.muted;
                else
                    root.headphoneMuted = !!saved.muted;
            }
        }
        if (cmds.length > 0) {
            console.log(`[Alsa] restore: ${cmds.length} change(s)`);
            restoreProc.command = ["sh", "-c", cmds.join("; ")];
            restoreProc.running = true;
        }
    }

    Process {
        id: restoreProc
    }

    Timer {
        id: volDebounce

        interval: 40
        onTriggered: {
            if (volProc.running) {
                restart(); // amixer still busy, retry shortly with the latest pending value
                return;
            }
            volProc.command = root._pendingVol;
            volProc.running = true;
        }
    }

    Process {
        id: volProc
    }

    Process {
        id: muteProc
    }

    // Periodic re-read while the popout is open, so external changes (volume keys,
    // pavucontrol) are reflected. triggeredOnStart gives an immediate read on open.
    Timer {
        running: root.refCount > 0
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: getProc.running = true
    }

    Process {
        id: getProc

        command: ["sh", "-c", `for c in Master Speaker Headphone; do out=$(amixer -D ${root.card} get "$c" 2>/dev/null); pct=$(printf '%s' "$out" | grep -om1 '[0-9]*%' | tr -d '%'); st=$(printf '%s' "$out" | grep -om1 '\\[on\\]\\|\\[off\\]'); printf '%s|%s|%s\\n' "$c" "$pct" "$st"; done`]

        stdout: StdioCollector {
            onStreamFinished: {
                let any = false;
                for (const line of text.trim().split("\n")) {
                    const [control, pct, st] = line.split("|");
                    if (pct === "" && st === "")
                        continue;
                    any = true;
                    const vol = parseInt(pct, 10) || 0;
                    const muted = st === "[off]";
                    if (control === "Master") {
                        root.masterVolume = vol;
                        root.masterMuted = muted;
                    } else if (control === "Speaker") {
                        root.speakerVolume = vol;
                        root.speakerMuted = muted;
                    } else if (control === "Headphone") {
                        root.headphoneVolume = vol;
                        root.headphoneMuted = muted;
                    }
                }
                root.available = any;
                if (root._restoreWanted && any) {
                    root._restoreWanted = false;
                    root._applySaved();
                }
            }
        }
    }
}
