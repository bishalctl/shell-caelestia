pragma Singleton

import "audio/Policy.js" as AudioPolicy
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.utils

// Keep explicit device choices stable across WirePlumber's transient default changes.
Singleton {
    id: root

    property bool loaded: false
    property var blockedSinks: []
    property var blockedSources: []
    property var sourceStack: []
    property string mainOutput: ""
    property string mainInput: ""

    function isSinkBlocked(name: string): bool {
        return root.blockedSinks.includes(name);
    }

    function isSourceBlocked(name: string): bool {
        return root.blockedSources.includes(name);
    }

    function toggleSinkBlocked(name: string): void {
        root.blockedSinks = root.isSinkBlocked(name) ? root.blockedSinks.filter(n => n !== name) : AudioPolicy.recent(root.blockedSinks, name);
        root.save();
    }

    function toggleSourceBlocked(name: string): void {
        root.blockedSources = root.isSourceBlocked(name) ? root.blockedSources.filter(n => n !== name) : AudioPolicy.recent(root.blockedSources, name);
        root.save();
    }

    function selectSink(node: PwNode): void {
        if (!node?.name)
            return;
        root.mainOutput = node.name;
        Pipewire.preferredDefaultAudioSink = node;
        root.save();
    }

    function selectSource(node: PwNode): void {
        if (!node?.name)
            return;
        root.mainInput = node.name;
        root.sourceStack = AudioPolicy.recent(root.sourceStack, node.name);
        Pipewire.preferredDefaultAudioSource = node;
        root.save();
    }

    function reconcile(): void {
        if (!root.loaded)
            return;

        const sinks = Audio.sinks.filter(n => n?.name && n.name !== "notification_sink");
        const sinkNames = sinks.map(n => n.name);
        // Retain the requested name until after the device list settles, even if
        // WirePlumber has already changed defaultAudioSink to another physical device.
        const current = root.mainOutput || (root.isSinkBlocked(Audio.sink?.name) ? "" : Audio.sink?.name) || "";
        const output = AudioPolicy.mainOutput(current, sinkNames, root.blockedSinks, "music_sink");
        if (output) {
            const node = sinks.find(n => n.name === output);
            if (root.mainOutput !== output || Audio.sink !== node)
                root.selectSink(node);
        }

        const sources = Audio.sources.filter(n => n?.name);
        const sourceNames = sources.map(n => n.name);
        const input = root.mainInput || (root.isSourceBlocked(Audio.source?.name) ? "" : Audio.source?.name) || "";
        const target = sourceNames.includes(input) ? input : AudioPolicy.fallback(sourceNames, root.sourceStack, root.blockedSources);
        if (target) {
            const node = sources.find(n => n.name === target);
            if (root.mainInput !== target || Audio.source !== node)
                root.selectSource(node);
        }
    }

    function save(): void {
        if (!root.loaded)
            return;
        stateFile.setText(JSON.stringify({
            blockedSinks: root.blockedSinks,
            blockedSources: root.blockedSources,
            sourceStack: root.sourceStack,
            mainOutput: root.mainOutput,
            mainInput: root.mainInput
        }));
    }

    Connections {
        function onSinksChanged(): void {
            settle.restart();
        }

        function onSourcesChanged(): void {
            settle.restart();
        }

        function onSinkChanged(): void {
            settle.restart();
        }

        function onSourceChanged(): void {
            settle.restart();
        }

        target: Audio
    }

    Timer {
        id: settle

        interval: 350
        onTriggered: root.reconcile()
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/audio-devices.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.blockedSinks = AudioPolicy.names(data.blockedSinks);
                root.blockedSources = AudioPolicy.names(data.blockedSources);
                root.sourceStack = AudioPolicy.names(data.sourceStack);
                root.mainOutput = typeof data.mainOutput === "string" ? data.mainOutput : "";
                root.mainInput = typeof data.mainInput === "string" ? data.mainInput : "";
            } catch (e) {}
            root.loaded = true;
            settle.restart();
        }
        onLoadFailed: {
            root.loaded = true;
            settle.restart();
        }
    }
}
