#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"
#include "enums.hpp"

namespace caelestia::shell::config {

class NotifsConfig : public settings::ObjectNode {
    CONFIG_NODE(NotifsConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(bool, expire, true)
    CONFIG_GLOBAL_ENUM_PROPERTY(NotifsFullscreen, fullscreen, NotifsFullscreen::On)
    CONFIG_GLOBAL_PROPERTY(int, defaultExpireTimeout, 5000)
    CONFIG_GLOBAL_PROPERTY(int, fullscreenExpireTimeout, 2000)
    CONFIG_PROPERTY(qreal, clearThreshold, 0.3)
    CONFIG_PROPERTY(int, expandThreshold, 20)
    CONFIG_GLOBAL_PROPERTY(bool, actionOnClick, false)
    CONFIG_PROPERTY(int, groupPreviewNum, 3)
    CONFIG_PROPERTY(bool, openExpanded, false)
    // Sound played on new notifications. Empty soundPath = bundled assets/sounds/notification.wav;
    // soundTarget is an optional PipeWire node name (e.g. a dedicated notification sink) for pw-play --target.
    CONFIG_GLOBAL_PROPERTY(QString, soundPath, {})
    CONFIG_GLOBAL_PROPERTY(QString, soundTarget, {})
};

} // namespace caelestia::shell::config
