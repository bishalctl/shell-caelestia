#pragma once

#include <qqmlintegration.h>
#include <qvariant.h>

#include "tickingservice.hpp"
#include "usagehistory.hpp"

namespace caelestia::shell::services {

class Memory : public TickingService {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(qreal used READ used NOTIFY changed)
    Q_PROPERTY(qreal total READ total NOTIFY changed)
    Q_PROPERTY(qreal percentage READ percentage NOTIFY changed)
    Q_PROPERTY(caelestia::shell::services::UsageHistory* history READ history CONSTANT)

public:
    explicit Memory(QObject* parent = nullptr);

    [[nodiscard]] qreal used() const;
    [[nodiscard]] qreal total() const;
    [[nodiscard]] qreal percentage() const;
    [[nodiscard]] UsageHistory* history() const;

signals:
    void changed();

protected:
    void tick() override;

private:
    UsageHistory* m_history;

    qreal m_used = 0.0;
    qreal m_total = 1.0;
    quint64 m_lastUsed = 0;
    quint64 m_lastTotal = 0;
};

} // namespace caelestia::shell::services
