import AVFoundation
import Combine

/// Запись голоса: запись → остановка → прослушивание → перезапись или сохранение.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum State: Equatable {
        case idle
        case recording
        case recorded
    }

    struct Take {
        let id: UUID
        let fileName: String
        let duration: TimeInterval
    }

    static let minimumDuration: TimeInterval = 0.5
    static let maximumDuration: TimeInterval = 10 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Уровень сигнала 0...1 для индикатора.
    @Published private(set) var level: Double = 0
    @Published private(set) var isPreviewing = false
    @Published private(set) var previewProgress: Double = 0
    @Published private(set) var permissionDenied = false
    @Published var errorMessage: String?

    private let store: FileStore
    private var recorder: AVAudioRecorder?
    private var previewPlayer: AVAudioPlayer?
    private var ticker: Timer?
    private var currentID: UUID?
    private var observers: [NSObjectProtocol] = []

    init(store: FileStore) {
        self.store = store
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self, raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
                self.handleLoss()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                guard let self, raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable else { return }
                self.handleLoss()
            }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    var hasTake: Bool { state != .idle }

    // MARK: - Запись

    func startRecording() async {
        guard state != .recording else { return }
        errorMessage = nil
        stopPreview()

        let granted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: granted = true
        case .denied: granted = false
        default: granted = await AVAudioApplication.requestRecordPermission()
        }
        permissionDenied = !granted
        guard granted else { return }

        discard()
        let id = UUID()
        let fileName = "\(id.uuidString).m4a"
        let url = store.recordingURL(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try AudioSessionController.activate(.record)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maximumDuration) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.recorder = recorder
            currentID = id
            elapsed = 0
            level = 0
            state = .recording
            startTicker()
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = "Не удалось начать запись. Проверьте микрофон и попробуйте ещё раз."
        }
    }

    func stopRecording() {
        guard state == .recording, let recorder else { return }
        elapsed = recorder.currentTime
        recorder.stop()
        finishRecording()
    }

    private func finishRecording() {
        stopTicker()
        recorder = nil
        level = 0
        guard let id = currentID else { state = .idle; return }
        let url = store.recordingURL("\(id.uuidString).m4a")
        let duration = (try? AudioReverser.duration(of: url)) ?? 0
        if duration < Self.minimumDuration {
            try? FileManager.default.removeItem(at: url)
            currentID = nil
            elapsed = 0
            state = .idle
            errorMessage = "Запись слишком короткая. Попробуйте ещё раз."
        } else {
            elapsed = duration
            state = .recorded
        }
    }

    /// Прерывание звонком или отключение микрофона: оставляем то, что уже записано.
    private func handleLoss() {
        if state == .recording {
            stopRecording()
            if state == .recorded { errorMessage = "Запись остановлена: микрофон стал недоступен." }
        } else if isPreviewing {
            stopPreview()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            // Лимит длительности достигнут сам по себе.
            guard self.state == .recording, recorder === self.recorder else { return }
            self.elapsed = recorder.currentTime
            self.finishRecording()
            if !flag && self.state == .idle { self.errorMessage = "Не удалось сохранить запись." }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard recorder === self.recorder else { return }
            self.discard()
            self.errorMessage = "Ошибка при записи. Попробуйте ещё раз."
        }
    }

    // MARK: - Прослушивание результата

    func togglePreview() {
        isPreviewing ? stopPreview() : startPreview()
    }

    private func startPreview() {
        guard state == .recorded, let id = currentID else { return }
        do {
            try AudioSessionController.activate(.playback)
            let player = try AVAudioPlayer(contentsOf: store.recordingURL("\(id.uuidString).m4a"))
            player.delegate = self
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            isPreviewing = true
            previewProgress = 0
            startTicker()
        } catch {
            errorMessage = "Не удалось воспроизвести запись."
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
        previewProgress = 0
        if state != .recording { stopTicker() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if player === self.previewPlayer { self.stopPreview() }
        }
    }

    // MARK: - Итог

    /// Передаёт запись вызывающему коду: файл остаётся на диске, рекордер возвращается в исходное состояние.
    func commit() -> Take? {
        guard state == .recorded, let id = currentID else { return nil }
        let take = Take(id: id, fileName: "\(id.uuidString).m4a", duration: elapsed)
        stopPreview()
        currentID = nil
        elapsed = 0
        state = .idle
        AudioSessionController.deactivate()
        return take
    }

    /// Прерывает запись/прослушивание и удаляет файл текущей попытки.
    func discard() {
        stopPreview()
        recorder?.stop()
        recorder = nil
        stopTicker()
        if let id = currentID {
            try? FileManager.default.removeItem(at: store.recordingURL("\(id.uuidString).m4a"))
        }
        currentID = nil
        elapsed = 0
        level = 0
        state = .idle
    }

    // MARK: - Таймер интерфейса

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        if state == .recording, let recorder {
            recorder.updateMeters()
            elapsed = recorder.currentTime
            let power = Double(recorder.averagePower(forChannel: 0))
            level = max(0, min(1, (power + 50) / 50))
        }
        if isPreviewing, let player = previewPlayer, player.duration > 0 {
            previewProgress = player.currentTime / player.duration
        }
    }
}
