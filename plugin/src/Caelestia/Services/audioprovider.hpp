#pragma once

#include <qqmlintegration.h>
#include <qtimer.h>

#include "audiocollector.hpp"
#include "service.hpp"

namespace caelestia::shell::services {

class AudioProcessor : public QObject {
    Q_OBJECT

public:
    explicit AudioProcessor(QObject* parent = nullptr);
    ~AudioProcessor() override;

    void init();

public slots:
    void start();
    void stop();
    void setCollector(AudioCollector* collector);

protected:
    [[nodiscard]] AudioCollector& collector() const;

    virtual void process() = 0;

private:
    QTimer* m_timer = nullptr;
    AudioCollector* m_collector = nullptr;
};

class AudioProvider : public Service {
    Q_OBJECT
    // Tap the default microphone instead of what is playing. Set before the provider is referenced.
    Q_PROPERTY(bool microphone READ microphone WRITE setMicrophone NOTIFY microphoneChanged)

public:
    explicit AudioProvider(QObject* parent = nullptr);
    ~AudioProvider() override;

    [[nodiscard]] bool microphone() const;
    void setMicrophone(bool microphone);

signals:
    void microphoneChanged();

protected:
    AudioProcessor* m_processor;

    void init();

private:
    QThread* m_thread;
    bool m_microphone = false;

    void start() override;
    void stop() override;
};

} // namespace caelestia::shell::services
