import QtQuick

QtObject {
    required property string text
    property string icon
    property string trailingIcon
    // When set, the trailing icon is a button of its own (does not select the item).
    property bool trailingClickable
    property bool trailingActive
    property string trailingTooltip
    property string activeIcon: icon
    property string activeText: text
    property var value

    signal clicked
    signal trailingClicked
}
