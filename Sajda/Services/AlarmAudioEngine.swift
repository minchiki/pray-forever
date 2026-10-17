import AVFoundation
import MediaPlayer
import UIKit

/// Держит приложение живым в фоне (тихий звук) и играет громкий зацикленный сигнал.
@MainActor
final class AlarmAudioEngine {
    /// `.listening` — сигнал приглушён, пока человек читает суру в микрофон.
    enum Mode: Equatable { case idle, keepAlive, ringing, listening }

    private(set) var mode: Mode = .idle
    private var player: AVAudioPlayer?
    /// Будильник всегда звучит на максимальной системной громкости.
    private let targetVolume: Float = 1
    private var volumeObservation: NSKeyValueObservation?
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))

    init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleMediaReset),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.addObserver(self, selector: #selector(handleRouteChange),
                           name: AVAudioSession.routeChangeNotification, object: nil)
    }

    // MARK: - Public

    /// Тихое воспроизведение, чтобы iOS не усыпляла приложение и таймер будильника работал в фоне.
    func startKeepAlive() {
        guard mode != .ringing, mode != .listening else { return }
        guard mode != .keepAlive || player?.isPlaying != true else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try makePlayer(resource: "silence.wav", volume: 0.01)
            player?.play()
            mode = .keepAlive
        } catch {
            mode = .idle
        }
    }

    func stopKeepAlive() {
        guard mode == .keepAlive else { return }
        stopPlayer()
        mode = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func startRinging(sound: AlarmSound) {
        do {
            try activateRingingSession()
            stopPlayer()
            player = try makePlayer(resource: sound.fileName, volume: 1)
            player?.play()
            mode = .ringing
            enforceSystemVolume()
            observeVolume()
        } catch {
            mode = .idle
        }
    }

    /// Глушит сигнал и переключает сессию на запись: микрофон не должен слышать будильник.
    func beginListening() {
        volumeObservation = nil
        stopPlayer()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? session.setActive(true)
        mode = .listening
    }

    func stopRinging(keepAlive: Bool) {
        guard mode == .ringing || mode == .listening else { return }
        volumeObservation = nil
        stopPlayer()
        mode = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if keepAlive { startKeepAlive() }
    }

    /// Короткое прослушивание звука в настройках.
    func preview(sound: AlarmSound) {
        guard mode != .ringing, mode != .listening else { return }
        let wasKeepAlive = mode == .keepAlive
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        stopPlayer()
        player = try? makePlayer(resource: sound.fileName, volume: 1, loops: 0)
        player?.play()
        let previewDuration: TimeInterval = 3
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDuration) { [weak self] in
            guard let self, self.mode != .ringing, self.mode != .listening else { return }
            self.stopPlayer()
            self.mode = .idle
            if wasKeepAlive { self.startKeepAlive() }
        }
    }

    // MARK: - Private

    /// Категория .playback звучит даже при беззвучном режиме.
    /// Сначала эксклюзивно (глушим чужую музыку); если iOS не позволяет в фоне — с приглушением остальных.
    private func activateRingingSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        }
    }

    private func makePlayer(resource: String, volume: Float, loops: Int = -1) throws -> AVAudioPlayer {
        guard let url = Bundle.main.url(forResource: resource, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = loops
        player.volume = volume
        player.prepareToPlay()
        return player
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
    }

    /// Поднимает системную громкость (приём, которым пользуются будильники в App Store).
    private func enforceSystemVolume() {
        if volumeView.superview == nil, let window = Self.keyWindow {
            window.addSubview(volumeView)
        }
        let target = targetVolume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let slider = self?.volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
            if abs(slider.value - target) > 0.01 { slider.value = target }
        }
    }

    /// Если пользователь убавляет громкость кнопками — возвращаем её обратно.
    private func observeVolume() {
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
                guard let self, self.mode == .ringing, newValue < self.targetVolume - 0.01 else { return }
                self.enforceSystemVolume()
            }
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.windows.first
    }

    private func resumeCurrentMode() {
        switch mode {
        case .ringing:
            try? AVAudioSession.sharedInstance().setActive(true)
            if player?.isPlaying != true { player?.play() }
            enforceSystemVolume()
        case .keepAlive:
            try? AVAudioSession.sharedInstance().setActive(true)
            if player?.isPlaying != true { player?.play() }
        case .idle, .listening:
            break
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        // Возобновляем всегда, даже если система не прислала .shouldResume (например, после звонка).
        Task { @MainActor in self.resumeCurrentMode() }
    }

    @objc private func handleRouteChange() {
        Task { @MainActor in self.resumeCurrentMode() }
    }

    @objc private func handleMediaReset() {
        Task { @MainActor in
            let current = self.mode
            self.player = nil
            self.mode = .idle
            if current == .keepAlive { self.startKeepAlive() }
            // .ringing восстановит координатор на следующем тике.
        }
    }
}
