import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

Item {
    id: root

    required property var modelData // { id, preview, isImage }
    required property ScreenState screenState
    required property var view // the ListView (to drive currentIndex on hover)
    required property int index

    readonly property bool isImage: root.modelData?.isImage ?? false

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    // "[[ binary data 3 MiB png 1920x1080 ]]" -> "Image · png · 1920×1080"
    function pretty(preview: string): string {
        const p = preview ?? "";
        const m = p.match(/\[\[ binary data\s+.+?\s+(png|jpe?g|gif|bmp|webp|tiff?|ico|svg)\s+(\d+x\d+)/i);
        return m ? Tr.tr("Image · %1 · %2").arg(m[1]).arg(m[2].replace("x", "×")) : p;
    }

    // Hovering highlights the row so the preview panel follows the mouse,
    // unless keyboard nav is scrolling the list under a stationary cursor
    HoverHandler {
        onHoveredChanged: if (hovered && root.view && !root.view.keyboardNavActive)
            root.view.currentIndex = root.index
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            if (root.modelData)
                Clipboard.copy(root.modelData);
            root.screenState.launcher = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.isImage ? "image" : "content_paste"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        StyledText {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: root.isImage ? root.pretty(root.modelData?.preview) : (root.modelData?.preview ?? "")
            font: Tokens.font.body.medium
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
