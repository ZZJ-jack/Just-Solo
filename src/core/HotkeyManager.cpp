#include "HotkeyManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>

#ifdef Q_OS_WIN
#include <windows.h>
#include <QAbstractNativeEventFilter>
#endif

// ---- 工具函数：Qt key → Windows VK ----
#ifdef Q_OS_WIN
static UINT qtKeyToVK(int qtKey)
{
    if (qtKey >= Qt::Key_A && qtKey <= Qt::Key_Z)  return qtKey;
    if (qtKey >= Qt::Key_0 && qtKey <= Qt::Key_9)   return qtKey;
    if (qtKey >= Qt::Key_F1 && qtKey <= Qt::Key_F24)
        return VK_F1 + (qtKey - Qt::Key_F1);

    switch (qtKey) {
    case Qt::Key_MediaPlay:     return VK_MEDIA_PLAY_PAUSE;
    case Qt::Key_MediaNext:     return VK_MEDIA_NEXT_TRACK;
    case Qt::Key_MediaPrevious: return VK_MEDIA_PREV_TRACK;
    case Qt::Key_MediaStop:     return VK_MEDIA_STOP;
    case Qt::Key_Space:         return VK_SPACE;
    case Qt::Key_Left:          return VK_LEFT;
    case Qt::Key_Right:         return VK_RIGHT;
    case Qt::Key_Up:            return VK_UP;
    case Qt::Key_Down:          return VK_DOWN;
    case Qt::Key_Escape:        return VK_ESCAPE;
    case Qt::Key_Return:        return VK_RETURN;
    case Qt::Key_Tab:           return VK_TAB;
    case Qt::Key_Delete:        return VK_DELETE;
    case Qt::Key_Insert:        return VK_INSERT;
    case Qt::Key_Home:          return VK_HOME;
    case Qt::Key_End:           return VK_END;
    case Qt::Key_PageUp:        return VK_PRIOR;
    case Qt::Key_PageDown:      return VK_NEXT;
    case Qt::Key_Backspace:     return VK_BACK;
    case Qt::Key_Comma:         return VK_OEM_COMMA;
    case Qt::Key_Period:        return VK_OEM_PERIOD;
    case Qt::Key_Minus:         return VK_OEM_MINUS;
    case Qt::Key_Plus:          return VK_OEM_PLUS;
    case Qt::Key_Semicolon:     return VK_OEM_1;
    case Qt::Key_Slash:         return VK_OEM_2;
    case Qt::Key_BracketLeft:   return VK_OEM_4;
    case Qt::Key_BracketRight:  return VK_OEM_6;
    case Qt::Key_Backslash:     return VK_OEM_5;
    case Qt::Key_Apostrophe:    return VK_OEM_7;
    }
    return 0;
}

static UINT qtModsToWin(Qt::KeyboardModifiers mods)
{
    UINT mod = 0;
    if (mods & Qt::ControlModifier) mod |= MOD_CONTROL;
    if (mods & Qt::AltModifier)     mod |= MOD_ALT;
    if (mods & Qt::ShiftModifier)   mod |= MOD_SHIFT;
    if (mods & Qt::MetaModifier)    mod |= MOD_WIN;
    return mod;
}
#endif

// ============================================================

HotkeyManager::HotkeyManager(const QString &cacheDir, QObject *parent)
    : QObject(parent), m_cacheDir(cacheDir)
{
    // 初始化默认绑定（valid=true，确保首次运行也能注册）
    m_bindings.resize(Count);
    m_bindings[PlayPause] = {PlayPause, Qt::Key_Space, Qt::ControlModifier | Qt::AltModifier, true};
    m_bindings[Next]      = {Next,      Qt::Key_Right, Qt::ControlModifier | Qt::AltModifier, true};
    m_bindings[Previous]  = {Previous,  Qt::Key_Left, Qt::ControlModifier | Qt::AltModifier, true};

    load();  // 从文件读取用户自定义

    // 延迟注册 + 安装事件过滤器，等消息循环就绪后再注册
    QTimer::singleShot(0, this, [this]() {
        registerAll();
#ifdef Q_OS_WIN
        QCoreApplication::instance()->installNativeEventFilter(this);
#endif
    });
}

