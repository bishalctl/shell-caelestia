pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge

    // Ctrl+P: pin/unpin the highlighted entry. Apps toggle in favouriteApps (saved to
    // shell.json, same as Nexus' app page); browser entries toggle in Browsers' own
    // favourites file. No-op in wallpaper/clipboard/other action modes.
    function togglePin(): void {
        const id = list.currentList?.currentItem?.modelData?.id;
        if (!id || list.showWallpapers || list.showClipboard)
            return;

        if (list.showBrowser) {
            Browsers.toggleFav(id);
            return;
        }
        if (search.text.startsWith(GlobalConfig.launcher.actionPrefix))
            return;

        const favs = GlobalConfig.launcher.favouriteApps;
        GlobalConfig.launcher.favouriteApps = favs.includes(id) ? favs.filter(a => a !== id) : [...favs, id];
    }

    // Keyboard list nav. Flags keyboard priority on lists that support it, so a
    // stationary hovering mouse can't steal the selection while the list scrolls.
    function navigate(delta: int): void {
        const l = list.currentList;
        if (!l)
            return;
        if (l.noteKeyboardNav)
            l.noteKeyboardNav();
        if (delta > 0)
            l.incrementCurrentIndex();
        else
            l.decrementCurrentIndex();
    }

    // Pre-fill the search from screenState.launcherQuery (set by e.g. the browserLauncher shortcut)
    function consumeQuery(): void {
        if (screenState.launcherQuery) {
            search.text = screenState.launcherQuery;
            screenState.launcherQuery = "";
        }
    }

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: Tr.tr("Type \"%1\" for commands, \"%2\" for clipboard").arg(GlobalConfig.launcher.actionPrefix).arg(Clipboard.prefix)

        onAccepted: {
            // Clipboard command: ":>clear" wipes the whole history. Plain ":clear"
            // stays a normal search — otherwise the word "clear" is unsearchable.
            if (list.showClipboard && clipboardHint.clearReady) {
                Clipboard.clearAll();
                text = Clipboard.prefix;
                return;
            }

            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (list.showClipboard) {
                    Clipboard.copy(currentItem.modelData);
                    root.screenState.launcher = false;
                } else if (list.showBrowser) {
                    Browsers.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: root.navigate(-1)
        Keys.onDownPressed: root.navigate(1)

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            if (!GlobalConfig.launcher.vimKeybinds) {
                // Ctrl+P pins; with vim keybinds it is "up" instead
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
                    root.togglePin();
                    event.accepted = true;
                }
                return;
            }

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    root.navigate(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    root.navigate(-1);
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                root.navigate(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                root.navigate(-1);
                event.accepted = true;
            }
        }

        Component.onCompleted: {
            root.consumeQuery();
            forceActiveFocus();
        }

        // Clipboard command hint: visible when the field holds just ":" (or a ">…"
        // command being typed), so the ">clear" command is discoverable.
        StyledText {
            id: clipboardHint

            readonly property string cmd: search.text.slice(Clipboard.prefix.length).trim()
            readonly property bool clearReady: cmd.startsWith(">") && cmd.slice(1).trim().toLowerCase() === "clear"

            anchors.right: search.clearIcon.left
            anchors.rightMargin: Tokens.spacing.small
            anchors.verticalCenter: parent.verticalCenter

            visible: opacity > 0
            opacity: list.showClipboard && (cmd === "" || cmd.startsWith(">")) ? 1 : 0

            text: clearReady ? Tr.tr("Enter — wipe clipboard history") : Tr.tr(">clear — wipe clipboard history")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    search.text = "";
                else
                    root.consumeQuery();
            }

            function onLauncherQueryChanged(): void {
                if (root.screenState.launcher)
                    root.consumeQuery();
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
