#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::shell::config {

class DashboardPerformance : public settings::ObjectNode {
    CONFIG_NODE(DashboardPerformance, settings::ObjectNode)

    CONFIG_PROPERTY(bool, showBattery, true)
    CONFIG_PROPERTY(bool, showGpu, true)
    CONFIG_PROPERTY(bool, showCpu, true)
    CONFIG_PROPERTY(bool, showMemory, true)
    CONFIG_PROPERTY(bool, showStorage, true)
    CONFIG_PROPERTY(bool, showNetwork, true)

    // Keep the CPU/GPU/memory services ticking while the dashboard is closed so the usage
    // graphs already have history when it opens (daemons/PerfHistory.qml)
    CONFIG_GLOBAL_PROPERTY(bool, continuousHistory, true)
    // Per-graph point interval (ms). 0 = resourceUpdateInterval. Samples taken every
    // resourceUpdateInterval are averaged over this window into a single graph point.
    CONFIG_GLOBAL_PROPERTY(int, cpuGraphInterval, 0)
    CONFIG_GLOBAL_PROPERTY(int, gpuGraphInterval, 0)
    CONFIG_GLOBAL_PROPERTY(int, memGraphInterval, 0)
};

class DashboardConfig : public settings::ObjectNode {
    CONFIG_NODE(DashboardConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, showOnHover, true)
    CONFIG_PROPERTY(bool, showDashboard, true)
    CONFIG_PROPERTY(bool, showMedia, true)
    CONFIG_PROPERTY(bool, showPerformance, true)
    CONFIG_PROPERTY(bool, showWeather, true)
    CONFIG_PROPERTY(bool, showClockSeconds, false)
    CONFIG_GLOBAL_PROPERTY(int, mediaUpdateInterval, 500)
    CONFIG_GLOBAL_PROPERTY(int, resourceUpdateInterval, 2000)
    CONFIG_PROPERTY(int, dragThreshold, 50)
    CONFIG_SUBOBJECT(DashboardPerformance, performance)
};

} // namespace caelestia::shell::config
