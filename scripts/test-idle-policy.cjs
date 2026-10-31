// Run without locking the live session: node --test scripts/test-idle-policy.cjs
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const vm = require("node:vm");

const source = readFileSync(join(__dirname, "../services/KeepAwake.qml"), "utf8");
const monitorsSource = readFileSync(join(__dirname, "../daemons/IdleMonitors.qml"), "utf8");

// The user's shell.json: lock -> dpms -> suspend-then-hibernate
const userTimeouts = [
    { idleAction: "lock", timeout: 900 },
    { idleAction: "dpms off", returnAction: "dpms on", timeout: 1200 },
    { idleAction: ["systemctl", "suspend-then-hibernate"], timeout: 1800 }
];

function blockBody(src, name, indent) {
    const re = new RegExp(`^${indent}readonly property bool ${name}: \\{\\n([\\s\\S]*?)^${indent}\\}`, "m");
    const m = src.match(re);
    assert.ok(m, `${name} block not found`);
    return m[1];
}

// Execute the production QML methods and bindings; strip only QML annotations.
function policy() {
    const root = {};
    const state = { inhibitIdle: false, inhibitSleepOnly: false, inhibitingIdleSince: -1 };
    const idle = { inhibitWhenFullscreen: true, inhibitWhenAudio: true, inhibitWhenCharging: false, timeouts: { values: userTimeouts } };
    const hypr = { monitors: { values: [] }, workspaces: { values: [] } };
    const context = vm.createContext({ root, RuntimeState: state, Hypr: hypr, GlobalConfig: { general: { idle } } });
    for (const [, name, params, body] of source.matchAll(/^    function (\w+)\(([^)]*)\): \w+ \{\n([\s\S]*?)^    \}/gm)) {
        vm.runInContext(`function ${name}(${params.replace(/:\s*\w+/g, "")}) {\n${body}\n}`, context);
        root[name] = context[name];
    }
    for (const [, name, expression] of source.matchAll(/^    readonly property bool (\w+): (.+)$/gm)) {
        Object.defineProperty(root, name, { get: () => vm.runInContext(expression, context) });
        Object.defineProperty(context, name, { get: () => root[name] });
    }

    const monitors = { hasPlayer: false, isCharging: false };
    const monitorContext = vm.createContext({
        KeepAwake: root,
        GlobalConfig: { general: { idle } },
        root: monitors
    });
    Object.defineProperty(monitorContext, "hasPlayer", { get: () => monitors.hasPlayer });
    Object.defineProperty(monitorContext, "isCharging", { get: () => monitors.isCharging });
    vm.runInContext(`function enabled() {\n${blockBody(monitorsSource, "enabled", "    ")}\n}`, monitorContext);
    Object.defineProperty(monitors, "enabled", { get: () => monitorContext.enabled() });
    vm.runInContext(`function watching(modelData) {\n${blockBody(monitorsSource, "watching", "            ")}\n}`, monitorContext);

    return {
        root,
        state,
        idle,
        hypr,
        monitors,
        timersEnabled: () => monitors.enabled,
        watching: entry => monitorContext.watching(entry),
        watchingActions: () => userTimeouts.filter(t => monitorContext.watching(t)).map(t => t.idleAction)
    };
}

function window(overrides = {}) {
    return { lastIpcObject: { fullscreen: 2, fullscreenClient: 2, mapped: true, hidden: false, ...overrides } };
}

function workspace(name, ...windows) {
    return { name, toplevels: { values: windows } };
}

function monitor(activeWorkspace, special = "", disabled = false) {
    return { activeWorkspace, lastIpcObject: { specialWorkspace: { name: special }, disabled } };
}

test("fullscreen gaming inhibits all idle actions without any keyboard/controller events", () => {
    const p = policy();
    const game = window();
    p.hypr.monitors.values = [monitor(workspace("1", game))];
    assert.equal(p.root.fullscreenActive, true);
    assert.equal(p.root.inhibiting, true);
    assert.equal(p.root.active, true);
    assert.equal(p.timersEnabled(), false);
    assert.deepEqual(p.watchingActions(), []);
    assert.equal(p.state.inhibitIdle, false, "automatic protection must not turn on the manual switch");

    game.lastIpcObject.fullscreen = game.lastIpcObject.fullscreenClient = 0;
    assert.equal(p.root.inhibiting, false);
    assert.equal(p.timersEnabled(), true, "leaving fullscreen restores normal idle behavior");
    assert.equal(p.watchingActions().length, 3);
});

test("fullscreen on an unfocused second monitor protects the whole session", () => {
    const p = policy();
    p.hypr.monitors.values = [monitor(workspace("1")), monitor(workspace("2", window()))];
    assert.equal(p.root.fullscreenActive, true);
    p.hypr.monitors.values.pop();
    assert.equal(p.root.fullscreenActive, false, "unplugging the game monitor releases protection");
});

test("switching away from a fullscreen game's workspace releases automatic protection", () => {
    const p = policy();
    const gameWorkspace = workspace("game", window());
    p.hypr.workspaces.values = [gameWorkspace, workspace("desktop")];
    p.hypr.monitors.values = [monitor(gameWorkspace)];
    assert.equal(p.root.inhibiting, true);
    p.hypr.monitors.values[0].activeWorkspace = p.hypr.workspaces.values[1];
    assert.equal(p.root.inhibiting, false);
    p.hypr.monitors.values[0].activeWorkspace = gameWorkspace;
    assert.equal(p.root.inhibiting, true);
});

