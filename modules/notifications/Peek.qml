pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Compact "peek" indicator shown in place of a full popup card when Notifs.peek is set: just the
// app's circular logo, so an arriving notification is visible without taking up space.
ClipRect {
    id: root

    required property NotifData modelData
    required property ScreenState screenState
    readonly property int urgency: modelData?.urgency ?? NotificationUrgency.Normal
    readonly property bool hasImage: (modelData?.image.length ?? 0) > 0
    readonly property bool hasAppIcon: (modelData?.resolvedAppIcon.length ?? 0) > 0

    implicitWidth: TokenConfig.sizes.notifs.image
    implicitHeight: TokenConfig.sizes.notifs.image
    radius: Tokens.rounding.full
    color: urgency === NotificationUrgency.Critical ? Colours.palette.m3error : urgency === NotificationUrgency.Low ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : Colours.palette.m3secondaryContainer

    // Clicking the badge opens the notification panel on this screen and dismisses the badge.
    StateLayer {
        radius: root.radius
        onClicked: {
            root.screenState.sidebar = true;
            root.modelData.popup = false;
        }
    }

    Loader {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: sourceComponent === iconComp ? 1 : 0
        sourceComponent: root.hasImage ? imageComp : root.hasAppIcon ? appIconComp : iconComp
    }

    Component {
        id: imageComp

        Image {
            source: Qt.resolvedUrl(root.modelData.image)
            fillMode: Image.PreserveAspectCrop
            width: root.implicitWidth
            height: root.implicitHeight
            sourceSize: {
                const size = TokenConfig.sizes.notifs.image * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1);
                return Qt.size(size, size);
            }
            cache: false
            asynchronous: true
        }
    }

    Component {
        id: appIconComp

        ColouredIcon {
            implicitSize: Math.round(TokenConfig.sizes.notifs.image * 0.6)
            source: root.modelData.resolvedAppIcon
            colour: root.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
            layer.enabled: root.modelData.resolvedAppIcon.includes("symbolic")
        }
    }

    Component {
        id: iconComp

        MaterialIcon {
            text: Icons.getNotifIcon(root.modelData?.summary ?? "", root.urgency)
            color: root.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
            fontStyle: Tokens.font.icon.medium
        }
    }
}
