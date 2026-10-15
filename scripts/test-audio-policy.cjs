// Run without touching the live PipeWire server: node --test scripts/test-audio-policy.cjs
const assert = require("node:assert/strict");
const { mkdtempSync, readFileSync, writeFileSync, rmSync } = require("node:fs");
const { join } = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");
const vm = require("node:vm");

const repo = join(__dirname, "..");
const policy = vm.createContext({});
vm.runInContext(readFileSync(join(repo, "services/audio/Policy.js"), "utf8").replace(/^\.pragma library\s*/, ""), policy);

function timer() {
    return { restart() {}, start() {}, stop() {} };
}

// Exercise the real QML service methods with fake nodes/timers, not a second
// implementation of their behavior. Only QML parameter/return annotations are removed.
function service(file, root, globals = {}) {
    const context = vm.createContext({ root, AudioPolicy: policy, console: { log() {} }, ...globals });
    // Qt's QV4 engine does not implement Array.flatMap, unlike Node.
    vm.runInContext("Array.prototype.flatMap = undefined", context);
    const qml = readFileSync(join(repo, "services", file), "utf8");
    const methods = [...qml.matchAll(/^    function (\w+)\(([^)]*)\)(?:\s*:\s*\w+)? \{\n([\s\S]*?)^    \}/gm)];
    assert.ok(methods.length > 0);
    for (const [, name, params, body] of methods) {
        vm.runInContext(`function ${name}(${params.replace(/:\s*\w+/g, "")}) {\n${body}\n}`, context);
        root[name] = context[name];
    }
    return root;
}

function node(name, volume = 1) {
    return { name, ready: true, audio: { volume, muted: false } };
}

function persistence() {
    const output = node("HDMI");
    const music = node("music_sink");
    const audio = { sink: music, source: null, streams: [] };
    const virtual = { musicSinkName: "music_sink", notificationSinkName: "notification_sink", musicOutput: output.name, musicOutputNode: output, musicSink: music };
    const root = service("AudioPersist.qml", {
        loaded: true,
        state: { pairs: {}, main: {}, sources: {}, apps: {}, alsa: {} },
        _pending: {},
        _pumpTicks: 0
    }, { Audio: audio, VirtualSink: virtual, GlobalConfig: { services: { maxVolume: 1 } }, pump: timer(), saveDebounce: timer() });
    return { root, audio, virtual, output, music };
}

function devices() {
    const music = node("music_sink");
    const hdmi = node("HDMI");
    const speaker = node("speaker");
    const mic = node("mic");
    const usbMic = node("usb-mic");
    const audio = { sinks: [music, hdmi, speaker], sources: [mic, usbMic], sink: music, source: mic };
    const pipewire = {};
    let saved;
    const root = service("AudioDevices.qml", { loaded: true, mainOutput: "music_sink", mainInput: "mic", sourceStack: [], blockedSinks: [], blockedSources: [] }, {
        Audio: audio,
        Pipewire: pipewire,
        stateFile: { setText(text) { saved = JSON.parse(text); } }
    });
    return { root, audio, pipewire, music, hdmi, speaker, mic, usbMic, saved: () => saved };
}

test("new MVS routes default to Main Sound 40%, output 100%", () => {
    const { root, output, music } = persistence();
    root.applyPair();
    root._pump();
    assert.equal(music.audio.volume, 0.4);
    assert.equal(output.audio.volume, 1);
});

test("direct mode defaults to 40%, never a value derived from an MVS pair", () => {
    const { root, audio, output } = persistence();
    root.state.pairs.HDMI = { vsink: 0.9, phys: 0.8 };
    audio.sink = output;
    root.applyMainSink();
    root._pump();
    assert.equal(output.audio.volume, 0.4);
});

test("direct mode restores only its own saved volume and mute", () => {
    const { root, audio, output } = persistence();
    root.state.pairs.HDMI = { vsink: 0.9, phys: 1 };
    root.state.main.HDMI = { vol: 0.23, muted: true };
    audio.sink = output;
    root.applyMainSink();
    root._pump();
    assert.equal(output.audio.volume, 0.23);
    assert.equal(output.audio.muted, true);
});

