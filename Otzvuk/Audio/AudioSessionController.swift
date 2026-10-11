import AVFoundation

enum AudioSessionController {
    enum Mode { case playback, record }

    static func activate(_ mode: Mode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .playback:
            try session.setCategory(.playback, mode: .default, options: [])
        case .record:
            try session.setCategory(.record, mode: .default, options: [])
        }
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
