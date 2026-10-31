#pragma once

#include <qobject.h>
#include <qqmlintegration.h>

#include <functional>

#include "core/circularbuffer.hpp"

namespace caelestia::shell::services {

class TickingService;

// Rolling 0..1 usage history for the dashboard graphs. Samples recorded on every service
// tick are averaged over graphInterval into a single buffer point, so a widget can show e.g.
// an hour of memory history at one point per two minutes while the service still ticks at
// resourceUpdateInterval. The first sample of a run is dropped (the startup spike and the
// first counter delta are both unreliable).
class UsageHistory : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(caelestia::shell::CircularBuffer* buffer READ buffer CONSTANT)
    Q_PROPERTY(int length READ length CONSTANT)
    Q_PROPERTY(int graphInterval READ graphInterval NOTIFY graphIntervalChanged)

public:
    static constexpr int k_length = 30;

    // configInterval reads the user's per-graph interval (ms); <= 0 means "one point per tick"
    explicit UsageHistory(TickingService* service, std::function<int()> configInterval);

    [[nodiscard]] CircularBuffer* buffer() const;
    [[nodiscard]] int length() const;
    [[nodiscard]] int graphInterval() const;

    void record(qreal value);

public slots:
    // Re-evaluate graphInterval after the config or the tick interval changed
    void refreshInterval();

signals:
    void graphIntervalChanged();

private:
    [[nodiscard]] int computeInterval() const;

    TickingService* m_service;
    std::function<int()> m_configInterval;
    CircularBuffer* m_buffer;
    int m_graphInterval = 0;

    qreal m_sum = 0.0;
    int m_count = 0;
    bool m_warmed = false;
};

} // namespace caelestia::shell::services
