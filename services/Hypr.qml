pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.I18n
import Caelestia.Services
import qs.components.misc

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property string lastSpecialWorkspace: ""

    signal configReloaded
    // monitoradded / monitorremoved — consumers (Brightness) re-detect on this.
    signal monitorsHotplugged

    // Mode-aware chokepoint: under the Lua config manager the request socket evaluates
    // dispatch args as Lua ("dispatch X" -> "return hl.dispatch(X)"), so classic
    // dispatcher strings fail silently. Already-typed Lua ("hl.…") passes through;
    // classic strings are translated by luaDispatch when usingLua.
    function dispatch(request: string): void {
        Hyprland.dispatch(usingLua ? luaDispatch(request) : request);
    }

    // Full socket request line for the given classic dispatch (for batchMessage callers).
    function dispatchRequest(request: string): string {
        return "dispatch " + (usingLua ? luaDispatch(request) : request);
    }

    // Classic dispatcher string -> hl.dsp.* Lua expression. Unknown verbs pass through
    // with a warning (call sites should then use the usingLua ternary idiom instead).
    function luaDispatch(request: string): string {
        if (request.startsWith("hl."))
            return request;

        const sp = request.indexOf(" ");
        const verb = sp < 0 ? request : request.slice(0, sp);
        const rest = sp < 0 ? "" : request.slice(sp + 1).trim();
        const q = s => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
        const win = (fn, sel) => sel ? `hl.dsp.window.${fn}({ window = ${q(sel)} })` : `hl.dsp.window.${fn}({})`;

        switch (verb) {
        case "submap":
            return `hl.dsp.submap(${q(rest)})`;
        case "global":
            return `hl.dsp.global(${q(rest)})`;
        case "focuswindow":
            return `hl.dsp.focus({ window = ${q(rest)} })`;
        case "workspace":
            return `hl.dsp.focus({ workspace = ${q(rest)} })`;
        case "togglespecialworkspace":
            return rest ? `hl.dsp.workspace.toggle_special(${q(rest)})` : "hl.dsp.workspace.toggle_special()";
        case "movecursor": {
            const parts = rest.split(/\s+/);
            return `hl.dsp.cursor.move({ x = ${Number(parts[0]) || 0}, y = ${Number(parts[1]) || 0} })`;
        }
        case "movetoworkspace":
        case "movetoworkspacesilent": {
            const ci = rest.indexOf(",");
            const ws = ci < 0 ? rest : rest.slice(0, ci);
            const sel = ci < 0 ? "" : rest.slice(ci + 1);
            const follow = verb === "movetoworkspace";
            return `hl.dsp.window.move({ workspace = ${q(ws)}, ${sel ? `window = ${q(sel)}, ` : ""}follow = ${follow} })`;
        }
        case "togglefloating":
            return win("float", rest);
        case "pin":
            return win("pin", rest);
        case "killwindow":
            // window.kill is the forceful legacy killwindow; window.close is graceful.
            return win("kill", rest);
        case "closewindow":
            return win("close", rest);
        case "layoutmsg":
            return `hl.dsp.layout(${q(rest)})`;
        case "dpms": {
            const parts = rest.split(/\s+/);
            const action = parts[0] === "off" ? "disable" : parts[0] === "on" ? "enable" : parts[0];
            return parts[1] ? `hl.dsp.dpms({ action = ${q(action)}, monitor = ${q(parts[1])} })` : `hl.dsp.dpms({ action = ${q(action)} })`;
        }
        case "moveworkspacetomonitor": {
            const parts = rest.split(/\s+/);
            return `hl.dsp.workspace.move({ workspace = ${q(parts[0])}, monitor = ${q(parts[1] ?? "")} })`;
        }
        case "exec":
            return `hl.dsp.exec_cmd(${q(rest)})`;
        case "execr":
            return `hl.dsp.exec_raw(${q(rest)})`;
        default:
            console.warn(`[Hypr] no Lua translation for dispatcher "${verb}" - sending classic form`);
            return request;
        }
    }

    function focusWorkspace(ws: var): void {
        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
    }

    function toggleSpecial(name: string): void {
        dispatch(usingLua ? `hl.dsp.workspace.toggle_special("${name}")` : `togglespecialworkspace ${name}`);
    }

    // address: bare hex, no 0x prefix (HyprlandToplevel.address)
    function focusWindow(address: string): void {
        const addr = address.startsWith("0x") ? address : "0x" + address;
        dispatch(usingLua ? `hl.dsp.focus({ window = "address:${addr}" })` : `focuswindow address:${addr}`);
    }

    function submap(name: string): void {
        dispatch(usingLua ? `hl.dsp.submap("${name}")` : `submap ${name}`);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor?.lastIpcObject.specialWorkspace?.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.lastIpcObject.windows > 0) {
                    focusWorkspace(lastSpecialWorkspace);
                    return;
                }
            }
            focusWorkspace(openSpecials[0].name);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        focusWorkspace(openSpecials[nextIndex].name);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        // Resolve by name over the live list instead of Hyprland.monitorFor: hotplug
        // destroys and recreates HyprlandMonitor objects, and reading monitors.values
        // here makes caller BINDINGS re-evaluate when the list changes, so they pick up
        // the new object instead of keeping a stale/null one forever.
        return monitors.values.find(m => m.name === screen?.name) ?? null;
    }

    // Live config values. `values` maps classic keys ("general:col.active_border") to
    // string values. Legacy: one keyword per entry. Lua: one eval hl.config (keys
    // ":"->"." and "-"->"_"; hl.config merges, so only the listed keys change).
    // NOTE: usingLua is false until quickshell's status probe resolves, so startup
    // pushes should be re-issued from an onUsingLuaChanged handler (see reloadDynamicConfs).
    function setConfigValues(values: var): void {
        const reqs = [];
        if (usingLua) {
            const entries = [];
            for (const k in values)
                entries.push(`["${k.replace(/:/g, ".").replace(/-/g, "_")}"] = "${values[k]}"`);
            reqs.push(`eval hl.config({ ${entries.join(", ")} })`);
        } else {
            for (const k in values)
                reqs.push(`keyword ${k} ${values[k]}`);
        }
        extras.batchMessage(reqs);
    }

    // Layer rules for a layershell namespace. `effects` maps effect names (blur,
    // ignore_alpha, ...) to bool/number values. Lua: one NAMED rule per effect so
    // re-issues replace the rule instead of leaking a new engine rule each time.
    function setLayerRules(namespace: string, effects: var): void {
        const reqs = [];
        for (const k in effects) {
            const v = effects[k];
            if (usingLua) {
                const lv = typeof v === "boolean" ? (v ? "true" : "false") : String(v);
                reqs.push(`eval hl.layer_rule({ name = "caelestia-${namespace}-${k}", match = { namespace = "${namespace}" }, ${k} = ${lv} })`);
            } else {
                const cv = typeof v === "boolean" ? (v ? 1 : 0) : v;
                reqs.push(`keyword layerrule ${k} ${cv}, match:namespace ${namespace}`);
            }
        }
        extras.batchMessage(reqs);
    }

    // Partial runtime update of a monitor rule. `selector` is the exact form of
    // the user's config rule (e.g. "desc:<description>") so the update merges
    // into the winning rule (hl.monitor merges; a differently-keyed selector
    // would resurrect a stale rule). `name` is the connector for the keyword path.
    function setMonitorRule(name: string, selector: string, fields: var): void {
        if (usingLua) {
            const entries = [`output = "${selector.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`];
            for (const k in fields) {
                const v = fields[k];
                entries.push(typeof v === "number" ? `${k} = ${v}` : `${k} = "${v}"`);
            }
            extras.batchMessage([`eval hl.monitor({ ${entries.join(", ")} })`]);
        } else {
            const reqs = [];
            for (const k in fields)
                reqs.push(`keyword monitorv2[${name}]:${k} ${fields[k]}`);
            extras.batchMessage(reqs);
        }
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: int, ignoredTags = []): list<HyprlandToplevel> {
        return toplevels.values.filter(t => t.workspace && t.workspace.id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: HyprlandToplevel, ignoredTags = []): bool {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc?.class || !ipc.mapped)
            return true;

        return ipc.tags?.some(tag => ignoredTags.includes(tag.replace(/\*$/, ""))) ?? false;
    }

    function reloadDynamicConfs(): void {
        if (usingLua) {
            extras.batchMessage(['eval hl.bind("Caps_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("Num_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("code:66", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })']);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,caelestia:refreshDevices", "keyword bindlni ,Num_Lock,global,caelestia:refreshDevices", "keyword bindlni ,code:66,global,caelestia:refreshDevices"]);
        }
    }

    onUsingLuaChanged: reloadDynamicConfs()
    Component.onCompleted: reloadDynamicConfs()

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                // Monitor rules (cm/HDR presets, sdr luminance) may have changed
                // and there is no separate event for that — refresh so consumers
                // (e.g. Brightness method resolution) see the new state.
                Hyprland.refreshMonitors();
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (n === "monitoradded" || n === "monitorremoved") {
                root.monitorsHotplugged();
                Hyprland.refreshMonitors();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
            }
        }

        target: Hyprland
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor?.lastIpcObject.specialWorkspace?.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0).map(w => w.name).join("\n");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: Hyprland.usingLua
    }
}
