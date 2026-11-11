pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// AirDrop tab: visibility switch and window, who can see us, nearby Apple devices to send to,
// what arrived. All state lives in the AirDrop service; this is only the view.
Item {
    id: root

    readonly property string statusText: {
        if (!AirDrop.checked)
            return Tr.tr("Checking the radio…");
        if (!AirDrop.ready && !AirDrop.active)
            return Tr.tr("Not ready");
        switch (AirDrop.radioState) {
        case "starting":
            return Tr.tr("Bringing the radio up…");
        case "stopping":
            return Tr.tr("Giving the radio back…");
        case "up":
            return AirDrop.receiving ? (AirDrop.remaining >= 0 ? Tr.tr("Visible to everyone · %1 left").arg(AirDrop.formatRemaining(AirDrop.remaining)) : Tr.tr("Visible to everyone until turned off")) : Tr.tr("Radio up, starting the receiver…");
        default:
            return Tr.tr("Off");
        }
    }

    readonly property color statusColour: AirDrop.radioState === "up" ? Colours.palette.m3primary : AirDrop.radioState === "idle" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3tertiary

    implicitWidth: 840
    implicitHeight: layout.implicitHeight

    function applyName(): void {
        const next = nameField.text.trim();
        if (!next)
            return;
        AirDrop.name = next;
        nameField.text = Qt.binding(() => AirDrop.name);
    }

    function formatSize(bytes: real): string {
        if (bytes >= 1024 * 1024 * 1024)
            return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GiB`;
        if (bytes >= 1024 * 1024)
            return `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
        if (bytes >= 1024)
            return `${Math.round(bytes / 1024)} KiB`;
        return `${bytes} B`;
    }

    Component.onCompleted: {
        if (!AirDrop.checked && !AirDrop.checking)
            AirDrop.check();
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // ---- header: name, status, switch -------------------------------------------------
        RowLayout {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true
            spacing: Tokens.spacing.large

            Item {
                // The 56px disc pulses out to 89.6px. Reserve its whole halo
                // inside the dashboard's clipped viewport, even while off.
                implicitWidth: 96
                implicitHeight: 96

                StyledRect {
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    radius: Tokens.rounding.full
                    color: AirDrop.radioState === "up" ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh

                    SvgIcon {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2
                        name: "airdrop"
                        fontStyle: Tokens.font.icon.extraLarge
                        color: AirDrop.radioState === "up" ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    }

                    // Pulse while visible
                    StyledRect {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Colours.palette.m3primary
                        opacity: 0
                        scale: 1
                        visible: AirDrop.radioState === "up"

                        SequentialAnimation on opacity {
                            running: AirDrop.radioState === "up"
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 0.7
                                to: 0
                                duration: 1600
                                easing.type: Easing.OutCubic
                            }
                        }
                        SequentialAnimation on scale {
                            running: AirDrop.radioState === "up"
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 1
                                to: 1.6
                                duration: 1600
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "AirDrop"
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: root.statusText
                    font: Tokens.font.body.small
                    color: root.statusColour
                    animate: true
                }
            }

            StyledSwitch {
                checked: AirDrop.active
                disabled: !AirDrop.checked || (!AirDrop.ready && !AirDrop.active) || AirDrop.radioState === "stopping"
                onToggled: AirDrop.toggle()
            }
        }

        // ---- not ready: what stands in the way ---------------------------------------------
        Card {
            visible: AirDrop.checked && !AirDrop.ready
            accent: Colours.palette.m3errorContainer

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "radio"
                    color: Colours.palette.m3error
                    fontStyle: Tokens.font.icon.large
                }

                Column {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall / 2

                    StyledText {
                        text: AirDrop.installed ? Tr.tr("The radio isn't ready") : Tr.tr("Owly isn't installed")
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        color: Colours.palette.m3onSurface
                    }

                    Repeater {
                        model: AirDrop.missing

                        StyledText {
                            required property var modelData

                            width: parent.width
                            text: modelData.say ?? modelData.id ?? ""
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                TextButton {
                    text: Tr.tr("Check again")
                    type: ButtonBase.Tonal
                    disabled: AirDrop.checking
                    onClicked: AirDrop.check()
                }
            }
        }

        // ---- incoming request -----------------------------------------------------------------
        Card {
            visible: AirDrop.pending !== null
            accent: Colours.palette.m3primaryContainer

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "move_to_inbox"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    Column {
                        Layout.fillWidth: true

                        StyledText {
                            text: (AirDrop.pending?.auto ? Tr.tr("Receiving from %1") : Tr.tr("%1 wants to send you")).arg(AirDrop.pending?.sender ?? "")
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: AirDrop.pending?.model ?? ""
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledText {
                        visible: !(AirDrop.pending?.auto ?? false)
                        text: Tr.tr("%1 s").arg(AirDrop.pendingRemaining)
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    CircularIndicator {
                        visible: AirDrop.pending?.auto ?? false
                        implicitWidth: 20
                        implicitHeight: 20
                    }
                }

                Repeater {
                    model: AirDrop.pending?.items ?? []

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.large

                        MaterialIcon {
                            text: "draft"
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideMiddle
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: modelData.size ? root.formatSize(modelData.size) : modelData.type
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                Repeater {
                    model: AirDrop.pending?.urls ?? []

                    RowLayout {
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.large

                        MaterialIcon {
                            text: "link"
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData
                            elide: Text.ElideMiddle
                            color: Colours.palette.m3onSurface
                        }
                    }
                }

                RowLayout {
                    visible: !(AirDrop.pending?.auto ?? false)
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: Tr.tr("Decline")
                        type: ButtonBase.Text
                        onClicked: AirDrop.decline()
                    }

                    TextButton {
                        text: Tr.tr("Accept")
                        onClicked: AirDrop.accept()
                    }
                }
            }
        }

        // ---- settings -----------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Card {
                title: Tr.tr("They see you as")
                icon: "badge"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: nameField

                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: AirDrop.name
                        placeholderText: Tr.tr("Name shown on Apple devices")
                        onAccepted: root.applyName()
                        Keys.onEscapePressed: text = Qt.binding(() => AirDrop.name)
                    }

                    IconButton {
                        icon: "check"
                        type: IconButton.Tonal
                        visible: nameField.text !== AirDrop.name
                        disabled: !nameField.text.trim()
                        Accessible.name: Tr.tr("Apply device name")
                        onClicked: root.applyName()
                    }
                }

                StyledText {
                    visible: AirDrop.active
                    Layout.fillWidth: true
                    text: Tr.tr("Confirm a new name with the checkmark or Enter")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            Card {
                title: Tr.tr("Save files to")
                icon: "folder"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Paths.shortenHome(AirDrop.dir)
                        placeholderText: "~/Downloads"
                        onEditingFinished: {
                            const t = text.trim();
                            if (t)
                                AirDrop.dir = Paths.absolutePath(t);
                        }
                    }

                    IconButton {
                        icon: "open_in_new"
                        type: IconButton.Tonal
                        Accessible.name: Tr.tr("Open receive folder")
                        onClicked: AirDrop.openDir()
                    }

                    IconButton {
                        icon: "folder_open"
                        type: IconButton.Tonal
                        Accessible.name: Tr.tr("Choose receive folder")
                        onClicked: AirDrop.pickDirectory(root.Window.window)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Card {
                title: Tr.tr("Stay visible for")
                icon: "timer"

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            {
                                minutes: 10,
                                label: Tr.tr("10 min")
                            },
                            {
                                minutes: 30,
                                label: Tr.tr("30 min")
                            },
                            {
                                minutes: 60,
                                label: Tr.tr("1 hour")
                            },
                            {
                                minutes: 0,
                                label: Tr.tr("Until off")
                            }
                        ]

                        TextButton {
                            required property var modelData

                            text: modelData.label
                            isToggle: true
                            checked: AirDrop.windowMinutes === modelData.minutes
                            type: ButtonBase.Tonal
                            onClicked: AirDrop.windowMinutes = modelData.minutes
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("The window starts when you turn receiving on")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            Card {
                title: Tr.tr("Incoming transfers")
                icon: "shield"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Accept automatically")
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: AirDrop.autoAccept ? Tr.tr("Anyone nearby can drop files without asking") : Tr.tr("Each transfer asks here first (15 s)")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledSwitch {
                        checked: AirDrop.autoAccept
                        onToggled: AirDrop.autoAccept = checked
                    }
                }
            }
        }

        // ---- send: compose box + device picker --------------------------------------------
        Card {
            id: sendCard

            title: Tr.tr("Send")
            icon: "ios_share"

            headerItem: TextButton {
                visible: AirDrop.picking
                text: Tr.tr("Cancel")
                type: ButtonBase.Text
                onClicked: AirDrop.stopPicking()
            }

            // Staged files, one chip each
            Flow {
                visible: AirDrop.draftFiles.length > 0
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: AirDrop.draftFiles

                    StyledRect {
                        id: chip

                        required property string modelData

                        implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3secondaryContainer

                        RowLayout {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: AirDrop.imageMime(chip.modelData) ? "image" : "draft"
                                color: Colours.palette.m3onSecondaryContainer
                            }

                            StyledText {
                                Layout.maximumWidth: 240
                                text: AirDrop.fileName(chip.modelData)
                                elide: Text.ElideMiddle
                                color: Colours.palette.m3onSecondaryContainer
                            }

                            IconButton {
                                icon: "close"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                padding: 0
                                onClicked: AirDrop.unstageFile(chip.modelData)
                            }
                        }
                    }
                }
            }

            // Compose row: attach, text, send
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconButton {
                    icon: "attach_file"
                    type: IconButton.Tonal
                    disabled: !AirDrop.installed
                    onClicked: AirDrop.pickFiles(root.Window.window)
                }

                StyledTextField {
                    id: composeField

                    Layout.fillWidth: true
                    placeholderText: AirDrop.draftFiles.length > 0 ? Tr.tr("Add a note (optional)") : Tr.tr("Paste a link or write a note…")
                    text: AirDrop.draftText
                    onTextEdited: AirDrop.draftText = text
                    onAccepted: AirDrop.startPicking()
                }

                // The share button: iOS-style share glyph, filled while there is something to send
                ButtonBase {
                    id: shareButton

                    type: ButtonBase.Filled
                    disabled: !AirDrop.hasDraft || !AirDrop.installed
                    isRound: true
                    padding: Tokens.padding.small
                    implicitWidth: implicitHeight
                    implicitHeight: shareIcon.implicitHeight + padding * 2
                    activeColour: Colours.palette.m3primary
                    inactiveColour: Colours.palette.m3primary
                    activeOnColour: Colours.palette.m3onPrimary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    onClicked: AirDrop.startPicking()

                    SvgIcon {
                        id: shareIcon

                        anchors.centerIn: parent
                        name: "share-ios"
                        fontStyle: Tokens.font.icon.medium
                        color: shareButton.onColour
                    }
                }
            }

            // Device picker: who answers, as circles with names, like the share sheet
            ColumnLayout {
                visible: AirDrop.picking
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    CircularIndicator {
                        implicitSize: 18
                        running: AirDrop.picking
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (AirDrop.radioState !== "up")
                                return Tr.tr("Bringing the radio up…");
                            return AirDrop.peers.length > 0 ? Tr.tr("Tap a device to send") : Tr.tr("Looking for devices nearby… wake the iPhone or open its share sheet so it answers.");
                        }
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large

                    Repeater {
                        model: AirDrop.peers

                        Column {
                            id: device

                            required property var modelData

                            width: 112
                            spacing: Tokens.spacing.small

                            StyledRect {
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitWidth: 60
                                implicitHeight: 60
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primaryContainer

                                StateLayer {
                                    radius: parent.radius
                                    onClicked: AirDrop.sendDraft(device.modelData.name)
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: /iphone/i.test(device.modelData.name) ? "smartphone" : /ipad/i.test(device.modelData.name) ? "tablet_mac" : "laptop_mac"
                                    color: Colours.palette.m3onPrimaryContainer
                                    fontStyle: Tokens.font.icon.large
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: device.modelData.name
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurface
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ---- transfers ---------------------------------------------------------------------
        Card {
            id: transfersCard

            // Sends first (they're live), then what came in. Two rows show; more scroll.
            readonly property var rows: [...AirDrop.sends.map(s => Object.assign({
                        row: "send"
                    }, s)), ...AirDrop.received.map(r => Object.assign({
                        row: "recv"
                    }, r))]
            readonly property int rowHeight: 44
            readonly property int maxRows: 2

            visible: rows.length > 0
            title: Tr.tr("Transfers")
            icon: "swap_vert"

            headerItem: TextButton {
                text: Tr.tr("Open folder")
                type: ButtonBase.Text
                onClicked: AirDrop.openDir()
            }

            ListView {
                id: transferList

                Layout.fillWidth: true
                implicitHeight: Math.max(0, Math.min(count, transfersCard.maxRows) * (transfersCard.rowHeight + spacing) - spacing)
                spacing: Tokens.spacing.small
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: transfersCard.rows

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: transferList
                }

                delegate: RowLayout {
                    id: transferRow

                    required property var modelData
                    readonly property bool isSend: modelData.row === "send"
                    readonly property bool isImage: !isSend && modelData.kind === "file" && AirDrop.imageMime(modelData.path) !== ""

                    width: ListView.view.width
                    height: transfersCard.rowHeight
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: {
                            if (transferRow.isSend)
                                return modelData.state === "delivered" ? "check_circle" : modelData.state === "declined" ? "block" : modelData.state === "failed" ? "error" : "upload";
                            return modelData.kind === "url" ? "link" : transferRow.isImage ? "image" : "download_done";
                        }
                        color: {
                            if (!transferRow.isSend || modelData.state === "delivered")
                                return Colours.palette.m3primary;
                            return modelData.state === "failed" || modelData.state === "declined" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant;
                        }
                    }

                    Column {
                        Layout.fillWidth: true

                        StyledText {
                            width: parent.width
                            text: transferRow.isSend ? Tr.tr("%1 → %2").arg(modelData.label ?? modelData.files.map(f => AirDrop.fileName(f)).join(", ")).arg(modelData.target) : modelData.name
                            elide: Text.ElideMiddle
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: {
                                if (!transferRow.isSend)
                                    return Tr.formatDateTime(modelData.time, "hh:mm");
                                switch (modelData.state) {
                                case "looking":
                                    return Tr.tr("Looking for the receiver…");
                                case "sending":
                                    return modelData.total > 0 ? Tr.tr("Sending · %1%").arg(Math.round(modelData.sent / modelData.total * 100)) : (modelData.detail || Tr.tr("Sending…"));
                                case "delivered":
                                    return Tr.tr("Delivered");
                                case "declined":
                                    return Tr.tr("Declined by the receiver");
                                default:
                                    return modelData.detail || Tr.tr("Failed");
                                }
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledProgressBar {
                        visible: transferRow.isSend && modelData.state === "sending" && modelData.total > 0
                        Layout.preferredWidth: 120
                        value: modelData.total > 0 ? modelData.sent / modelData.total : 0
                    }

                    // Copy: the link, the picture itself, or the file's path
                    IconButton {
                        visible: !transferRow.isSend
                        icon: "content_copy"
                        type: IconButton.Text
                        onClicked: AirDrop.copy(modelData)
                    }

                    IconButton {
                        visible: !transferRow.isSend
                        icon: "open_in_new"
                        type: IconButton.Text
                        onClicked: AirDrop.openPath(modelData.path)
                    }
                }
            }
        }

        // ---- footer: link + last error --------------------------------------------------------
        RowLayout {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (AirDrop.lastError)
                        return AirDrop.lastError;
                    const parts = [];
                    if (AirDrop.station)
                        parts.push(AirDrop.station);
                    if (AirDrop.mode)
                        parts.push(AirDrop.channel ? Tr.tr("%1 mode, channel %2").arg(AirDrop.mode).arg(AirDrop.channel) : Tr.tr("%1 mode").arg(AirDrop.mode));
                    if (AirDrop.linkAddress)
                        parts.push(AirDrop.linkAddress);
                    return parts.join(" · ");
                }
                font: Tokens.font.label.small
                color: AirDrop.lastError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // A dashboard card: optional title row with icon and a trailing item, then content.
    component Card: StyledRect {
        id: card

        property string title
        property string icon
        property color accent: "transparent"
        property alias headerItem: headerSlot.sourceComponent
        default property alias content: body.data

        Layout.fillWidth: true
        Layout.preferredWidth: 1 // equal shares in a row
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: accent.a > 0 ? accent : Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                visible: card.title.length > 0
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    visible: card.icon.length > 0
                    text: card.icon
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.title
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }

                Loader {
                    id: headerSlot
                }
            }

            ColumnLayout {
                id: body

                Layout.fillWidth: true
                spacing: Tokens.spacing.small
            }
        }
    }
}
