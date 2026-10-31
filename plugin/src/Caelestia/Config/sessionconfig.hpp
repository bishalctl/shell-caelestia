#pragma once

#include <qstring.h>
#include <qstringlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::shell::config {

using Qt::StringLiterals::operator""_s;

class SessionIcons : public settings::ObjectNode {
    CONFIG_NODE(SessionIcons, settings::ObjectNode)

    CONFIG_PROPERTY(QString, logout, u"logout"_s)
    CONFIG_PROPERTY(QString, shutdown, u"power_settings_new"_s)
    CONFIG_PROPERTY(QString, hibernate, u"downloading"_s)
    CONFIG_PROPERTY(QString, reboot, u"cached"_s)
    CONFIG_PROPERTY(QString, lock, u"lock"_s)
    CONFIG_PROPERTY(QString, suspend, u"bedtime"_s)
    CONFIG_PROPERTY(QString, rebootForce, u"restart_alt"_s)
    CONFIG_PROPERTY(QString, shutdownForce, u"power_off"_s)
};

class SessionCommands : public settings::ObjectNode {
    CONFIG_NODE(SessionCommands, settings::ObjectNode)

    CONFIG_PROPERTY(QStringList, logout, { u"logout"_s })
    CONFIG_PROPERTY(QStringList, shutdown, { u"poweroff"_s })
    CONFIG_PROPERTY(QStringList, hibernate, { u"hibernate"_s })
    CONFIG_PROPERTY(QStringList, reboot, { u"reboot"_s })
    CONFIG_PROPERTY(QStringList, lock, DEFAULT_ARG({ u"loginctl"_s, u"lock-session"_s }))
    CONFIG_PROPERTY(QStringList, suspend, { u"suspend"_s })
    // systemctl -f talks to PID 1 directly and needs root; sudo -n so a missing rule fails fast
    CONFIG_PROPERTY(QStringList, rebootForce, DEFAULT_ARG({ u"sudo"_s, u"-n"_s, u"systemctl"_s, u"reboot"_s, u"-f"_s }))
    CONFIG_PROPERTY(QStringList, shutdownForce, DEFAULT_ARG({ u"sudo"_s, u"-n"_s, u"systemctl"_s, u"poweroff"_s, u"-f"_s }))
};

class SessionConfig : public settings::ObjectNode {
    CONFIG_NODE(SessionConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, dragThreshold, 30)
    CONFIG_PROPERTY(bool, vimKeybinds, false)
    CONFIG_SUBOBJECT(SessionIcons, icons)
    CONFIG_SUBOBJECT(SessionCommands, commands)
};

} // namespace caelestia::shell::config
