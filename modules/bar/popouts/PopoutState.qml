import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // Extra hover region (window coords) belonging to the current popout, e.g. a
    // device menu flying out beside it. Interactions keep the popout open while inside it.
    property Item flyout: null

    signal detachRequested(mode: string)
}
