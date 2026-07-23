#ifndef FOLDERSYNCMANAGER_H
#define FOLDERSYNCMANAGER_H

#include <QObject>
#include <QStringList>
#include <QSet>
#include <QFileSystemWatcher>
#include <QTimer>

class MusicManager;

// ============================================================
// 文件夹同步管理器
// 监控用户配置的文件夹，自动将新增/删除的音乐文件同步到音乐库
// ============================================================
class FolderSyncManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList syncFolders READ syncFolders NOTIFY syncFoldersChanged)
    Q_PROPERTY(bool syncEnabled READ syncEnabled WRITE setSyncEnabled NOTIFY syncEnabledChanged)
    Q_PROPERTY(bool isSyncing READ isSyncing NOTIFY isSyncingChanged)

public:
    explicit FolderSyncManager(const QString &cacheDir, MusicManager *mgr, QObject *parent = nullptr);

    // ---- QML 可调用 API ----
    Q_INVOKABLE QStringList syncFolders() const { return m_syncFolders; }
    Q_INVOKABLE void addSyncFolder(const QString &path);
    Q_INVOKABLE void removeSyncFolder(int index);
    Q_INVOKABLE void rescanNow();                     // 手动触发全量同步
    bool syncEnabled() const { return m_syncEnabled; }
    Q_INVOKABLE void setSyncEnabled(bool enabled);
    Q_INVOKABLE bool isSyncing() const { return m_syncing; }

signals:
    void syncFoldersChanged();
    void syncEnabledChanged();
    void isSyncingChanged();
    void syncStarted();
    void syncCompleted(int added, int removed);

private:
    void saveConfig();
    void loadConfig();
    void rebuildWatcher();                            // 重建 QFileSystemWatcher
    void addSubDirsRecursive(const QString &root);    // 递归添加子目录到 watcher
    void onDirectoryChanged(const QString &path);
    void onDebounceTimeout();
    void fullSync();                                  // 全量扫描比对
    QStringList scanAudioFiles(const QString &dir, bool recursive = false) const;
    static QStringList supportedExtensions();

    MusicManager *m_mgr;
    QFileSystemWatcher *m_watcher;
    QTimer *m_debounce;

    QStringList m_syncFolders;       // 用户配置的同步根目录
    QSet<QString> m_watchedDirs;     // 实际被监控的目录集（含子目录）
    QSet<QString> m_knownPaths;      // 已知文件路径快照（用于侦测删除）
    bool m_syncEnabled = false;
    bool m_syncing = false;
    QString m_cacheDir;

    QSet<QString> m_pendingChanges;  // debounce 期间收集的变更目录
};

#endif // FOLDERSYNCMANAGER_H
