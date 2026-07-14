#ifndef MUSICMANAGER_H
#define MUSICMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QStringList>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QFileInfo>
#include <QDir>
#include <QTimer>

class MusicManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStateChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentCover READ currentCover NOTIFY currentTrackChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)

public:
    explicit MusicManager(QObject *parent = nullptr);

    Q_INVOKABLE void addFiles(const QStringList &paths);
    Q_INVOKABLE void addFolder(const QString &path);
    Q_INVOKABLE void removeTrack(int index);
    Q_INVOKABLE void clearPlaylist();

    Q_INVOKABLE void playIndex(int index);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

    QVariantList playlist() const { return m_playlist; }
    int currentIndex() const { return m_currentIndex; }
    bool isPlaying() const { return m_player && m_player->playbackState() == QMediaPlayer::PlayingState; }
    bool isLoading() const { return m_loading; }

    QString currentTitle() const;
    QString currentArtist() const;
    QString currentCover() const { return m_currentCover; }

    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE qint64 duration() const;
    Q_INVOKABLE void seek(qint64 ms);

signals:
    void playlistChanged();
    void currentIndexChanged();
    void playbackStateChanged();
    void currentTrackChanged();
    void positionChanged(qint64 ms);
    void durationChanged();
    void isLoadingChanged();

private:
    void updateCurrentTrack();
    void scanFolder(const QString &path);
    void processNextPending();
    static QStringList supportedExtensions();

    QVariantList m_playlist;
    int m_currentIndex = -1;
    QString m_currentCover;
    bool m_loading = false;

    QStringList m_pendingPaths;
    QTimer *m_loadTimer = nullptr;

    QMediaPlayer *m_player = nullptr;
    QAudioOutput *m_audioOutput = nullptr;
};

#endif
