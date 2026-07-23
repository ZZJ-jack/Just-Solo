#include "FolderSyncManager.h"
#include "MusicManager.h"
#include <QFileInfo>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>

// ============================================================
// 工具函数
// ============================================================

static QStringList audioExtensions() {
    return {"*.mp3", "*.flac", "*.wav", "*.ogg", "*.aac", "*.m4a", "*.wma", "*.opus"};
}

// ============================================================
// FolderSyncManager 实现
// ============================================================

FolderSyncManager::FolderSyncManager(const QString &cacheDir, MusicManager *mgr, QObject *parent)
    : QObject(parent)
    , m_mgr(mgr)
    , m_watcher(new QFileSystemWatcher(this))
    , m_debounce(new QTimer(this))
    , m_cacheDir(cacheDir)
{
    m_debounce->setSingleShot(true);
    m_debounce->setInterval(500);
    connect(m_debounce, &QTimer::timeout, this, &FolderSyncManager::onDebounceTimeout);

    connect(m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &FolderSyncManager::onDirectoryChanged);

    // 加载持久化配置
    loadConfig();

    // 如果启用了同步，启动时全量同步
    if (m_syncEnabled && !m_syncFolders.isEmpty()) {
        QTimer::singleShot(500, this, &FolderSyncManager::fullSync);
    }
}

// ============================================================
// 配置持久化
// ============================================================

void FolderSyncManager::saveConfig() {
    if (m_cacheDir.isEmpty()) return;

    QJsonObject obj;
    obj["syncEnabled"] = m_syncEnabled;

    QJsonArray arr;
    for (const QString &folder : m_syncFolders) {
        arr.append(folder);
    }
    obj["syncFolders"] = arr;

    QJsonDocument doc(obj);
    QFile file(m_cacheDir + "/foldersync.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
    }
}

void FolderSyncManager::loadConfig() {
    if (m_cacheDir.isEmpty()) return;

    QFile file(m_cacheDir + "/foldersync.json");
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) return;

    QJsonObject obj = doc.object();
    m_syncEnabled = obj.value("syncEnabled").toBool(false);

    m_syncFolders.clear();
    QJsonArray arr = obj.value("syncFolders").toArray();
    for (const QJsonValue &v : arr) {
        QString path = v.toString().trimmed();
        if (!path.isEmpty() && QDir(path).exists())
            m_syncFolders.append(path);
    }
}

// ============================================================
// 公开 API
// ============================================================

void FolderSyncManager::addSyncFolder(const QString &path) {
    QString normalized = QDir::cleanPath(path);
    if (normalized.isEmpty() || !QDir(normalized).exists()) return;
    if (m_syncFolders.contains(normalized)) return;

    m_syncFolders.append(normalized);
    saveConfig();
    emit syncFoldersChanged();

    if (m_syncEnabled) {
        fullSync();
    }
}

void FolderSyncManager::removeSyncFolder(int index) {
    if (index < 0 || index >= m_syncFolders.size()) return;

    QString removedPath = m_syncFolders.at(index);
    m_syncFolders.removeAt(index);
    saveConfig();
    emit syncFoldersChanged();

    // 清除该文件夹下的已知路径
    QStringList toRemove;
    for (const QString &known : m_knownPaths) {
        if (known.startsWith(removedPath + "/") || known.startsWith(removedPath + "\\"))
            toRemove.append(known);
    }
    for (const QString &p : toRemove)
        m_knownPaths.remove(p);

    // 重建 watcher（移除已删除文件夹的监控）
    rebuildWatcher();
}

void FolderSyncManager::setSyncEnabled(bool enabled) {
    if (m_syncEnabled == enabled) return;
    m_syncEnabled = enabled;
    saveConfig();
    emit syncEnabledChanged();

    if (enabled && !m_syncFolders.isEmpty()) {
        fullSync();
    } else if (!enabled) {
        // 禁用同步：清空监控
        m_watcher->removePaths(m_watcher->directories());
        m_watchedDirs.clear();
        m_knownPaths.clear();
    }
}

void FolderSyncManager::rescanNow() {
    if (m_syncFolders.isEmpty()) return;
    fullSync();
}

// ============================================================
// 全量同步
// ============================================================

