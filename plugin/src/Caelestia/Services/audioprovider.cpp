#include "audioprovider.hpp"

#include <qloggingcategory.h>
#include <qthread.h>

#include "audiocollector.hpp"
#include "service.hpp"

namespace {

Q_LOGGING_CATEGORY(lcAp, "caelestia.services.ap", QtInfoMsg)

} // namespace

namespace caelestia::shell::services {

AudioProcessor::AudioProcessor(QObject* parent)
    : QObject(parent) {}

AudioProcessor::~AudioProcessor() {
    stop();
}

void AudioProcessor::init() {
    m_timer = new QTimer(this);
    m_timer->setInterval(static_cast<int>(ac::k_chunkSize * 1000.0 / ac::k_sampleRate));
    connect(m_timer, &QTimer::timeout, this, &AudioProcessor::process);
}

void AudioProcessor::start() {
    QMetaObject::invokeMethod(&collector(), &AudioCollector::ref, Qt::QueuedConnection, this);
    if (m_timer) {
        m_timer->start();
    }
}

void AudioProcessor::stop() {
    if (m_timer) {
        m_timer->stop();
    }
    QMetaObject::invokeMethod(&collector(), &AudioCollector::unref, Qt::QueuedConnection, this);
}

void AudioProcessor::setCollector(AudioCollector* collector) {
    m_collector = collector;
}

AudioCollector& AudioProcessor::collector() const {
    return m_collector ? *m_collector : AudioCollector::instance();
}

AudioProvider::AudioProvider(QObject* parent)
    : Service(parent)
    , m_processor(nullptr)
    , m_thread(nullptr) {}

AudioProvider::~AudioProvider() {
    if (m_thread) {
        m_thread->quit();
        m_thread->wait();
    }
}

bool AudioProvider::microphone() const {
    return m_microphone;
}

void AudioProvider::setMicrophone(bool microphone) {
    if (m_microphone != microphone) {
        m_microphone = microphone;
        emit microphoneChanged();
    }
}

void AudioProvider::init() {
    if (!m_processor) {
        qCWarning(lcAp) << "init: attempted to init with no processor set";
        return;
    }

    m_thread = new QThread(this);
    m_processor->moveToThread(m_thread);

    connect(m_thread, &QThread::started, m_processor, &AudioProcessor::init);
    connect(m_thread, &QThread::finished, m_processor, &AudioProcessor::deleteLater);
    connect(m_thread, &QThread::finished, m_thread, &QThread::deleteLater);

    m_thread->start();
}

void AudioProvider::start() {
    if (m_processor) {
        // Create the collector on the main thread, then hand it to the processor before it starts
        auto* collector = &AudioCollector::instance(m_microphone ? CaptureKind::Source : CaptureKind::Sink);
        QMetaObject::invokeMethod(m_processor, &AudioProcessor::setCollector, Qt::QueuedConnection, collector);
        QMetaObject::invokeMethod(m_processor, &AudioProcessor::start);
    }
}

void AudioProvider::stop() {
    if (m_processor) {
        QMetaObject::invokeMethod(m_processor, &AudioProcessor::stop);
    }
}

} // namespace caelestia::shell::services