test("switching MVS outputs restores each independent pair", () => {
    const { root, virtual, music, output } = persistence();
    root.sinkVolumeSet(music, 0.32);
    root.outputVolumeSet("HDMI", 0.76);
    virtual.musicOutput = "speaker";
    virtual.musicOutputNode = node("speaker");
    root.sinkVolumeSet(music, 0.61);
    root.outputVolumeSet("speaker", 0.85);
    virtual.musicOutput = "HDMI";
    virtual.musicOutputNode = output;
    root.applyPair();
    root._pump();
    assert.equal(music.audio.volume, 0.32);
    assert.equal(output.audio.volume, 0.76);
    assert.equal(root.state.pairs.speaker.vsink, 0.61);
    assert.equal(root.state.pairs.speaker.phys, 0.85);
});

test("switching direct -> MVS restores the pair, not direct volume", () => {
    const { root, audio, virtual, output, music } = persistence();
    root.state.main.HDMI = { vol: 0.19 };
    root.state.pairs.HDMI = { vsink: 0.63, phys: 0.88 };
    audio.sink = output;
    root.applyPair();
    root.applyMainSink();
    root._pump();
    assert.equal(output.audio.volume, 0.19);
    audio.sink = virtual.musicSink;
    root.applyMainSink();
    root._pump();
    assert.equal(music.audio.volume, 0.63);
    assert.equal(output.audio.volume, 0.88);
});

test("a shared physical-output slider cannot poison the MVS pair in direct mode", () => {
    const { root, audio, output } = persistence();
    root.state.pairs.HDMI = { vsink: 0.32, phys: 0.76 };
    audio.sink = output;
    root.outputVolumeSet("HDMI", 0.18);
    root.outputMutedSet("HDMI", true);
    assert.equal(root.state.main.HDMI.vol, 0.18);
    assert.equal(root.state.main.HDMI.muted, true);
    assert.equal(root.state.pairs.HDMI.phys, 0.76);
    assert.equal(root.state.pairs.HDMI.vsink, 0.32);
});

test("a delayed old pair is discarded after changing the output", () => {
    const { root, virtual, music, output } = persistence();
    root.state.pairs.HDMI = { vsink: 0.8, phys: 0.9 };
    root.applyPair();
    virtual.musicOutput = "speaker";
    virtual.musicOutputNode = node("speaker");
    root._pump();
    assert.equal(music.audio.volume, 1);
    assert.equal(output.audio.volume, 1);
});

test("a delayed pair cannot overwrite a newly direct output", () => {
    const { root, audio, output } = persistence();
    root.state.pairs.HDMI = { phys: 0.9 };
    root.applyPair();
    audio.sink = output;
    root._pump();
    assert.equal(output.audio.volume, 1);
});

test("a user slider update cancels its outstanding restore", () => {
    const { root, output } = persistence();
    root.applyPair();
    output.audio.volume = 0.25;
    root.outputVolumeSet("HDMI", 0.25);
    root._pump();
    assert.equal(output.audio.volume, 0.25);
});

test("MVS disconnect chooses connected unblocked MRU, retaining missing history", () => {
    const history = ["HDMI", "blocked", "speaker", "headphones"];
    assert.equal(policy.musicOutput("HDMI", ["blocked", "speaker", "headphones"], ["HDMI", "blocked", "speaker", "headphones"], history, ["blocked"], true), "speaker");
    assert.equal(policy.recent(history, "speaker").join(), "speaker,HDMI,blocked,headphones");
});

test("newly connected blocked devices never steal the MVS route", () => {
    assert.equal(policy.musicOutput("HDMI", ["HDMI", "blocked"], ["HDMI"], ["HDMI"], ["blocked"], true), "HDMI");
});

test("unblocked hotplug keeps the existing auto-connect behavior", () => {
    assert.equal(policy.musicOutput("HDMI", ["HDMI", "headphones"], ["HDMI"], ["HDMI"], [], true), "headphones");
});

test("all physical devices blocked means no automatic MVS route", () => {
    assert.equal(policy.musicOutput("gone", ["blocked"], ["gone", "blocked"], ["gone", "blocked"], ["blocked"], true), "");
});

