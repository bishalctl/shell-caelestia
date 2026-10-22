// Run without locking the live session: node --test scripts/test-idle-policy.cjs
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const vm = require("node:vm");

const source = readFileSync(join(__dirname, "../services/IdleInhibitor.qml"), "utf8");
const monitorsSource = readFileSync(join(__dirname, "../modules/IdleMonitors.qml"), "utf8");

// Execute the production QML methods and bindings; strip only QML annotations.
function policy() {
    const root = {};
    const props = { enabled: false, sleepOnly: false };
    const idle = { inhibitWhenFullscreen: true, inhibitWhenAudio: true };
    const hypr = { monitors: { values: [] }, workspaces: { values: [] } };
    const context = vm.createContext({ root, props, Hypr: hypr, GlobalConfig: { general: { idle } } });
    for (const [, name, params, body] of source.matchAll(/^    function (\w+)\(([^)]*)\): \w+ \{\n([\s\S]*?)^    \}/gm)) {
        vm.runInContext(`function ${name}(${params.replace(/:\s*\w+/g, "")}) {\n${body}\n}`, context);
        root[name] = context[name];
    }
    for (const [, name, expression] of source.matchAll(/^    readonly property bool (\w+): (.+)$/gm)) {
        Object.defineProperty(root, name, { get: () => vm.runInContext(expression, context) });
        Object.defineProperty(context, name, { get: () => root[name] });
    }
    const monitorContext = vm.createContext({
        Services: { IdleInhibitor: root },
        GlobalConfig: { general: { idle } },
        Players: { list: [] }
    });
    const enabledExpression = monitorsSource.match(/^    readonly property bool enabled: (.+)$/m)[1];
    return { root, props, idle, hypr, monitorContext, timersEnabled: () => vm.runInContext(enabledExpression, monitorContext) };
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
    assert.equal(p.props.enabled, false, "automatic protection must not turn on the manual switch");

    game.lastIpcObject.fullscreen = game.lastIpcObject.fullscreenClient = 0;
    assert.equal(p.root.inhibiting, false);
    assert.equal(p.timersEnabled(), true, "leaving fullscreen restores normal idle behavior");
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
    p.props.enabled = true;
    assert.equal(p.root.inhibiting, true);
    assert.equal(p.timersEnabled(), false);
});

test("manual Keep Awake survives a fullscreen session ending", () => {
    const p = policy();
    p.props.enabled = true;
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    p.hypr.monitors.values = [];
    assert.equal(p.root.fullscreenActive, false);
    assert.equal(p.root.inhibiting, true);
    assert.equal(p.timersEnabled(), false);
});

test("fullscreen protection temporarily takes precedence over sleep-only mode", () => {
    const p = policy();
    p.props.sleepOnly = true;
    assert.equal(p.root.active, true);
    assert.equal(p.timersEnabled(), true, "sleep-only must allow the normal lock/screen-off timers");
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    assert.equal(p.timersEnabled(), false);
    p.hypr.monitors.values = [];
    assert.equal(p.props.sleepOnly, true);
    assert.equal(p.timersEnabled(), true);
});

test("audio inhibition remains independent of fullscreen protection", () => {
    const p = policy();
    p.monitorContext.Players.list = [{ isPlaying: true }];
    assert.equal(p.timersEnabled(), false);
    p.idle.inhibitWhenAudio = false;
    assert.equal(p.timersEnabled(), true);
    p.hypr.monitors.values = [monitor(workspace("game", window()))];
    assert.equal(p.timersEnabled(), false);
});
