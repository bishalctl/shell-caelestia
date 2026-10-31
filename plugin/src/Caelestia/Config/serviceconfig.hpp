#pragma once

#include <qstring.h>
#include <qvariantlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"
#include "enums.hpp"

namespace caelestia::shell::config {

using Qt::StringLiterals::operator""_s;
using settings::vmap;

class PlayerAlias : public settings::ObjectNode {
    CONFIG_NODE(PlayerAlias, settings::ObjectNode)

    CONFIG_PROPERTY(QString, from, {})
    CONFIG_PROPERTY(QString, to, {})
};
CONFIG_LIST_TYPE(PlayerAlias, PlayerAliasList)

// Per-monitor brightness override. `match` is "model:X" | "serial:X" | "name:X" (bare = name);
// `method` is "ddc" | "backlight" | "hdr" | "apple" | "none" (empty = auto-detect);
// hdrMinNits/hdrMaxNits override the HDR slider range for that monitor (0 = inherit).
class BrightnessRule : public settings::ObjectNode {
    CONFIG_NODE(BrightnessRule, settings::ObjectNode)

    CONFIG_PROPERTY(QString, match, {})
    CONFIG_PROPERTY(QString, method, {})
    CONFIG_PROPERTY(int, hdrMinNits, 0)
    CONFIG_PROPERTY(int, hdrMaxNits, 0)
};
CONFIG_LIST_TYPE(BrightnessRule, BrightnessRuleList)

class ServiceConfig : public settings::ObjectNode {
    CONFIG_NODE(ServiceConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(QString, weatherLocation, {})
    // Auto guesses based on locale
    CONFIG_GLOBAL_ENUM_PROPERTY(TemperatureUnit, weatherUnits, TemperatureUnit::Auto)
    // Always Celsius by default cause apparently even imperial system users don't use Fahrenheit for perf temps?
    CONFIG_GLOBAL_ENUM_PROPERTY(TemperatureUnit, sensorUnits, TemperatureUnit::Celsius)
    // Binary (KiB/MiB/GiB) or decimal (KB/MB/GB) data sizes
    CONFIG_GLOBAL_ENUM_PROPERTY(DataUnit, dataUnits, DataUnit::Binary)
    CONFIG_GLOBAL_ENUM_PROPERTY(ClockFormat, clockFormat, ClockFormat::Auto)
    CONFIG_GLOBAL_ENUM_PROPERTY(GpuType, gpuType, GpuType::Auto)
    CONFIG_GLOBAL_PROPERTY(int, visualiserBars, 60)
    CONFIG_GLOBAL_PROPERTY(qreal, audioIncrement, 0.1)
    CONFIG_GLOBAL_PROPERTY(qreal, brightnessIncrement, 0.1)
    CONFIG_GLOBAL_PROPERTY(qreal, maxVolume, 1.0)
    CONFIG_GLOBAL_PROPERTY(bool, smartScheme, true)
    CONFIG_GLOBAL_PROPERTY(QString, defaultPlayer, u"Spotify"_s)
    CONFIG_GLOBAL_LIST(PlayerAliasList, playerAliases,
        DEFAULT_ARG({
            vmap({ { u"from"_s, u"com.github.th_ch.youtube_music"_s }, { u"to"_s, u"YT Music"_s } }),
        }))
    CONFIG_GLOBAL_ENUM_PROPERTY(LyricsBackend, lyricsBackend, LyricsBackend::Auto)
    // Escape hatch: broken DDC/CI firmware can hang the i2c bus, so all probing/writes can be disabled
    CONFIG_GLOBAL_PROPERTY(bool, ddcEnabled, true)
    // Keep-latest write spacing per DDC monitor; VESA floor is 50ms, raise for flaky HDMI i2c paths
    CONFIG_GLOBAL_PROPERTY(int, ddcMinWriteIntervalMs, 100)
    // Empty = auto-resolve (firmware > platform > raw); set to pin e.g. amdgpu_bl1 on hybrid-GPU laptops
    CONFIG_GLOBAL_PROPERTY(QString, backlightDevice, {})
    // Slider range for SDR white luminance on HDR monitors (nits); 80 = SDR reference white.
    // The max is overridden per panel by its EDID-declared peak when present.
    CONFIG_GLOBAL_PROPERTY(int, hdrMinNits, 80)
    CONFIG_GLOBAL_PROPERTY(int, hdrMaxNits, 400)
    // DRM hotplug events arrive in bursts during link training; debounce before re-detecting
    CONFIG_GLOBAL_PROPERTY(int, hotplugDebounceMs, 1500)
    CONFIG_GLOBAL_LIST(BrightnessRuleList, brightnessRules, {})
};

} // namespace caelestia::shell::config