test("manually chosen blocked devices stay selectable", () => {
    assert.equal(policy.musicOutput("blocked", ["blocked"], ["blocked"], [], ["blocked"], true), "blocked");
    const { root, hdmi, pipewire } = devices();
    root.blockedSinks = ["HDMI"];
    root.selectSink(hdmi);
    root.reconcile();
    assert.equal(pipewire.preferredDefaultAudioSink, hdmi);
});

test("direct disconnect falls back to MVS despite an intervening WirePlumber default", () => {
    const { root, audio, pipewire, music, speaker } = devices();
    root.mainOutput = "HDMI";
    audio.sinks = [music, speaker];
    audio.sink = speaker;
    root.reconcile();
    assert.equal(root.mainOutput, "music_sink");
    assert.equal(pipewire.preferredDefaultAudioSink, music);
});

test("a blocked MVS is skipped during direct-disconnect fallback", () => {
    const { root, audio, music, speaker, pipewire } = devices();
    root.mainOutput = "HDMI";
    root.blockedSinks = ["music_sink"];
    audio.sinks = [music, speaker];
    root.reconcile();
    assert.equal(pipewire.preferredDefaultAudioSink, speaker);
});

test("microphone disconnect skips blocked inputs", () => {
    const { root, audio, usbMic, pipewire } = devices();
    const fallback = node("fallback-mic");
    audio.sources = [usbMic, fallback];
    root.sourceStack = ["mic", "usb-mic", "fallback-mic"];
    root.blockedSources = ["usb-mic"];
    root.reconcile();
    assert.equal(pipewire.preferredDefaultAudioSource, fallback);
});

test("block state and priority persist by stable device name", () => {
    const { root, saved, usbMic } = devices();
    root.toggleSinkBlocked("HDMI");
    root.toggleSourceBlocked("mic");
    root.selectSource(usbMic);
    assert.deepEqual(saved().blockedSinks, ["HDMI"]);
    assert.deepEqual(saved().blockedSources, ["mic"]);
    assert.deepEqual(saved().sourceStack, ["usb-mic"]);
    root.toggleSinkBlocked("HDMI");
    assert.deepEqual(saved().blockedSinks, []);
});

function routing() {
    const output = node("HDMI");
    const root = service("VirtualSink.qml", {
        _stateLoaded: true, _relinkPending: false,
        musicOutput: "HDMI", musicOutputNode: output,
        musicLoopbackName: "music_sink.output", musicLoopback: node("music_sink.output"),
        musicLinks: [{ target: output, state: 6 }, { target: output, state: 6 }]
    }, { AudioDevices: { loaded: true }, PwLinkState: { Error: 0, Unlinked: 1 }, relinkDebounce: timer(), relinkProc: { running: false } });
    return { root, output };
}

test("healthy game/audio links require no relink or volume reset", () => {
    const { root } = routing();
    root.checkMusicRoute();
    assert.equal(root._relinkPending, false);
});

test("game launch losing the selected route automatically queues repair", () => {
    const { root } = routing();
    root.musicLinks = [];
    root.checkMusicRoute();
    assert.equal(root._relinkPending, true);
});

test("a missing stereo channel automatically queues repair", () => {
    const { root } = routing();
    root.musicLinks.pop();
    root.checkMusicRoute();
    assert.equal(root._relinkPending, true);
});

test("a game/session-manager move to the wrong physical output queues repair", () => {
    const { root } = routing();
    root.musicLinks[0].target = node("wrong-device");
    root.checkMusicRoute();
    assert.equal(root._relinkPending, true);
});

test("errored links queue repair", () => {
    const { root } = routing();
    root.musicLinks[0].state = 0;
    root.checkMusicRoute();
    assert.equal(root._relinkPending, true);
    assert.equal(root._resetMusicRoute, true);
});

test("paused but healthy links are left alone while playback is idle", () => {
    const { root } = routing();
    root.musicLinks.forEach(link => link.state = 5);
    root.checkMusicRoute();
    assert.equal(root._relinkPending, false);
});

test("failed negotiations force old links to be recreated", () => {
    const proc = { running: false };
    const root = service("VirtualSink.qml", { _relinkPending: true, _resetMusicRoute: true, musicOutput: "HDMI", musicLoopbackName: "music_sink.output" }, { relinkProc: proc });
    root._runRelink();
    assert.ok(proc.command[2].startsWith("(\n"));
    assert.equal(root._resetMusicRoute, false);
    assert.match(proc.command[2], /HDMI:playback_FL/);
});

