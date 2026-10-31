import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    // Launcher: text to pre-fill the search with on next open (consumed by the launcher)
    property string launcherQuery

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()
}
