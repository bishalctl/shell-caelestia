import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData // { id, name, subtitle, icon, picture, command }
    required property var list // the AppList (drives currentIndex on hover)
    required property int index

    readonly property bool fav: root.modelData ? Browsers.favs.indexOf(root.modelData.id) !== -1 : false

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    HoverHandler {
        onHoveredChanged: if (hovered && root.list)
            root.list.currentIndex = root.index
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            if (root.modelData)
                Browsers.launch(root.modelData);
            root.list.screenState.launcher = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        Item {
            id: icon

            implicitWidth: parent.height * 0.8
            implicitHeight: parent.height * 0.8
            anchors.verticalCenter: parent.verticalCenter

            // True only once the avatar file actually loads (else fall back to the icon)
            readonly property bool hasPicture: (root.modelData?.picture ?? "") !== "" && avatar.status === Image.Ready

            ClipRect {
                anchors.fill: parent
                visible: icon.hasPicture
                radius: Tokens.rounding.full

                Image {
                    id: avatar

                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    source: (root.modelData?.picture ?? "") !== "" ? `file://${root.modelData.picture}` : ""
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                }
            }

            IconImage {
                anchors.fill: parent
                visible: !icon.hasPicture
                asynchronous: true
                source: Quickshell.iconPath(root.modelData?.icon, "applications-internet")
            }
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - favIcon.width
            implicitHeight: name.implicitHeight + sub.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
            }

            StyledText {
                id: sub

                anchors.top: name.bottom

                text: root.modelData?.subtitle ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
                width: root.width - icon.width - favIcon.width - Tokens.rounding.extraLargeIncreased
            }
        }

        Loader {
            id: favIcon

            asynchronous: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            active: root.fav

            sourceComponent: MaterialIcon {
                text: "favorite"
                fill: 1
                color: Colours.palette.m3primary
            }
        }
    }
}