test("zero-volume caches are preserved rather than treated as missing", () => {
    assert.equal(policy.pair({ vsink: 0, phys: 0 }).vsink, 0);
    assert.equal(policy.pair({ vsink: 0, phys: 0 }).phys, 0);
    assert.equal(policy.direct({ vol: 0 }).vol, 0);
});

test("returning from a lost direct device restores the last usable MVS pair", () => {
    const { root, virtual, output, music, audio } = persistence();
    root.state.pairs.HDMI = { vsink: 0.31, phys: 0.82 };
    root.state.main.HDMI = { vol: 0.12 };
    audio.sink = node("disconnected-usb");
    const target = policy.mainOutput(audio.sink.name, [music.name, output.name], [], music.name);
    assert.equal(target, music.name);
    audio.sink = virtual.musicSink;
    root.applyMainSink();
    root._pump();
    assert.equal(music.audio.volume, 0.31);
    assert.equal(output.audio.volume, 0.82);
});

test("rapid route changes serialize and eventually use the latest selection", () => {
    const proc = { running: true };
    const root = service("VirtualSink.qml", { _relinkPending: true, musicOutput: "old", musicLoopbackName: "music_sink.output" }, { relinkProc: proc });
    root._runRelink();
    assert.equal(root._relinkPending, true);
    root.musicOutput = "new";
    proc.running = false;
    root._runRelink();
    assert.equal(root._relinkPending, false);
    assert.match(proc.command[2], /new:playback_FL/);
    assert.doesNotMatch(proc.command[2], /old:playback_FL/);
});

function relink(links, targets = ["HDMI"]) {
    const dir = mkdtempSync("/tmp/opencode/audio-routing-test-");
    try {
        const log = join(dir, "calls");
        writeFileSync(join(dir, "pw-link"), `#!${process.execPath}\nconst fs = require('node:fs');\nconst args = process.argv.slice(2);\nif (args[0] === '-l') process.stdout.write(process.env.TEST_LINKS);\nelse fs.appendFileSync(process.env.TEST_LOG, JSON.stringify(args) + '\\n');\n`, { mode: 0o755 });
        const { root } = routing();
        const result = spawnSync("sh", ["-c", root._relinkScript("music_sink.output", targets)], { encoding: "utf8", env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, TEST_LINKS: links, TEST_LOG: log } });
        assert.equal(result.status, 0, result.stderr);
        try {
            return readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
        } catch (error) {
            if (error.code === "ENOENT") return [];
            throw error;
        }
    } finally {
        rmSync(dir, { recursive: true });
    }
}

test("the actual repair shell script leaves healthy links untouched", () => {
    assert.deepEqual(relink("music_sink.output:output_FL\n  |-> HDMI:playback_FL\nmusic_sink.output:output_FR\n  |-> HDMI:playback_FR\n"), []);
});

test("the repair script adds only the missing channel", () => {
    assert.deepEqual(relink("music_sink.output:output_FL\n  |-> HDMI:playback_FL\n"), [["music_sink.output:output_FR", "HDMI:playback_FR"]]);
});

test("the repair script removes a wrong route, not application links", () => {
    assert.deepEqual(relink("music_sink.output:output_FL\n  |-> wrong:playback_FL\nSteam:output_FL\n  |-> music_sink:playback_FL\n"), [
        ["-d", "music_sink.output:output_FL", "wrong:playback_FL"],
        ["music_sink.output:output_FL", "HDMI:playback_FL"],
        ["music_sink.output:output_FR", "HDMI:playback_FR"]
    ]);
});

test("an empty eligible set disconnects stale links without choosing a blocked output", () => {
    assert.deepEqual(relink("music_sink.output:output_FL\n  |-> blocked:playback_FL\n", []), [["-d", "music_sink.output:output_FL", "blocked:playback_FL"]]);
});

test("repair commands quote device names rather than treating them as shell code", () => {
    assert.deepEqual(relink("", ["HDMI'odd"]), [
        ["music_sink.output:output_FL", "HDMI'odd:playback_FL"],
        ["music_sink.output:output_FR", "HDMI'odd:playback_FR"]
    ]);
});
