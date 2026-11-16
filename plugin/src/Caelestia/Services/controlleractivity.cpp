#include "controlleractivity.hpp"

#include <qdir.h>
#include <qfile.h>
#include <qloggingcategory.h>
#include <qsocketnotifier.h>

#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <array>
#include <bitset>
#include <cerrno>

#include "controllerinput.hpp"

namespace {

Q_LOGGING_CATEGORY(lcControllerActivity, "caelestia.services.controlleractivity", QtInfoMsg)

template <std::size_t N>
bool bitSet(const std::array<unsigned char, N>& bits, unsigned int bit) {
    return bit / 8 < N && (bits[bit / 8] & (1U << (bit % 8))) != 0;
}

template <std::size_t N>
std::bitset<N> capabilities(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const auto words = file.readAll().simplified().split(' ');
    std::bitset<N> bits;
    constexpr auto width = sizeof(unsigned long) * 8;
    for (std::size_t bit = 0; bit < N; ++bit) {
        const auto index = static_cast<qsizetype>(bit / width);
        if (index < words.size())
            bits[bit] = (words[words.size() - index - 1].toULongLong(nullptr, 16) & (1ULL << (bit % width))) != 0;
    }
    return bits;
}

} // namespace

namespace caelestia::shell::services {

using Qt::StringLiterals::operator""_s;

struct ControllerActivity::Device {
    int fd = -1;
    QSocketNotifier* notifier = nullptr;
    ControllerInput input;
    bool dropped = false;

    ~Device() {
        if (notifier) {
            notifier->setEnabled(false);
            notifier->deleteLater();
        }
        if (fd >= 0)
            close(fd);
    }
};

ControllerActivity::ControllerActivity(QObject* parent)
    : QObject(parent) {
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &ControllerActivity::scanDevices);
    connect(&m_scanTimer, &QTimer::timeout, this, &ControllerActivity::scanDevices);
    connect(&m_heldTimer, &QTimer::timeout, this, &ControllerActivity::activity);
    m_scanTimer.start(5000); // Also retry after udev applies ACLs or /dev/input appears.
    m_heldTimer.setInterval(1000);
    scanDevices();
}

ControllerActivity::~ControllerActivity() = default;

int ControllerActivity::deviceCount() const {
    return static_cast<int>(m_devices.size());
}

bool ControllerActivity::isController(const QString& eventName) {
    // Inspect only capability metadata before opening anything. In particular,
    // this service never opens keyboard/mouse nodes to discover their type.
    const auto path = u"/sys/class/input/"_s + eventName + u"/device/capabilities/"_s;
    return isGameController(capabilities<KEY_CNT>(path + u"key"_s), capabilities<ABS_CNT>(path + u"abs"_s),
        capabilities<REL_CNT>(path + u"rel"_s));
}

void ControllerActivity::initializeState(Device& device) {
    device.input = ControllerInput{};
    std::array<unsigned char, (KEY_CNT + 7) / 8> keys{};
    if (ioctl(device.fd, EVIOCGKEY(sizeof(keys)), keys.data()) >= 0) {
        for (unsigned int code = 0; code < KEY_CNT; ++code)
            device.input.initializeButton(code, bitSet(keys, code));
    }
    std::array<unsigned char, (ABS_CNT + 7) / 8> axes{};
    if (ioctl(device.fd, EVIOCGBIT(EV_ABS, sizeof(axes)), axes.data()) >= 0) {
        for (unsigned int code = 0; code < ABS_CNT; ++code) {
            input_absinfo info{};
            if (bitSet(axes, code) && ioctl(device.fd, EVIOCGABS(code), &info) >= 0)
                device.input.configureAxis(code, info);
        }
    }
}

void ControllerActivity::scanDevices() {
    const QString inputDir = u"/dev/input"_s;
    if (!m_watcher.directories().contains(inputDir) && QDir(inputDir).exists())
        m_watcher.addPath(inputDir);
    const auto entries = QDir(inputDir).entryList({ u"event*"_s }, QDir::System | QDir::Files);
    const auto previousCount = deviceCount();
    for (auto it = m_devices.begin(); it != m_devices.end();) {
        if (!QFile::exists(it->first))
            it = m_devices.erase(it);
        else
            ++it;
    }
    for (const auto& entry : entries) {
        const auto path = inputDir + u'/' + entry;
        if (m_devices.contains(path) || !isController(entry))
            continue;
        const int fd = open(QFile::encodeName(path).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            qCDebug(lcControllerActivity) << "Cannot read controller" << path << "errno" << errno;
            continue;
        }
        auto device = std::make_unique<Device>();
        device->fd = fd;
        initializeState(*device);
        device->notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(device->notifier, &QSocketNotifier::activated, this, [this, path] { readEvents(path); });
        m_devices.emplace(path, std::move(device));
        qCInfo(lcControllerActivity) << "Monitoring controller" << path;
    }
    if (deviceCount() != previousCount)
        emit deviceCountChanged();
    updateHeldTimer();
}

void ControllerActivity::readEvents(const QString& path) {
    const auto it = m_devices.find(path);
    if (it == m_devices.end())
        return;
    auto& device = *it->second;
    bool changed = false;
    std::array<input_event, 64> events{};
    while (true) {
        const auto bytes = read(device.fd, events.data(), sizeof(events));
        if (bytes < 0 && errno == EINTR)
            continue;
        if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            break;
        if (bytes <= 0) {
            m_devices.erase(it);
            emit deviceCountChanged();
            updateHeldTimer();
            return;
        }
        const auto count = static_cast<std::size_t>(bytes) / sizeof(input_event);
        for (std::size_t i = 0; i < count; ++i) {
            const auto& event = events[i];
            if (event.type == EV_SYN && event.code == SYN_DROPPED) {
                device.dropped = true;
            } else if (device.dropped) {
                if (event.type == EV_SYN && event.code == SYN_REPORT) {
                    initializeState(device);
                    device.dropped = false;
                }
            } else {
                changed |= device.input.process(event.type, event.code, event.value);
            }
        }
    }
    if (changed)
        emit activity();
    updateHeldTimer();
}

void ControllerActivity::updateHeldTimer() {
    const bool held = std::ranges::any_of(m_devices, [](const auto& entry) { return entry.second->input.held(); });
    if (held && !m_heldTimer.isActive())
        m_heldTimer.start();
    else if (!held)
        m_heldTimer.stop();
}

} // namespace caelestia::shell::services
