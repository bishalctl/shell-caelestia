pragma Singleton

import QtQuick
import QtQuick.Dialogs as Native
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.utils

// AirDrop, through Owly (https://github.com/t4t5/owly): `owlyd` runs AWDL in userspace on
// ordinary Wi-Fi cards and leases an `awdl0` link; the `owly` CLI speaks AirDrop on it.
//
// This service owns two long-running children while receiving is on:
//   `owly radio up --for N`   holds the radio lease (polkit allows it from the active seat)
//   `owly receive ...`        the AirDrop receiver on awdl0:8771, started once the link is up
// plus short ones for `doctor --json`, `browse` and `send`. Everything the UI shows comes
// from parsing their stdout/stderr; there is no state file beyond our own settings.
Singleton {
    id: root

    // --- settings (persisted in $XDG_STATE_HOME/caelestia/airdrop.json) ---------------------
    property string name: Quickshell.env("HOSTNAME") || hostnameFile.text().trim() || "Linux"
    property string dir: `${Paths.home}/Downloads`
    property int windowMinutes: 10 // 0 = until turned off
    property bool autoAccept: false

    // --- doctor ---------------------------------------------------------------------------
    property bool installed: false // `owly` found on PATH
    property bool checked: false
    property var doctor: ({}) // last `owly doctor --json` report
    readonly property bool ready: installed && (doctor.missing?.length ?? -1) === 0
    readonly property var missing: doctor.missing ?? []
    readonly property string station: doctor.station ?? ""
    readonly property string mode: doctor.mode ?? ""
    readonly property int channel: doctor.channel ?? 0
    property bool checking: false

    // --- radio / receiver ------------------------------------------------------------------
    // "idle" | "starting" | "up" | "stopping"
    property string radioState: "idle"
    readonly property bool receiving: receiver.running
    readonly property bool active: radioState !== "idle"
    property string linkAddress
    property string lastError
    // Set when a setting the receiver was started with changed: bring it back once it exits
    property bool receiverRestartWanted: false
    // Seconds left in the visibility window (-1 = no limit / not visible)
    property int remaining: -1

    // --- incoming request (when autoAccept is off) ------------------------------------------
    // { sender, model, items: [{ name, type, size }], urls: [string], deadline }
    property var pending: null
    property int pendingRemaining: 0

    // --- history for this session -------------------------------------------------------------
    // Received: { kind: "file"|"url", path, name, time }
    property list<var> received: []
    // Sends: { id, target, files, state: "looking"|"sending"|"delivered"|"declined"|"failed", detail, sent, total }
    property list<var> sends: []

    // --- peers (owly browse) ----------------------------------------------------------------
    // { instance, name, addr }
    property list<var> peers: []
    readonly property bool browsing: browser.running

    // --- composing a send -------------------------------------------------------------------
    // What the compose box holds: a note or link, plus files staged from the picker or from
    // "Send via AirDrop" in a file manager. Hitting send shows the device picker (`picking`),
    // which keeps browsing until a device is chosen or the picker is dismissed.
    property string draftText
    property list<string> draftFiles: []
    readonly property bool hasDraft: draftText.trim() !== "" || draftFiles.length > 0
    property bool picking: false

    // Recent log lines for the details view
    property list<string> log: []

    signal fileReceived(path: string)
    // Something was staged from outside (file manager, IPC): the dashboard should show this tab
    signal composeRequested

    function pushLog(line: string): void {
        if (!line)
            return;
        const next = [...log, line];
        log = next.length > 60 ? next.slice(next.length - 60) : next;
    }

    // Settings are written only after the file has been read, so startup can't clobber it
    property bool settingsLoaded: false

    function saveSettings(): void {
        if (!settingsLoaded)
            return;
        settingsFile.setText(JSON.stringify({
            name,
            dir,
            windowMinutes,
            autoAccept
        }, null, 2));
    }

    function check(): void {
        if (checking)
            return;
        checking = true;
        doctorProc.running = true;
    }

    // Turn receiving on: bring the radio up for the window, then start the receiver.
    function turnOn(): void {
        if (!installed) {
            lastError = Tr.tr("owly is not installed");
            return;
        }
        if (radio.running)
            return;
        lastError = "";
        linkAddress = "";
        radioState = "starting";
        const seconds = windowMinutes > 0 ? windowMinutes * 60 : 0;
        radio.command = ["owly", "radio", "up", "--for", String(seconds)];
        radio.running = true;
        remaining = seconds > 0 ? seconds : -1;
        if (seconds > 0)
            countdown.start();
    }

    function turnOff(): void {
        countdown.stop();
        remaining = -1;
        pending = null;
        receiverRestart.stop();
        receiverRestartWanted = false;
        if (receiver.running)
            receiver.signal(2); // SIGINT: the receiver's own clean exit
        if (radio.running) {
            radioState = "stopping";
            radio.signal(2); // SIGINT: releases the lease and gives Wi-Fi back
        } else {
            radioState = "idle";
        }
    }

    function toggle(): void {
        if (active)
            turnOff();
        else
            turnOn();
    }

    function startReceiver(): void {
        if (receiver.running)
            return;
        const cmd = ["owly", "receive", "--dir", dir, "--name", name];
        if (autoAccept)
            cmd.push("--accept");
        receiver.command = cmd;
        receiver.running = true;
    }

    function accept(): void {
        if (!pending || !receiver.running)
            return;
        receiver.write("y\n");
        pushLog(Tr.tr("Accepted transfer from %1").arg(pending.sender));
        pending = null;
    }

    function decline(): void {
        if (!pending || !receiver.running)
            return;
        receiver.write("n\n");
        pushLog(Tr.tr("Declined transfer from %1").arg(pending.sender));
        pending = null;
    }

    // Look for nearby receivers. Needs the radio: turn it on first if it isn't.
    function browse(): void {
        if (browser.running)
            return;
        if (radioState !== "up") {
            browseWhenUp = true;
            if (!active)
                turnOn();
            return;
        }
        if (!picking)
            peers = [];
        browser.running = true;
    }

    property bool browseWhenUp: false

    // Send files to a receiver by name
    function send(target: string, files: list<string>): void {
        if (!files.length)
            return;
        sendPayload(target, {
            files,
            label: files.map(f => fileName(f)).join(", ")
        }, ["owly", "send", "--to", target, "--name", name, ...files]);
    }

    // Send a link: AirDrop carries URLs as their own item type, the phone opens them directly
    function sendUrl(target: string, url: string): void {
        sendPayload(target, {
            files: [],
            label: url
        }, ["owly", "send", "--to", target, "--name", name, "--url", url]);
    }

    // Send a note (and optionally files with it). AirDrop has no plain-text item owly can
    // send, so the note travels as a small text file written just before the send starts.
    function sendText(target: string, text: string, files: list<string>): void {
        const stamp = Tr.formatDateTime(new Date(), "yyyy-MM-dd HH.mm.ss");
        const note = `${Paths.cache}/airdrop/Note ${stamp}.txt`;
        const first = text.split("\n")[0];
        sendPayload(target, {
            files: [...files, note],
            label: [...files.map(f => fileName(f)), first.length > 40 ? `${first.slice(0, 40)}…` : first].join(", ")
        }, ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf \'%s\\n\' "$AIRDROP_NOTE" > "$1" && shift && exec owly send "$@"', "sh", note, "--to", target, "--name", name, ...files, note], {
            AIRDROP_NOTE: text
        });
    }

    function sendPayload(target: string, payload: var, command: list<string>, env: var): void {
        const id = Date.now();
        sends = [{
            id,
            target,
            files: payload.files,
            label: payload.label,
            state: "looking",
            detail: "",
            sent: 0,
            total: 0
        }, ...sends].slice(0, 10);
        const proc = sendComponent.createObject(root, {
            sendId: id,
            command,
            environment: env ?? ({})
        });
        proc.running = true;
    }

    // --- compose box ------------------------------------------------------------------------
    function stageFiles(files: list<string>): void {
        const next = [...draftFiles];
        for (const f of files)
            if (f && !next.includes(f))
                next.push(f);
        draftFiles = next;
    }

    function unstageFile(path: string): void {
        draftFiles = draftFiles.filter(f => f !== path);
        if (!hasDraft)
            picking = false;
    }

    function clearDraft(): void {
        draftText = "";
        draftFiles = [];
        picking = false;
    }

    function isUrl(text: string): bool {
        return /^(https?|ftp|mailto|file|tel|sms):/i.test(text) || /^www\.[^\s]+$/i.test(text);
    }

    // Send pressed: show the device picker and keep looking for receivers while it's up
    function startPicking(): void {
        if (!hasDraft || !installed)
            return;
        picking = true;
        browse();
    }

    function stopPicking(): void {
        picking = false;
    }

    // A device was chosen in the picker: send the draft to it
    function sendDraft(target: string): void {
        const text = draftText.trim();
        const files = [...draftFiles];
        if (!files.length && text && isUrl(text))
            sendUrl(target, text);
        else if (text)
            sendText(target, text, files);
        else if (files.length)
            send(target, files);
        clearDraft();
    }

    // "Send via AirDrop" from a file manager or the CLI: stage the files, open the tab, pick
    function shareFiles(files: list<string>): void {
        stageFiles(files.map(f => f.startsWith("file://") ? decodeURIComponent(f.slice(7)) : f));
        showTab();
        if (hasDraft)
            startPicking();
    }

    function shareText(text: string): void {
        if (!text.trim())
            return;
        draftText = text;
        showTab();
        startPicking();
    }

    // Open the file chooser for the compose box. It lives here, not in the tab: the dashboard
    // unloads when it loses focus to the dialog, which would take the dialog's handlers with it.
    function pickFiles(win: var): void {
        // The dialog needs a window to attach to; the drawers window outlives the tab
        if (win)
            filePicker.parentWindow = win;
        filePicker.open();
    }

    function fileUrl(path: string): string {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    // Keep the chooser in the service: the dashboard unloads when a dialog
    // takes focus, but the accepted folder still needs to be applied.
    function pickDirectory(win: var): void {
        if (win)
            directoryPicker.parentWindow = win;
        directoryPicker.currentFolder = fileUrl(dir);
        directoryPicker.open();
    }

    function showTab(): void {
        const s = ShellState.forActive();
        if (s)
            s.dashboard = true;
        composeRequested();
    }

    function updateSend(id: int, patch: var): void {
        sends = sends.map(s => s.id === id ? Object.assign({}, s, patch) : s);
    }

    function openPath(path: string): void {
        Quickshell.execDetached([...GlobalConfig.launcher.launchPrefix, "xdg-open", path]);
    }

    function openDir(): void {
        Quickshell.execDetached([...GlobalConfig.launcher.launchPrefix, "xdg-open", dir]);
    }

    // Recognized image files are decoded and copied as PNG for clipboard clients.
    readonly property var imageMimes: ({
        png: "image/png",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        gif: "image/gif",
        webp: "image/webp",
        bmp: "image/bmp",
        svg: "image/svg+xml",
        tif: "image/tiff",
        tiff: "image/tiff",
        avif: "image/avif",
        heic: "image/heic"
    })

    function imageMime(path: string): string {
        const i = path.lastIndexOf(".");
        return i >= 0 ? (imageMimes[path.slice(i + 1).toLowerCase()] ?? "") : "";
    }

    // Copy a received item: a link as text, an image as the picture itself, anything else as its path
    function copy(entry: var): void {
        if (entry.kind === "url") {
            Quickshell.execDetached(["wl-copy", "--", entry.path]);
            Toaster.toast(Tr.tr("Link copied"), entry.path, "content_copy");
            return;
        }
        const mime = imageMime(entry.path);
        if (mime) {
            CUtils.copyImage(fileUrl(entry.path), () => {
                Toaster.toast(Tr.tr("Image copied"), fileName(entry.path), "content_copy");
                Clipboard.reload();
            }, error => Toaster.toast(Tr.tr("Couldn't copy image"), error, "error"));
        } else {
            Quickshell.execDetached(["wl-copy", "--", entry.path]);
            Toaster.toast(Tr.tr("Path copied"), entry.path, "content_copy");
        }
    }

    function formatRemaining(seconds: int): string {
        if (seconds < 0)
            return Tr.tr("until turned off");
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        return m > 0 ? `${m}:${String(s).padStart(2, "0")}` : `0:${String(s).padStart(2, "0")}`;
    }

    // Rust's {:?} quoting: "like \"this\"" -> like "this"
    function unquote(s: string): string {
        const m = /^"(.*)"$/.exec(s.trim());
        if (!m)
            return s.trim();
        try {
            return JSON.parse(m[0]);
        } catch (e) {
            return m[1];
        }
    }

    function fileName(path: string): string {
        const i = path.lastIndexOf("/");
        return i >= 0 ? path.slice(i + 1) : path;
    }

    Component.onDestruction: {
        if (receiver.running)
            receiver.signal(2);
        if (radio.running)
            radio.signal(2);
    }

    Native.FileDialog {
        id: filePicker

        title: Tr.tr("Send via AirDrop")
        fileMode: Native.FileDialog.OpenFiles
        onAccepted: {
            const files = [];
            for (let i = 0; i < selectedFiles.length; i++)
                files.push(decodeURIComponent(selectedFiles[i].toString().replace(/^file:\/\//, "")));
            root.stageFiles(files);
            root.showTab(); // the dashboard closed when the dialog took focus
        }
    }

    Native.FolderDialog {
        id: directoryPicker

        title: Tr.tr("Choose where AirDrop saves files")
        onAccepted: {
            const path = CUtils.toLocalFile(selectedFolder);
            if (path)
                root.dir = path;
            root.showTab();
        }
        onRejected: root.showTab()
    }

    FileView {
        id: hostnameFile

        path: "/etc/hostname"
        printErrors: false
    }

    FileView {
        id: settingsFile

        path: `${Paths.state}/airdrop.json`
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (typeof s.name === "string" && s.name)
                    root.name = s.name;
                if (typeof s.dir === "string" && s.dir)
                    root.dir = s.dir;
                if (typeof s.windowMinutes === "number")
                    root.windowMinutes = s.windowMinutes;
                if (typeof s.autoAccept === "boolean")
                    root.autoAccept = s.autoAccept;
            } catch (e) {}
            root.settingsLoaded = true;
            root.check();
        }
        onLoadFailed: {
            root.settingsLoaded = true;
            root.check();
        }
    }

    // `owly doctor --json`: is the card usable, and what stands in the way
    Process {
        id: doctorProc

        command: ["sh", "-c", "command -v owly >/dev/null 2>&1 || exit 127; exec owly doctor --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.doctor = JSON.parse(text);
                } catch (e) {
                    root.doctor = ({});
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.pushLog(text.trim());
            }
        }
        onExited: (code, status) => {
            root.installed = code !== 127;
            if (!root.installed)
                root.doctor = ({
                    missing: [{
                        id: "owly",
                        say: Tr.tr("owly is not installed. Enable services.owly in the system configuration.")
                    }]
                });
            root.checked = true;
            root.checking = false;
        }
    }

    // The radio lease. Held for the whole visibility window.
    Process {
        id: radio

        stderr: SplitParser {
            onRead: line => {
                const l = line.trim();
                if (!l)
                    return;
                root.pushLog(l);
                let m;
                if ((m = /^(\S+) is up: (\S+) \(/.exec(l))) {
                    root.linkAddress = m[2];
                    root.radioState = "up";
                    root.startReceiver();
                    if (root.browseWhenUp) {
                        root.browseWhenUp = false;
                        root.browse();
                    }
                } else if ((m = /^owly: the radio went down: (.*)$/.exec(l))) {
                    root.lastError = m[1];
                } else if ((m = /^owly: (.*)$/.exec(l))) {
                    root.lastError = m[1];
                }
            }
        }
        onExited: (code, status) => {
            root.radioState = "idle";
            root.linkAddress = "";
            countdown.stop();
            root.remaining = -1;
            root.browseWhenUp = false;
            root.picking = false;
            if (receiver.running)
                receiver.signal(2);
            if (code === 3 && !root.lastError)
                root.lastError = Tr.tr("The radio can't come up right now");
            else if (code === 4 && !root.lastError)
                root.lastError = Tr.tr("No usable radio");
        }
    }

    // The AirDrop receiver on awdl0
    Process {
        id: receiver

        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                const l = line.trim();
                if (!l)
                    return;
                root.pending = null; // whatever was incoming has now landed
                if (l.startsWith("\"")) {
                    const url = root.unquote(l);
                    root.received = [{
                        kind: "url",
                        path: url,
                        name: url,
                        time: new Date()
                    }, ...root.received].slice(0, 30);
                    Toaster.toast(Tr.tr("Link received"), url, "link");
                } else {
                    root.received = [{
                        kind: "file",
                        path: l,
                        name: root.fileName(l),
                        time: new Date()
                    }, ...root.received].slice(0, 30);
                    root.fileReceived(l);
                    Toaster.toast(Tr.tr("File received"), root.fileName(l), "download_done");
                }
                root.pushLog(l);
            }
        }
        stderr: SplitParser {
            onRead: line => {
                const l = line.replace(/\s+$/, "");
                if (!l.trim())
                    return;
                let m;
                if ((m = /^(".*") \((".*")\) wants to send:$/.exec(l))) {
                    // With --accept the receiver has already said yes: show it as an incoming
                    // transfer, with no buttons or countdown, until the file lands.
                    const auto = root.autoAccept;
                    root.pending = {
                        sender: root.unquote(m[1]),
                        model: root.unquote(m[2]),
                        items: [],
                        urls: [],
                        auto
                    };
                    root.pendingRemaining = 15;
                    if (!auto)
                        pendingCountdown.restart();
                    root.pushLog(Tr.tr("%1 wants to send").arg(root.pending.sender));
                    if (auto)
                        Toaster.toast(Tr.tr("AirDrop from %1").arg(root.pending.sender), Tr.tr("Receiving…"), "ios_share");
                    else
                        Toaster.toast(Tr.tr("AirDrop from %1").arg(root.pending.sender), Tr.tr("Open the dashboard to accept"), "ios_share");
                } else if (root.pending && (m = /^ {2}(".*") (\S+) ?(\d+ bytes)?$/.exec(l))) {
                    const p = Object.assign({}, root.pending);
                    p.items = [...p.items, {
                        name: root.unquote(m[1]),
                        type: m[2],
                        size: m[3] ? parseInt(m[3]) : 0
                    }];
                    root.pending = p;
                } else if (root.pending && (m = /^ {2}(".*")$/.exec(l))) {
                    const p = Object.assign({}, root.pending);
                    p.urls = [...p.urls, root.unquote(m[1])];
                    root.pending = p;
                } else if (/^accept\? \[y\/N\]/.test(l)) {
                // prompt line, nothing to do: pending is already shown
                } else if (/^timed out$/.test(l) || /^the request was withdrawn$/.test(l)) {
                    root.pending = null;
                    root.pushLog(l);
                } else if ((m = /^transfer failed: (.*)$/.exec(l))) {
                    root.pending = null;
                    root.lastError = m[1];
                    root.pushLog(l);
                    Toaster.toast(Tr.tr("AirDrop transfer failed"), m[1], "error");
                } else {
                    root.pushLog(l);
                }
            }
        }
        onExited: (code, status) => {
            root.pending = null;
            if (root.receiverRestartWanted) {
                root.receiverRestartWanted = false;
                if (root.radioState === "up")
                    root.startReceiver();
            }
        }
    }

    // The receiver only reads its name, folder and --accept at start: restart it when they
    // change while it runs, debounced so typing a new name doesn't restart it per keystroke.
    Timer {
        id: receiverRestart

        interval: 800
        onTriggered: {
            if (!receiver.running || root.radioState !== "up")
                return;
            root.receiverRestartWanted = true;
            receiver.signal(2);
        }
    }

    function restartReceiverIfRunning(): void {
        if (settingsLoaded && receiver.running)
            receiverRestart.restart();
    }

    // `owly browse`: who answers /Discover on the link
    Process {
        id: browser

        command: ["owly", "browse", "--seconds", "8", "--name", root.name]
        stdout: SplitParser {
            onRead: line => {
                // "<instance>   "<name>" (<addr>)"
                const m = /^(\S+)\s+(".*") \((.*)\)\s*$/.exec(line.trim());
                if (!m)
                    return;
                const peer = {
                    instance: m[1],
                    name: root.unquote(m[2]),
                    addr: m[3]
                };
                if (!root.peers.some(p => p.instance === peer.instance))
                    root.peers = [...root.peers, peer];
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.pushLog(line.trim());
            }
        }
        onExited: {
            if (root.picking)
                rebrowse.restart();
        }
    }

    // While the device picker is up, scan again as soon as the last scan ends
    Timer {
        id: rebrowse

        interval: 500
        onTriggered: {
            if (root.picking && root.radioState === "up" && !browser.running)
                root.browse();
        }
    }

    Component {
        id: sendComponent

        Process {
            id: sendProc

            required property int sendId

            stdout: SplitParser {
                onRead: line => {
                    const l = line.trim();
                    let m;
                    if (l === "delivered") {
                        root.updateSend(sendProc.sendId, {
                            state: "delivered"
                        });
                        Toaster.toast(Tr.tr("AirDrop delivered"), root.sends.find(s => s.id === sendProc.sendId)?.target ?? "", "done");
                    } else if (l === "declined") {
                        root.updateSend(sendProc.sendId, {
                            state: "declined"
                        });
                    } else if ((m = /^failed: (.*)$/.exec(l))) {
                        root.updateSend(sendProc.sendId, {
                            state: "failed",
                            detail: m[1]
                        });
                    }
                }
            }
            stderr: SplitParser {
                splitMarker: "" // progress lines use \r, split on both
                onRead: chunk => {
                    for (const raw of chunk.split(/[\r\n]+/)) {
                        const l = raw.trim();
                        if (!l)
                            continue;
                        let m;
                        if ((m = /^(\d+) \/ (\d+) bytes$/.exec(l))) {
                            root.updateSend(sendProc.sendId, {
                                state: "sending",
                                sent: parseInt(m[1]),
                                total: parseInt(m[2])
                            });
                        } else if (/^sending to /.test(l)) {
                            root.updateSend(sendProc.sendId, {
                                state: "sending",
                                detail: Tr.tr("Waiting for the receiver to accept")
                            });
                            root.pushLog(l);
                        } else if (l === "accepted") {
                            root.updateSend(sendProc.sendId, {
                                detail: ""
                            });
                        } else if ((m = /^owly: (.*)$/.exec(l))) {
                            root.updateSend(sendProc.sendId, {
                                state: "failed",
                                detail: m[1]
                            });
                            root.pushLog(l);
                        } else {
                            root.pushLog(l);
                        }
                    }
                }
            }
            onExited: (code, status) => {
                const s = root.sends.find(x => x.id === sendProc.sendId);
                if (s && (s.state === "looking" || s.state === "sending"))
                    root.updateSend(sendProc.sendId, {
                        state: "failed",
                        detail: s.detail || Tr.tr("No receiver answered")
                    });
                sendProc.destroy();
            }
        }
    }

    Timer {
        id: countdown

        interval: 1000
        repeat: true
        onTriggered: {
            if (root.remaining > 0)
                root.remaining -= 1;
            if (root.remaining === 0)
                stop();
        }
    }

    // The receiver declines by itself after 15 s without an answer
    Timer {
        id: pendingCountdown

        interval: 1000
        repeat: true
        running: root.pending !== null && !root.pending.auto
        onTriggered: {
            if (root.pendingRemaining > 0)
                root.pendingRemaining -= 1;
            else
                root.pending = null;
        }
    }

    onNameChanged: {
        saveSettings();
        restartReceiverIfRunning();
    }
    onDirChanged: {
        saveSettings();
        restartReceiverIfRunning();
    }
    onWindowMinutesChanged: saveSettings()
    onAutoAcceptChanged: {
        saveSettings();
        restartReceiverIfRunning();
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function on(): void {
            root.turnOn();
        }

        function off(): void {
            root.turnOff();
        }

        function status(): string {
            return root.radioState + (root.receiving ? " receiving" : "");
        }

        // Stage files for sending and open the AirDrop tab with the device picker.
        // Paths are separated by newlines; file:// URLs are accepted too.
        function share(paths: string): void {
            root.shareFiles(paths.split("\n").map(p => p.trim()).filter(p => p));
        }

        // Stage a note or link for sending and open the AirDrop tab with the device picker
        function shareText(text: string): void {
            root.shareText(text);
        }

        target: "airdrop"
    }
}
