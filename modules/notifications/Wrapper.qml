import QtQuick
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState
    required property Item sidebarPanel
    property alias osdPanel: content.osdPanel
    property alias sessionPanel: content.sessionPanel
    property alias utilitiesPanel: content.utilitiesPanel

    visible: height > 0
    anchors.topMargin: -5
    // Normally match the sidebar width so popups align with it; in peek mode use the content's own
    // (badge-sized) width so the background hugs the small circle instead of staying full-width.
    implicitWidth: Notifs.peek ? content.implicitWidth : Math.max(sidebarPanel.width, content.implicitWidth)
    implicitHeight: content.implicitHeight

    Content {
        id: content

        anchors.topMargin: -root.anchors.topMargin
        screenState: root.screenState
    }
}
