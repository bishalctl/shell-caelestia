#pragma once

#include <linux/input.h>

#include <algorithm>
#include <array>
#include <bitset>
#include <cstdlib>

namespace caelestia::shell::services {

// Input filtering is independent of Qt and window focus. Initial state and
// small stick noise never count as user activity; held controls do, once used.
class ControllerInput {
public:
    void configureAxis(unsigned int code, const input_absinfo& info) {
        // Motion sensors and touch coordinates are not game controls.
        if (code > ABS_BRAKE && (code < ABS_HAT0X || code > ABS_HAT3Y))
            return;
        const int range = info.maximum - info.minimum;
        if (range <= 0)
            return;
        const bool trigger = code == ABS_Z || code == ABS_RZ || code == ABS_GAS || code == ABS_BRAKE
            || code == ABS_THROTTLE;
        const int neutral = trigger ? info.minimum : info.minimum + range / 2;
        auto& axis = m_axes[code];
        axis = { .configured = true,
            .neutral = neutral,
            .deadzone = std::max(info.flat, range / 20),
            .step = std::max({ 1, info.fuzz, range / 128 }) };
        axis.value = normalize(axis, info.value);
    }

    void initializeButton(unsigned int code, bool pressed) {
        if (code < KEY_CNT)
            m_buttons[code] = pressed;
    }

    bool process(unsigned int type, unsigned int code, int value) {
        if (type == EV_KEY && code < KEY_CNT) {
            const bool pressed = value != 0;
            if (pressed == m_buttons[code])
                return false;
            m_buttons[code] = pressed;
            m_heldButtons[code] = pressed;
            return true;
        }
        if (type != EV_ABS || code >= ABS_CNT || !m_axes[code].configured)
            return false;

        auto& axis = m_axes[code];
        const int normalized = normalize(axis, value);
        const bool active = normalized != axis.neutral;
        if (active == (axis.value != axis.neutral) && std::abs(normalized - axis.value) < axis.step)
            return false;
        if (normalized == axis.value)
            return false;
        axis.value = normalized;
        axis.held = active;
        return true;
    }

    [[nodiscard]] bool held() const {
        return m_heldButtons.any()
            || std::ranges::any_of(m_axes, [](const Axis& axis) { return axis.held; });
    }

private:
    struct Axis {
        bool configured = false;
        int neutral = 0;
        int deadzone = 0;
        int step = 1;
        int value = 0;
        bool held = false;
    };

    static int normalize(const Axis& axis, int value) {
        return std::abs(value - axis.neutral) <= axis.deadzone ? axis.neutral : value;
    }

    std::array<Axis, ABS_CNT> m_axes{};
    std::bitset<KEY_CNT> m_buttons;
    std::bitset<KEY_CNT> m_heldButtons;
};

} // namespace caelestia::shell::services
