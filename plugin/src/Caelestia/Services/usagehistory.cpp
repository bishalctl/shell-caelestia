#include "usagehistory.hpp"

#include <algorithm>
#include <cmath>

#include "tickingservice.hpp"

namespace caelestia::shell::services {

UsageHistory::UsageHistory(TickingService* service, std::function<int()> configInterval)
    : QObject(service)
    , m_service(service)
    , m_configInterval(std::move(configInterval))
    , m_buffer(new CircularBuffer(this)) {
    m_buffer->setCapacity(k_length + 1);
    m_graphInterval = computeInterval();
    QObject::connect(service, &TickingService::updateIntervalChanged, this, &UsageHistory::refreshInterval);
}

CircularBuffer* UsageHistory::buffer() const {
    return m_buffer;
}

int UsageHistory::length() const {
    return k_length;
}

int UsageHistory::graphInterval() const {
    return m_graphInterval;
}

int UsageHistory::computeInterval() const {
    const int configured = m_configInterval ? m_configInterval() : 0;
    return configured > 0 ? configured : m_service->updateInterval();
}

void UsageHistory::refreshInterval() {
    const int interval = computeInterval();
    if (interval == m_graphInterval) {
        return;
    }
    m_graphInterval = interval;
    emit graphIntervalChanged();
}

void UsageHistory::record(qreal value) {
    if (!m_warmed) {
        m_warmed = true;
        return;
    }

    m_sum += value;
    ++m_count;

    const int tick = std::max(1, m_service->updateInterval());
    const int ticksPerPoint = std::max(1, static_cast<int>(std::lround(static_cast<double>(m_graphInterval) / tick)));
    if (m_count < ticksPerPoint) {
        return;
    }

    m_buffer->push(m_sum / m_count);
    m_sum = 0.0;
    m_count = 0;
}

} // namespace caelestia::shell::services
