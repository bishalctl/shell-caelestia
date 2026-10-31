import Quickshell
import Caelestia.Config
import Caelestia.Services

// Keeps the CPU/GPU/memory services ticking while the dashboard is closed so their usage
// graphs already hold history when it opens. Off: they only run while the dashboard is open.
Scope {
    readonly property bool keepRunning: GlobalConfig.dashboard.performance.continuousHistory

    ServiceRef {
        service: keepRunning ? Cpu : null
    }

    ServiceRef {
        service: keepRunning ? Gpu : null
    }

    ServiceRef {
        service: keepRunning ? Memory : null
    }
}
