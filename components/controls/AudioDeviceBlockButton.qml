import QtQuick
import QtQuick.Controls as QQC
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

StyledRect {
    id: root

    required property string deviceName
    property bool inputDevice: false
    readonly property bool blocked: inputDevice ? AudioDevices.isSourceBlocked(deviceName) : AudioDevices.isSinkBlocked(deviceName)

    function toggle(): void {
        if (root.inputDevice)
            AudioDevices.toggleSourceBlocked(root.deviceName);
        else
            AudioDevices.toggleSinkBlocked(root.deviceName);
    }

    implicitWidth: implicitHeight
    implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
    radius: Tokens.rounding.full
    color: blocked ? Colours.palette.m3errorContainer : "transparent"
    activeFocusOnTab: true

    QQC.ToolTip.visible: blockMouse.containsMouse
    QQC.ToolTip.text: blocked ? Tr.tr("Blocked from automatic switching — click to allow") : Tr.tr("Allow automatic switching — click to block")
    Accessible.role: Accessible.Button
    Accessible.name: QQC.ToolTip.text
    Accessible.onPressAction: root.toggle()
    Keys.onSpacePressed: root.toggle()
    Keys.onReturnPressed: root.toggle()

    StateLayer {
        id: blockMouse

        onClicked: root.toggle()
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: root.blocked ? "block" : "sync"
        color: root.blocked ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
    }
}
