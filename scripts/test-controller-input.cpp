// c++ -std=c++20 -Wall -Wextra scripts/test-controller-input.cpp -o /tmp/test-controller-input
#include "../plugin/src/Caelestia/Services/controllerinput.hpp"

#include <cassert>
#include <iostream>

using caelestia::shell::services::ControllerInput;
using caelestia::shell::services::isGameController;

int main() {
    std::bitset<KEY_CNT> keys;
    std::bitset<ABS_CNT> axes;
    std::bitset<REL_CNT> relative;
    // ydotool and the Wispr helper advertise gamepad buttons along with typing
    // keys, but have no game axes. Neither may be opened by the controller reader.
    keys.set();
    assert(!isGameController(keys, axes, relative));
    axes[ABS_X] = axes[ABS_Y] = true;
    assert(!isGameController(keys, axes, relative));
    keys.reset();
    keys[BTN_GAMEPAD] = true;
    assert(isGameController(keys, axes, relative));
    relative[REL_X] = true;
    assert(!isGameController(keys, axes, relative));
    relative.reset();
    keys.reset();
    keys[BTN_JOYSTICK] = true; // Keychron's separate joystick interface.
    assert(isGameController(keys, axes, relative));
    axes.reset();
    assert(!isGameController(keys, axes, relative));
    keys.reset();
    keys[BTN_DPAD_UP] = keys[BTN_DPAD_DOWN] = keys[BTN_DPAD_LEFT] = keys[BTN_DPAD_RIGHT] = true;
    assert(isGameController(keys, axes, relative)); // Digital-only gamepads.
    keys.reset();
    axes[ABS_X] = axes[ABS_Y] = true;
    assert(!isGameController(keys, axes, relative)); // A touch device isn't a controller.

    ControllerInput input;
    input.configureAxis(ABS_X, { .value = 120, .minimum = -32768, .maximum = 32767, .fuzz = 16, .flat = 1000, .resolution = 0 });
    assert(!input.held());
    for (const int value : { -200, 0, 240, 1000, -1500, 2000 })
        assert(!input.process(EV_ABS, ABS_X, value));
    assert(!input.held());
    assert(input.process(EV_ABS, ABS_X, 10000));
    assert(input.held());
    assert(!input.process(EV_ABS, ABS_X, 10016));
    assert(input.process(EV_ABS, ABS_X, 11000));
    assert(input.process(EV_ABS, ABS_X, 0));
    assert(!input.held());

    input.configureAxis(ABS_Z, { .value = -32768, .minimum = -32768, .maximum = 32767, .fuzz = 0, .flat = 0, .resolution = 0 });
    assert(!input.held());
    assert(!input.process(EV_ABS, ABS_Z, -32760));
    assert(input.process(EV_ABS, ABS_Z, 0));
    assert(input.held());
    assert(input.process(EV_ABS, ABS_Z, -32768));
    assert(!input.held());

    input.configureAxis(ABS_HAT0X, { .value = 0, .minimum = -1, .maximum = 1, .fuzz = 0, .flat = 0, .resolution = 0 });
    assert(input.process(EV_ABS, ABS_HAT0X, -1));
    assert(input.held());
    assert(!input.process(EV_ABS, ABS_HAT0X, -1));
    assert(input.process(EV_ABS, ABS_HAT0X, 0));
    assert(!input.held());

    input.initializeButton(BTN_SOUTH, true);
    assert(!input.held()); // Plugging in with a button down isn't new activity.
    assert(!input.process(EV_KEY, BTN_SOUTH, 1));
    assert(input.process(EV_KEY, BTN_SOUTH, 0));
    assert(input.process(EV_KEY, BTN_SOUTH, 1));
    assert(input.held());
    assert(!input.process(EV_KEY, BTN_SOUTH, 2));
    assert(input.process(EV_KEY, BTN_EAST, 1));
    assert(input.process(EV_KEY, BTN_SOUTH, 0));
    assert(input.held()); // A second held button still counts.
    assert(input.process(EV_KEY, BTN_EAST, 0));
    assert(!input.held());

    assert(!input.process(EV_SYN, SYN_REPORT, 1));
    assert(!input.process(EV_MSC, MSC_TIMESTAMP, 1000));
    assert(!input.process(EV_FF, FF_RUMBLE, 1));
    input.configureAxis(ABS_MISC, { .value = 0, .minimum = -32768, .maximum = 32767, .fuzz = 0, .flat = 0, .resolution = 0 });
    assert(!input.process(EV_ABS, ABS_MISC, 30000));
    assert(!input.process(EV_ABS, ABS_MAX + 1, 1));
    assert(!input.held());

    input = ControllerInput{}; // Unplug/reconnect and buffer resync discard held state.
    input.configureAxis(ABS_X, { .value = 30000, .minimum = -32768, .maximum = 32767, .fuzz = 0, .flat = 0, .resolution = 0 });
    assert(!input.held());
    assert(!input.process(EV_ABS, ABS_X, 30001));
    assert(input.process(EV_ABS, ABS_X, 0));
    assert(!input.held());
    std::cout << "Controller input: device classification, initialization, drift, sticks, triggers, hats, held buttons, noise and resync passed\n";
}