void FolderSyncManager::fullSync() {
    if (m_syncing) return;
    m_syncing = true;
    emit isSyncingChanged();
    emit syncStarted();

    // 收集当前所有音频文件
    QSet<QString> currentPaths;
    for (const QString &root : m_syncFolders) {
        QStringList files = scanAudioFiles(root, true);  // 递归扫描
        for (const QString &f : files)
            currentPaths.insert(f);
    }

    // 新增：当前有但已知没有
    QStringList added;
    for (const QString &p : currentPaths) {
        if (!m_knownPaths.contains(p)) {
            added.append(p);
            m_knownPaths.insert(p);
        }
    }

    // 删除：已知有但当前没有 → 检查文件是否真的不存在
    QStringList removed;
    for (const QString &p : m_knownPaths) {
        if (!currentPaths.contains(p)) {
            if (!QFileInfo::exists(p)) {
                removed.append(p);
            }
        }
    }
    for (const QString &p : removed)
        m_knownPaths.remove(p);

    // 重建 watcher（确保覆盖所有子目录）
    rebuildWatcher();

    // 批量执行
    if (!removed.isEmpty()) {
        for (const QString &f : removed)
            m_mgr->deleteSongByPath(f);
    }
    if (!added.isEmpty()) {
        m_mgr->addFiles(added);
    }

    m_syncing = false;
    emit isSyncingChanged();
    emit syncCompleted(added.size(), removed.size());
}

// ============================================================
// QFileSystemWatcher 管理
// ============================================================

void FolderSyncManager::rebuildWatcher() {
    // 清空原有监控
    QStringList oldDirs = m_watcher->directories();
    if (!oldDirs.isEmpty())
        m_watcher->removePaths(oldDirs);
    m_watchedDirs.clear();

    // 重新添加所有同步根目录及其子目录
    for (const QString &root : m_syncFolders) {
        if (QDir(root).exists())
            addSubDirsRecursive(root);
    }
}

void FolderSyncManager::addSubDirsRecursive(const QString &root) {
    if (m_watchedDirs.contains(root)) return;

    // 添加到 watcher
    m_watcher->addPath(root);
    m_watchedDirs.insert(root);

    // 递归添加子目录（QFileSystemWatcher 不递归，需手动添加）
    QDirIterator it(root, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        QString subDir = it.next();
        if (!m_watchedDirs.contains(subDir)) {
            m_watcher->addPath(subDir);
            m_watchedDirs.insert(subDir);
        }
    }
}

// ============================================================
// 增量变更处理
// ============================================================

void FolderSyncManager::onDirectoryChanged(const QString &path) {
    if (!m_syncEnabled || m_syncFolders.isEmpty()) return;

    m_pendingChanges.insert(path);
    m_debounce->start();  // 每次触发都重启 500ms 定时器
}

void FolderSyncManager::onDebounceTimeout() {
    if (m_pendingChanges.isEmpty()) return;

    // 收集所有变更目录
    QSet<QString> changes = m_pendingChanges;
    m_pendingChanges.clear();

    m_syncing = true;
    emit isSyncingChanged();

    QStringList allAdded, allRemoved;

    // 清理已删除的已知路径（从 knownPaths 中移除）
    QStringList knownPathsList = m_knownPaths.values();
    for (const QString &p : knownPathsList) {
        if (!QFileInfo::exists(p)) {
            // 只移除在同步文件夹下的
            bool underSync = false;
            for (const QString &root : m_syncFolders) {
                if (p.startsWith(root + "/") || p.startsWith(root + "\\")) {
                    underSync = true;
                    break;
                }
            }
            if (underSync) {
                m_knownPaths.remove(p);
                allRemoved.append(p);
            }
        }
    }

    // ---- 执行变更 ----
    if (!allRemoved.isEmpty()) {
        for (const QString &f : allRemoved)
            m_mgr->deleteSongByPath(f);
    }

    // 处理新增文件：重新扫描变更目录下的所有文件
    QStringList newFiles;
    for (const QString &dirPath : changes) {
        QStringList files = scanAudioFiles(dirPath);
        for (const QString &f : files) {
            if (!m_knownPaths.contains(f)) {
                m_knownPaths.insert(f);
                newFiles.append(f);
            }
        }
    }
    if (!newFiles.isEmpty()) {
        m_mgr->addFiles(newFiles);
        allAdded = newFiles;
    }

    m_syncing = false;
    emit isSyncingChanged();
    emit syncCompleted(allAdded.size(), allRemoved.size());
}

// ============================================================
// 文件扫描
// ============================================================

QStringList FolderSyncManager::scanAudioFiles(const QString &dir, bool recursive) const {
    QStringList result;
    QDirIterator::IteratorFlags flags = recursive ? QDirIterator::Subdirectories : QDirIterator::NoIteratorFlags;
    QDirIterator it(dir, audioExtensions(), QDir::Files, flags);
    while (it.hasNext()) {
        result.append(it.next());
    }
    return result;
}

QStringList FolderSyncManager::supportedExtensions() {
    return audioExtensions();
}
