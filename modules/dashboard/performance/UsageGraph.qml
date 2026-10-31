import QtQuick
import Caelestia.Components
import Caelestia.Config
import qs.components

// Inset time-series usage graph (0..1) used as a card background. Fed by a service's
// UsageHistory; one point per history.graphInterval, which is also the scroll cadence.
Item {
    id: root

    required property var history
    property color colour: Colours.palette.m3primary

    visible: history.buffer.count > 1

    SparklineItem {
        id: spark

        anchors.fill: parent
        line1: root.history.buffer
        line1Color: root.colour
        line1FillAlpha: 0.18
        maxValue: 1
        historyLength: root.history.length
        lineWidth: 2

        Connections {
            function onValuesChanged(): void {
                slideAnim.restart();
            }

            target: root.history.buffer
        }

        NumberAnimation {
            id: slideAnim

            target: spark
            property: "slideProgress"
            from: 0
            to: 1
            easing.type: Easing.Linear
            duration: root.history.graphInterval
        }
    }
}
