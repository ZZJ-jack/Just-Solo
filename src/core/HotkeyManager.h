#ifndef HOTKEYMANAGER_H
#define HOTKEYMANAGER_H

#include <QObject>
#include <QAbstractNativeEventFilter>
#include <QJsonObject>
#include <QVector>

struct HotkeyBinding {
    int id;               // RegisterHotKey 用唯一 id
    int qtKey;            // Qt::Key
    int qtMods;           // Qt::KeyboardModifiers
    bool valid = false;
};

class HotkeyManager : public QObject, public QAbstractNativeEventFilter
{
    Q_OBJECT
public:
    enum HotkeyId {
        PlayPause = 0,
        Next     = 1,
        Previous = 2,
        Count    = 3
    };

    explicit HotkeyManager(const QString &cacheDir, QObject *parent = nullptr);
    ~HotkeyManager();

    // QML 调用：设置快捷键
    Q_INVOKABLE void setHotkey(int id, int qtKey, int qtMods);
    // QML 调用：获取当前快捷键的 Qt key code
    Q_INVOKABLE int hotkeyKey(int id) const;
    Q_INVOKABLE int hotkeyMods(int id) const;

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

signals:
    void playPauseTriggered();
    void nextTriggered();
    void previousTriggered();
    void hotkeyChanged();

private:
    void registerAll();
    void unregisterAll();
    void registerOne(int id);
    void unregisterOne(int id);
    QJsonObject toJson() const;
    void fromJson(const QJsonObject &obj);
    void load();
    void save();

    QString m_cacheDir;
    QVector<HotkeyBinding> m_bindings;
    static const int ID_BASE = 0x6000;  // 避开系统热键 ID
};

#endif // HOTKEYMANAGER_H
