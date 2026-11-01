import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // Extra hover region (window coords) belonging to the current popout, e.g. a
    // device menu flying out beside it. Interactions keep the popout open while inside it.
    property Item flyout: null
    // Whether the flyout is currently expanded (the item itself stays registered while it
    // animates closed so its bubble background can shrink back into the popout).
    property bool flyoutOpen: false

    signal detachRequested(mode: string)
}