HotkeyManager::~HotkeyManager()
{
#ifdef Q_OS_WIN
    QCoreApplication::instance()->removeNativeEventFilter(this);
#endif
    unregisterAll();
}

void HotkeyManager::registerOne(int id)
{
    if (id < 0 || id >= m_bindings.size()) return;
    auto &b = m_bindings[id];
    if (!b.valid) return;

#ifdef Q_OS_WIN
    UINT vk = qtKeyToVK(b.qtKey);
    UINT mod = qtModsToWin(static_cast<Qt::KeyboardModifiers>(b.qtMods));
    if (vk == 0) return;
    RegisterHotKey(nullptr, ID_BASE + id, mod, vk);
#endif
}

void HotkeyManager::unregisterOne(int id)
{
#ifdef Q_OS_WIN
    UnregisterHotKey(nullptr, ID_BASE + id);
#endif
}

void HotkeyManager::registerAll()
{
    for (int i = 0; i < m_bindings.size(); i++)
        registerOne(i);
}

void HotkeyManager::unregisterAll()
{
    for (int i = 0; i < m_bindings.size(); i++)
        unregisterOne(i);
}

void HotkeyManager::setHotkey(int id, int qtKey, int qtMods)
{
    if (id < 0 || id >= m_bindings.size()) return;

    unregisterOne(id);
    m_bindings[id].qtKey = qtKey;
    m_bindings[id].qtMods = qtMods;
    m_bindings[id].valid = (qtKey != 0);
    registerOne(id);
    save();
    emit hotkeyChanged();
}

int HotkeyManager::hotkeyKey(int id) const
{
    if (id < 0 || id >= m_bindings.size()) return 0;
    return m_bindings[id].qtKey;
}

int HotkeyManager::hotkeyMods(int id) const
{
    if (id < 0 || id >= m_bindings.size()) return 0;
    return m_bindings[id].qtMods;
}

bool HotkeyManager::nativeEventFilter(const QByteArray &eventType, void *message, qintptr * /*result*/)
{
#ifdef Q_OS_WIN
    if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
        MSG *msg = static_cast<MSG *>(message);
        if (msg->message == WM_HOTKEY) {
            int id = (int)msg->wParam - ID_BASE;
            if (id >= 0 && id < m_bindings.size()) {
                switch (id) {
                case PlayPause: emit playPauseTriggered(); break;
                case Next:      emit nextTriggered();      break;
                case Previous:  emit previousTriggered();   break;
                }
                return true;
            }
        }
    }
#else
    Q_UNUSED(eventType)
    Q_UNUSED(message)
#endif
    return false;
}

// ---- 持久化 ----

QJsonObject HotkeyManager::toJson() const
{
    QJsonObject obj;
    for (int i = 0; i < m_bindings.size(); i++) {
        const auto &b = m_bindings[i];
        QJsonObject h;
        h["key"] = b.qtKey;
        h["mods"] = b.qtMods;
        obj[QString::number(i)] = h;
    }
    return obj;
}

void HotkeyManager::fromJson(const QJsonObject &obj)
{
    for (int i = 0; i < m_bindings.size(); i++) {
        QJsonValue v = obj.value(QString::number(i));
        if (v.isObject()) {
            QJsonObject h = v.toObject();
            m_bindings[i].qtKey = h.value("key").toInt(m_bindings[i].qtKey);
            m_bindings[i].qtMods = h.value("mods").toInt(m_bindings[i].qtMods);
            m_bindings[i].valid = true;
        }
    }
}

void HotkeyManager::load()
{
    if (m_cacheDir.isEmpty()) return;
    QFile file(m_cacheDir + "/hotkeys.json");
    if (!file.open(QIODevice::ReadOnly)) return;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (doc.isObject())
        fromJson(doc.object());
}

void HotkeyManager::save()
{
    if (m_cacheDir.isEmpty()) return;
    QDir().mkpath(m_cacheDir);
    QFile file(m_cacheDir + "/hotkeys.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(toJson()).toJson());
        file.close();
    }
}