test("special workspace games inhibit only while that workspace is open", () => {
    const p = policy();
    p.hypr.workspaces.values = [workspace("special:game", window())];
    p.hypr.monitors.values = [monitor(workspace("1"))];
    assert.equal(p.root.fullscreenActive, false);
    p.hypr.monitors.values[0].lastIpcObject.specialWorkspace.name = "special:game";
    assert.equal(p.root.fullscreenActive, true);
    p.hypr.monitors.values[0].lastIpcObject.specialWorkspace.name = "";
    assert.equal(p.root.fullscreenActive, false);
});

test("opening a scratchpad over a fullscreen game does not interrupt protection", () => {
    const p = policy();
    p.hypr.workspaces.values = [workspace("special:chat", window({ fullscreen: 0, fullscreenClient: 0 }))];
    p.hypr.monitors.values = [monitor(workspace("game", window()), "special:chat")];
    assert.equal(p.root.fullscreenActive, true);
});

for (const [name, client, expected] of [
    ["client-only fullscreen", { fullscreen: 0, fullscreenClient: 2 }, true],
    ["compositor-only fullscreen", { fullscreen: 2, fullscreenClient: 0 }, true],
    ["combined fullscreen flags", { fullscreen: 3, fullscreenClient: 0 }, true],
    ["maximized", { fullscreen: 1, fullscreenClient: 1 }, false],
    ["windowed", { fullscreen: 0, fullscreenClient: 0 }, false],
    ["hidden", { hidden: true }, false],
    ["unmapped", { mapped: false }, false]
]) {
    test(`${name} window: fullscreen protection is ${expected}`, () => {
        const p = policy();
        p.hypr.monitors.values = [monitor(workspace("1", window(client)))];
        assert.equal(p.root.fullscreenActive, expected);
    });
}

test("empty, disabled, and not-yet-populated monitor/workspace state is safe", () => {
    const p = policy();
    assert.equal(p.root.fullscreenActive, false);
    p.hypr.monitors.values = [monitor(null, "special:missing"), monitor(workspace("game", window()), "", true)];
    assert.equal(p.root.fullscreenActive, false);
});

test("the automatic preference can be disabled independently of manual Keep Awake", () => {
    const p = policy();
    p.hypr.monitors.values = [monitor(workspace("1", window()))];
    p.idle.inhibitWhenFullscreen = false;
    assert.equal(p.root.fullscreenActive, false);
    assert.equal(p.timersEnabled(), true);
    p.state.inhibitIdle = true;
    assert.equal(p.root.inhibiting, true);
    assert.equal(p.timersEnabled(), false);
});

test("manual Keep Awake survives a fullscreen session ending", () => {
    const p = policy();
    p.state.inhibitIdle = true;
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    p.hypr.monitors.values = [];
    assert.equal(p.root.fullscreenActive, false);
    assert.equal(p.root.inhibiting, true);
    assert.equal(p.timersEnabled(), false);
});

test("sleep-only mode keeps lock and dpms timers but blocks suspend-then-hibernate", () => {
    const p = policy();
    p.state.inhibitSleepOnly = true;
    assert.equal(p.root.active, true);
    assert.equal(p.root.inhibiting, false, "sleep-only must not create a compositor inhibitor");
    assert.equal(p.timersEnabled(), true, "sleep-only must allow the normal lock/screen-off timers");
    assert.deepEqual(p.watchingActions(), ["lock", "dpms off"]);
});

for (const [action, expected] of [
    [["systemctl", "suspend-then-hibernate"], true],
    [["suspendThenHibernate"], true],
    [["systemctl", "suspend"], true],
    [["hibernate"], true],
    [["loginctl", "lock-session"], false],
    ["lock", false],
    ["dpms off", false],
    [undefined, false]
]) {
    test(`isSleepAction(${JSON.stringify(action)}) is ${expected}`, () => {
        assert.equal(policy().root.isSleepAction(action), expected);
    });
}

test("fullscreen protection temporarily takes precedence over sleep-only mode", () => {
    const p = policy();
    p.state.inhibitSleepOnly = true;
    assert.equal(p.timersEnabled(), true);
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    assert.equal(p.timersEnabled(), false);
    p.hypr.monitors.values = [];
    assert.equal(p.state.inhibitSleepOnly, true);
    assert.equal(p.timersEnabled(), true);
    assert.deepEqual(p.watchingActions(), ["lock", "dpms off"]);
});

test("audio and charging inhibition remain independent of fullscreen protection", () => {
    const p = policy();
    p.monitors.hasPlayer = true;
    assert.equal(p.timersEnabled(), false);
    p.idle.inhibitWhenAudio = false;
    assert.equal(p.timersEnabled(), true);
    p.monitors.isCharging = true;
    assert.equal(p.timersEnabled(), true, "inhibitWhenCharging defaults off");
    p.idle.inhibitWhenCharging = true;
    assert.equal(p.timersEnabled(), false);
    p.idle.inhibitWhenCharging = false;
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    assert.equal(p.timersEnabled(), false);
});

test("per-timeout audio/charging flags and disabled entries are honoured", () => {
    const p = policy();
    assert.equal(p.watching({ idleAction: "lock", enabled: false }), false);
    p.monitors.hasPlayer = true;
    p.idle.inhibitWhenAudio = false;
    assert.equal(p.watching({ idleAction: "lock", inhibitWhenAudio: true }), false);
    assert.equal(p.watching({ idleAction: "lock" }), true);
    p.monitors.isCharging = true;
    assert.equal(p.watching({ idleAction: "lock", inhibitWhenCharging: true }), false);
});
