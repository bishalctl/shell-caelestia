#pragma once

#include <qfilesystemwatcher.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qtimer.h>

#include <map>
#include <memory>

namespace caelestia::shell::services {

class ControllerActivity : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int deviceCount READ deviceCount NOTIFY deviceCountChanged)

public:
    explicit ControllerActivity(QObject* parent = nullptr);
    ~ControllerActivity() override;

    [[nodiscard]] int deviceCount() const;

signals:
    void activity();
    void deviceCountChanged();

private:
    struct Device;
    void scanDevices();
    void readEvents(const QString& path);
    void updateHeldTimer();
    static void initializeState(Device& device);
    static bool isController(const QString& eventName);

    QFileSystemWatcher m_watcher;
    QTimer m_scanTimer;
    QTimer m_heldTimer;
    std::map<QString, std::unique_ptr<Device>> m_devices;
};

} // namespace caelestia::shell::services
