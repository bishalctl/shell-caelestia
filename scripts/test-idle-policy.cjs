// Run without locking the live session: node --test scripts/test-idle-policy.cjs
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const vm = require("node:vm");

const source = readFileSync(join(__dirname, "../services/KeepAwake.qml"), "utf8");
const monitorsSource = readFileSync(join(__dirname, "../daemons/IdleMonitors.qml"), "utf8");
const timeouts = [
    { idleAction: "lock", timeout: 900 },
    { idleAction: "dpms off", returnAction: "dpms on", timeout: 1200 },
    { idleAction: ["systemctl", "suspend-then-hibernate"], timeout: 1800 }
];

function blockBody(src, name, indent) {
    const re = new RegExp(`^${indent}readonly property bool ${name}: \\{\\n([\\s\\S]*?)^${indent}\\}`, "m");
    const match = src.match(re);
    assert.ok(match, `${name} block not found`);
    return match[1];
}

// Execute the actual production QML functions and bindings, stripping type annotations.
function policy() {
    const root = {};
    const state = { inhibitIdle: false, inhibitingIdleSince: -1 };
    const persistent = { keepAwakeAllowLock: true, keepAwakeAllowScreenBlank: false };
    const idle = { inhibitWhenAudio: false, inhibitWhenCharging: false };
    const context = vm.createContext({ root, RuntimeState: state, PersistentState: persistent });
    for (const [, name, params, body] of source.matchAll(/^    function (\w+)\(([^)]*)\): \w+ \{\n([\s\S]*?)^    \}/gm)) {
        vm.runInContext(`function ${name}(${params.replace(/:\s*\w+/g, "")}) {\n${body}\n}`, context);
        root[name] = context[name];
    }
    for (const [, name, expression] of source.matchAll(/^    readonly property bool (\w+): (.+)$/gm)) {
        Object.defineProperty(root, name, { get: () => vm.runInContext(expression, context) });
        Object.defineProperty(context, name, { get: () => root[name] });
    }
    const monitors = { hasPlayer: false, isCharging: false };
    const monitorContext = vm.createContext({ KeepAwake: root, GlobalConfig: { general: { idle } }, root: monitors });
    for (const name of ["hasPlayer", "isCharging"])
        Object.defineProperty(monitorContext, name, { get: () => monitors[name] });
    vm.runInContext(`function enabled() {\n${blockBody(monitorsSource, "enabled", "    ")}\n}`, monitorContext);
    Object.defineProperty(monitors, "enabled", { get: () => monitorContext.enabled() });
    vm.runInContext(`function watching(modelData) {\n${blockBody(monitorsSource, "watching", "            ")}\n}`, monitorContext);
    return { root, state, persistent, idle, monitors, watching: entry => monitorContext.watching(entry) };
}

for (const allowLock of [false, true]) {
    for (const allowBlank of [false, true]) {
        test(`Keep Awake on: lock=${allowLock}, screen blank=${allowBlank}`, () => {
            const p = policy();
            p.state.inhibitIdle = true;
            p.persistent.keepAwakeAllowLock = allowLock;
            p.persistent.keepAwakeAllowScreenBlank = allowBlank;
            assert.equal(p.watching(timeouts[0]), allowLock);
            assert.equal(p.watching(timeouts[1]), allowBlank);
            assert.equal(p.watching(timeouts[2]), false);
            assert.equal(p.root.inhibiting, !allowLock && !allowBlank);
        });
        test(`Turning Keep Awake off restores every timer and preserves ${allowLock}/${allowBlank}`, () => {
            const p = policy();
            p.persistent.keepAwakeAllowLock = allowLock;
            p.persistent.keepAwakeAllowScreenBlank = allowBlank;
            for (let i = 0; i < 3; i++) {
                p.state.inhibitIdle = true;
                p.state.inhibitIdle = false;
                assert.equal(p.root.inhibiting, false);
                for (const entry of timeouts)
                    assert.equal(p.watching(entry), true);
                assert.equal(p.root.allowLock, allowLock);
                assert.equal(p.root.allowScreenBlank, allowBlank);
            }
        });
    }
}

test("defaults allow lock and keep the display on", () => {
    const p = policy();
    p.state.inhibitIdle = true;
    assert.equal(p.watching(timeouts[0]), true);
    assert.equal(p.watching(timeouts[1]), false);
    assert.equal(p.watching(timeouts[2]), false);
});

for (const action of [["systemctl", "suspend"], ["hibernate"], ["suspendThenHibernate"], ["systemctl", "hybrid-sleep"]]) {
    test(`sleep action ${JSON.stringify(action)} is blocked in every enabled combination`, () => {
        const p = policy();
        p.state.inhibitIdle = true;
        for (const lock of [false, true]) for (const blank of [false, true]) {
            p.persistent.keepAwakeAllowLock = lock;
            p.persistent.keepAwakeAllowScreenBlank = blank;
            assert.equal(p.root.isSleepAction(action), true);
            assert.equal(p.watching({ idleAction: action }), false);
        }
    });
}

test("loginctl lock aliases and Hyprland DPMS commands respect the independent options", () => {
    const p = policy();
    p.state.inhibitIdle = true;
    for (const action of ["lock", ["lock"], ["loginctl", "lock-session"], ["loginctl", "lock-sessions"]]) {
        assert.equal(p.watching({ idleAction: action }), true);
        p.persistent.keepAwakeAllowLock = false;
        assert.equal(p.watching({ idleAction: action }), false);
        p.persistent.keepAwakeAllowLock = true;
    }
    for (const action of ["dpms off", ["hyprctl", "dispatch", "dpms off"]]) {
        assert.equal(p.watching({ idleAction: action }), false);
        p.persistent.keepAwakeAllowScreenBlank = true;
        assert.equal(p.watching({ idleAction: action }), true);
        p.persistent.keepAwakeAllowScreenBlank = false;
    }
});

test("audio, charging and disabled timeout settings remain independent", () => {
    const p = policy();
    p.monitors.hasPlayer = true;
    p.idle.inhibitWhenAudio = true;
    assert.equal(p.watching(timeouts[0]), false);
    p.idle.inhibitWhenAudio = false;
    assert.equal(p.watching(timeouts[0]), true);
    assert.equal(p.watching({ idleAction: "lock", inhibitWhenAudio: true }), false);
    p.monitors.isCharging = true;
    p.idle.inhibitWhenCharging = true;
    assert.equal(p.watching(timeouts[0]), false);
    p.idle.inhibitWhenCharging = false;
    assert.equal(p.watching(timeouts[0]), true);
    assert.equal(p.watching({ idleAction: "lock", inhibitWhenCharging: true }), false);
    assert.equal(p.watching({ idleAction: "lock", enabled: false }), false);
});
