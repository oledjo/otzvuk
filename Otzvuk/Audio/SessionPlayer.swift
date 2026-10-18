import AVFoundation
import Combine
import MediaPlayer

/// Сессия прослушивания: голос (по очереди, по кругу, с паузами) + непрерывная фоновая музыка.
/// Пауза, таймер и остановка управляют обоими плеерами сразу.
@MainActor
final class SessionPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    static let fadeDuration: TimeInterval = 4

    @Published private(set) var state: State = .idle
    @Published private(set) var currentID: UUID?
    @Published private(set) var currentTitle = ""
    /// Идёт пауза между записями.
    @Published private(set) var isInGap = false
    /// Готовится развёрнутая копия.
    @Published private(set) var isPreparing = false
    @Published private(set) var isFadingOut = false
    /// Сколько осталось до остановки по таймеру, в секундах (nil — без ограничения).
    @Published private(set) var timerRemaining: Int?

    /// Сообщения об ошибках для показа пользователю.
    var reportError: (String) -> Void = { _ in }

    private let library: Library
    private let music: MusicLibrary
    private let settings: SettingsStore
    private let cache: ReversedAudioCache

    private var queue = PlaybackQueue(ids: [])
    private var voicePlayer: AVAudioPlayer?
    private var musicPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?

    private var playToken = UUID()
    private var gapTask: Task<Void, Never>?
    private var gapDeadline: Date?
    private var pendingGapRemaining: TimeInterval?
    private var tickTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var timerExact: TimeInterval?
    private var consecutiveFailures = 0
    private var resumeAfterInterruption = false

    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var lastSettings: SessionSettings

    init(library: Library, music: MusicLibrary, settings: SettingsStore, cache: ReversedAudioCache) {
        self.library = library
        self.music = music
        self.settings = settings
        self.cache = cache
        self.lastSettings = settings.value
        super.init()

        settings.$value.dropFirst().sink { [weak self] new in
            Task { @MainActor in self?.settingsChanged(new) }
        }.store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            Task { @MainActor in self?.handleInterruption(type: type, options: options) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in
                // Наушники отключили — как в системных приложениях, ставим на паузу.
                if reason == .oldDeviceUnavailable, self?.state == .playing { self?.pause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state != .idle else { return }
                self.stop()
                self.reportError("Звуковая система была перезапущена. Запустите прослушивание заново.")
            }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: - Состояние для тестов и интерфейса

    var isVoicePlaying: Bool { voicePlayer?.isPlaying ?? false }
    var isMusicPlaying: Bool { musicPlayer?.isPlaying ?? false }
    var queueIDs: [UUID] { queue.ids }
    var isActive: Bool { state != .idle }

    // MARK: - Управление

    func start() {
        guard state == .idle else { return }
        let ids = library.selected.map(\.id)
        guard !ids.isEmpty else {
            reportError("Выберите хотя бы одну запись.")
            return
        }
        do {
            try AudioSessionController.activate(.playback)
        } catch {
            reportError("Не удалось включить звук. Попробуйте ещё раз.")
            return
        }

        queue = PlaybackQueue(ids: ids)
        consecutiveFailures = 0
        resumeAfterInterruption = false
        isFadingOut = false
        state = .playing

        let timer = settings.value.timerSeconds
        timerExact = timer > 0 ? TimeInterval(timer) : nil
        timerRemaining = timer > 0 ? timer : nil

        startMusic()
        startTicker()
        installRemoteCommands()
        prefetchReversed()
        playCurrent()
    }

    func pause() {
        guard state == .playing, !isFadingOut else { return }
        state = .paused
        voicePlayer?.pause()
        musicPlayer?.pause()
        keepAlivePlayer?.pause()
        if gapTask != nil, let deadline = gapDeadline {
            pendingGapRemaining = max(0, deadline.timeIntervalSinceNow)
            cancelGap()
        }
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        do {
            try AudioSessionController.activate(.playback)
        } catch {
            reportError("Не удалось продолжить воспроизведение.")
            return
        }
        state = .playing
        musicPlayer?.play()
        keepAlivePlayer?.play()
        if let voice = voicePlayer {
            voice.play()
        } else if let remaining = pendingGapRemaining {
            pendingGapRemaining = nil
            scheduleGap(remaining)
        } else if !isPreparing {
            playCurrent()
        }
        updateNowPlaying()
    }

    func togglePlayPause() {
        switch state {
        case .idle: start()
        case .playing: pause()
        case .paused: resume()
        }
    }

    func next() {
        guard state != .idle, !isFadingOut, !queue.isEmpty else { return }
        if state == .paused {
            do { try AudioSessionController.activate(.playback) } catch { return }
            state = .playing
            musicPlayer?.play()
            keepAlivePlayer?.play()
        }
        advanceAndPlay()
    }

    func stop() {
        playToken = UUID()
        cancelGap()
        pendingGapRemaining = nil
        tickTask?.cancel(); tickTask = nil
        fadeTask?.cancel(); fadeTask = nil
        voicePlayer?.stop(); voicePlayer = nil
        musicPlayer?.stop(); musicPlayer = nil
        keepAlivePlayer?.stop(); keepAlivePlayer = nil
        queue = PlaybackQueue(ids: [])
        currentID = nil
        currentTitle = ""
        isInGap = false
        isPreparing = false
        isFadingOut = false
        timerExact = nil
        timerRemaining = nil
        resumeAfterInterruption = false
        let wasActive = state != .idle
        state = .idle
        removeRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if wasActive { AudioSessionController.deactivate() }
    }

    /// Удаление записи: убираем её из очереди, не прерывая остальное прослушивание.
    func remove(id: UUID) {
        guard state != .idle else { return }
        switch queue.remove(id) {
        case .notFound, .other:
            return
        case .current:
            playToken = UUID()
            cancelGap()
            pendingGapRemaining = nil
            voicePlayer?.stop(); voicePlayer = nil
            isInGap = false
            isPreparing = false
            if queue.isEmpty {
                stop()
            } else if state == .playing {
                playCurrent()
            } else {
                // На паузе: переходим на следующую запись, но звук не запускаем.
                currentID = queue.current
                currentTitle = currentID.flatMap { library.affirmation(id: $0)?.title } ?? ""
                updateNowPlaying()
            }
        }
    }

    // MARK: - Воспроизведение голоса

    private func playCurrent() {
        guard !isFadingOut else { return }
        guard let id = queue.current, let item = library.affirmation(id: id) else {
            // Запись исчезла из библиотеки — убираем её и пробуем следующую.
            if let id = queue.current { queue.remove(id) }
            if queue.isEmpty { stop() } else { playCurrent() }
            return
        }
        cancelGap()
        voicePlayer?.stop()
        voicePlayer = nil
        isInGap = false
        currentID = id
        currentTitle = item.title
        let token = UUID()
        playToken = token
        let reversed = settings.value.reversed
        isPreparing = reversed
        updateNowPlaying()

        let store = library.store
        let cache = self.cache
        Task { [weak self] in
            do {
                let source = store.recordingURL(item.fileName)
                var url = source
                if reversed {
                    url = store.reversedURL(item.reversedFileName)
                    try await cache.ensureReversed(source: source, destination: url)
                }
                guard let self, self.playToken == token else { return }
                try self.begin(url: url)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.playToken == token else { return }
                self.itemFailed(item)
            }
        }
    }

    private func begin(url: URL) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.volume = Float(settings.value.voiceVolume)
        player.prepareToPlay()
        voicePlayer = player
        isPreparing = false
        isInGap = false
        consecutiveFailures = 0
        if state == .playing { player.play() }
        updateNowPlaying()
    }

    private func itemFailed(_ item: Affirmation) {
        isPreparing = false
        consecutiveFailures += 1
        reportError("Не удалось воспроизвести «\(item.title)». Запись пропущена.")
        if consecutiveFailures >= queue.count {
            stop()
            return
        }
        advanceAndPlay()
    }

    private func advanceAndPlay() {
        voicePlayer?.stop()
        voicePlayer = nil
        cancelGap()
        pendingGapRemaining = nil
        isInGap = false
        queue.advance()
        playCurrent()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.voiceDidFinish(player, successfully: flag) }
    }

    private func voiceDidFinish(_ player: AVAudioPlayer, successfully: Bool) {
        guard player === voicePlayer else { return }
        voicePlayer = nil
        guard state == .playing, !isFadingOut else { return }
        if !successfully, let id = currentID, let item = library.affirmation(id: id) {
            itemFailed(item)
            return
        }
        let gap = settings.value.gapSeconds
        if gap <= 0 {
            advanceAndPlay()
        } else {
            isInGap = true
            scheduleGap(TimeInterval(gap))
            updateNowPlaying()
        }
    }

    // MARK: - Паузы между записями

    private func scheduleGap(_ seconds: TimeInterval) {
        cancelGap()
        isInGap = true
        gapDeadline = Date().addingTimeInterval(seconds)
        gapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.gapElapsed()
        }
    }

    private func cancelGap() {
        gapTask?.cancel()
        gapTask = nil
        gapDeadline = nil
    }

    private func gapElapsed() {
        gapTask = nil
        gapDeadline = nil
        guard state == .playing, !isFadingOut else { return }
        advanceAndPlay()
    }

    // MARK: - Музыка

    private func startMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil

        if let id = settings.value.musicTrackID {
            if let url = music.url(for: id) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.numberOfLoops = -1
                    player.volume = isFadingOut ? 0 : Float(settings.value.musicVolume)
                    player.prepareToPlay()
                    if state == .playing { player.play() }
                    musicPlayer = player
                    return
                } catch {
                    reportError("Не удалось воспроизвести мелодию. Прослушивание продолжится без музыки.")
                }
            } else {
                reportError("Выбранная мелодия недоступна. Прослушивание продолжится без музыки.")
            }
        }
        startKeepAlive()
    }

    /// Без музыки в паузах между записями звука нет вовсе. Тихий цикл не даёт системе
    /// приостановить приложение с заблокированным экраном.
    private func startKeepAlive() {
        guard let player = try? AVAudioPlayer(data: Self.silentWAV) else { return }
        player.numberOfLoops = -1
        player.prepareToPlay()
        if state == .playing { player.play() }
        keepAlivePlayer = player
    }

    private static let silentWAV: Data = {
        let sampleRate = 8_000
        let samples = sampleRate // 1 секунда, 16 бит, моно
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples * 2))
        data.append(Data(count: samples * 2))
        return data
    }()

    private func applyVolumes() {
        guard !isFadingOut else { return }
        voicePlayer?.volume = Float(settings.value.voiceVolume)
        musicPlayer?.volume = Float(settings.value.musicVolume)
    }

    private func settingsChanged(_ new: SessionSettings) {
        let old = lastSettings
        lastSettings = new
        guard state != .idle else { return }
        applyVolumes()
        if new.musicTrackID != old.musicTrackID, !isFadingOut { startMusic() }
        if new.timerSeconds != old.timerSeconds, !isFadingOut {
            timerExact = new.timerSeconds > 0 ? TimeInterval(new.timerSeconds) : nil
            timerRemaining = new.timerSeconds > 0 ? new.timerSeconds : nil
        }
    }

    // MARK: - Подготовка развёрнутых копий

    /// Заранее готовим обратные версии всех выбранных записей, чтобы не ждать в процессе.
    private func prefetchReversed() {
        let store = library.store
        let cache = self.cache
        guard settings.value.reversed else { return }
        let items = library.selected
        for item in items {
            Task.detached(priority: .utility) {
                try? await cache.ensureReversed(source: store.recordingURL(item.fileName),
                                                destination: store.reversedURL(item.reversedFileName))
            }
        }
    }

    // MARK: - Таймер остановки

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                let now = Date()
                self.tick(now.timeIntervalSince(last))
                last = now
            }
        }
    }

    private func tick(_ dt: TimeInterval) {
        guard state == .playing, !isFadingOut, let remaining = timerExact else { return }
        let left = remaining - dt
        timerExact = left
        if left <= 0 {
            timerRemaining = 0
            beginFadeOut()
        } else {
            let whole = Int(left.rounded(.up))
            if whole != timerRemaining { timerRemaining = whole }
        }
    }

    /// Короткое плавное затухание голоса и музыки, затем полная остановка.
    private func beginFadeOut() {
        isFadingOut = true
        cancelGap()
        voicePlayer?.setVolume(0, fadeDuration: Self.fadeDuration)
        musicPlayer?.setVolume(0, fadeDuration: Self.fadeDuration)
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration + 0.2))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: - Прерывания

    private func handleInterruption(type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions?) {
        guard state != .idle else { return }
        switch type {
        case .began:
            if state == .playing {
                resumeAfterInterruption = true
                pause()
            }
        case .ended:
            if resumeAfterInterruption, options?.contains(.shouldResume) == true {
                resumeAfterInterruption = false
                resume()
            }
        default:
            break
        }
    }

    // MARK: - Экран блокировки

    private func installRemoteCommands() {
        removeRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (SessionPlayer) -> Void) {
            command.isEnabled = true
            let token = command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                Task { @MainActor in action(self) }
                return .success
            }
            commandTargets.append((command, token))
        }
        add(center.playCommand) { $0.resume() }
        add(center.pauseCommand) { $0.pause() }
        add(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        add(center.nextTrackCommand) { $0.next() }
        center.previousTrackCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func removeRemoteCommands() {
        for (command, token) in commandTargets { command.removeTarget(token) }
        commandTargets.removeAll()
    }

    private func updateNowPlaying() {
        guard state != .idle else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: "Otzvuk",
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let voice = voicePlayer {
            info[MPMediaItemPropertyPlaybackDuration] = voice.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = voice.currentTime
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
