import Foundation
import AVFoundation
import MediaPlayer
import Observation
import os

/// Звуки интерфейса и питомца плюс отдельная релакс-музыка.
/// Всё синтезируется в коде. Звуки интерфейса не прерывают чужое аудио (категория ambient),
/// релакс играет вместе с другими приложениями, при звонке уступает и умеет засыпать по таймеру.
@MainActor
@Observable
final class SoundService {
    static let shared = SoundService()
    private static let key = "hf.sound.v1"

    var settings: SoundSettings {
        didSet {
            persist()
            relaxRenderer.setVolume(SoundRules.gain(relaxVolume))
        }
    }

    /// Какая сцена играет сейчас (nil — релакс выключен).
    private(set) var relaxScene: AmbientScene?
    private(set) var sleepTimerEnd: Date?
    var relaxVolume: Double = 0.5 {
        didSet { relaxRenderer.setVolume(SoundRules.gain(relaxVolume)) }
    }

    private var players: [SoundEvent: AVAudioPlayer] = [:]
    private var engine: AVAudioEngine?
    private let relaxRenderer = AmbientRenderer()
    private var timerTask: Task<Void, Never>?
    private var stopToken = 0
    private var observing = false
    private var testing: Bool { TestMode.shared.data != nil }

    private init() {
        settings = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(SoundSettings.self, from: $0) } ?? SoundSettings()
        if let v = UserDefaults.standard.object(forKey: "hf.sound.relaxVolume") as? Double { relaxVolume = v }
    }

    var isRelaxing: Bool { relaxScene != nil }

    // MARK: - Короткие звуки

    func play(_ event: SoundEvent) {
        guard !testing, SoundRules.allows(event, settings) else { return }
        if !isRelaxing { configureSession(playback: false) }
        guard let player = player(for: event) else { return }
        player.volume = SoundRules.gain(settings.volume)
        player.currentTime = 0
        player.play()
    }

    private func player(for event: SoundEvent) -> AVAudioPlayer? {
        if let p = players[event] { return p }
        let samples = ToneSynth.render(ToneSynth.notes(for: event))
        let data = WAVEncoder.encode(samples, sampleRate: Int(ToneSynth.sampleRate))
        guard let p = try? AVAudioPlayer(data: data) else { return nil }
        p.prepareToPlay()
        players[event] = p
        return p
    }

    // MARK: - Релакс

    /// Включить фон. `timerMinutes` — через сколько мягко затихнуть (nil — играть, пока не выключат).
    func startRelax(_ scene: AmbientScene, timerMinutes: Int? = nil) {
        guard !testing else { return }
        stopToken += 1
        configureSession(playback: true)
        observeSystemEvents()
        relaxRenderer.configure(scene: scene, volume: SoundRules.gain(relaxVolume))

        if engine == nil { engine = makeEngine() }
        guard let engine else { return }
        if !engine.isRunning {
            do { try engine.start() } catch {
                print("Релакс не запустился: \(error)")
                relaxScene = nil
                return
            }
        }
        relaxRenderer.fadeIn()
        relaxScene = scene
        setupRemote(scene)
        setSleepTimer(minutes: timerMinutes)
    }

    func stopRelax(fade: Bool = true) {
        guard relaxScene != nil else { return }
        timerTask?.cancel()
        sleepTimerEnd = nil
        relaxScene = nil
        clearRemote()
        relaxRenderer.fadeOut(seconds: fade ? 2 : 0.1)
        stopToken += 1
        let token = stopToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(fade ? 2.3 : 0.3))
            guard let self, token == self.stopToken else { return }
            self.engine?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func toggleRelax(_ scene: AmbientScene) {
        if relaxScene == scene { stopRelax() } else { startRelax(scene, timerMinutes: nil) }
    }

    func setSleepTimer(minutes: Int?) {
        timerTask?.cancel()
        guard relaxScene != nil, let minutes, minutes > 0 else { sleepTimerEnd = nil; return }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEnd = end
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.stopRelax()
        }
    }

    // MARK: - Движок

    private func makeEngine() -> AVAudioEngine {
        let e = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let renderer = relaxRenderer
        let node = AVAudioSourceNode(format: format) { _, _, frames, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            renderer.render(frames: Int(frames), into: abl)
            return noErr
        }
        e.attach(node)
        e.connect(node, to: e.mainMixerNode, format: format)
        return e
    }

    private func configureSession(playback: Bool) {
        let s = AVAudioSession.sharedInstance()
        do {
            if playback {
                try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try s.setActive(true)
        } catch {
            print("Аудиосессия: \(error)")
        }
    }

    private func observeSystemEvents() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .ended, self.relaxScene != nil,
                   AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0).contains(.shouldResume) {
                    self.configureSession(playback: true)
                    try? self.engine?.start()
                }
            }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                // Отключили наушники — не включаем звук на весь дом.
                if let raw, AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                    self?.stopRelax(fade: false)
                }
            }
        }
    }

    // MARK: - Экран блокировки

    private func setupRemote(_ scene: AmbientScene) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRelax() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRelax() }
            return .success
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Релакс · \(scene.title)",
            MPMediaItemPropertyArtist: "HabitFlow",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    private func clearRemote() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
        UserDefaults.standard.set(relaxVolume, forKey: "hf.sound.relaxVolume")
    }
}

/// Состояние звукового потока. Живёт отдельно от главного потока и защищено блокировкой.
final class AmbientRenderer: @unchecked Sendable {
    private struct State {
        var generator = AmbientGenerator(scene: .rain)
        var fade = FadeEnvelope()
        var volume: Float = 0.3
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func configure(scene: AmbientScene, volume: Float) {
        lock.withLock { s in
            s.generator = AmbientGenerator(scene: scene)
            s.volume = volume
        }
    }

    func setVolume(_ v: Float) { lock.withLock { $0.volume = v } }
    func fadeIn() { lock.withLock { $0.fade.fadeIn(seconds: 2) } }
    func fadeOut(seconds: Float) { lock.withLock { $0.fade.fadeOut(seconds: seconds) } }

    func render(frames: Int, into abl: UnsafeMutableAudioBufferListPointer) {
        lock.withLock { s in
            for buffer in abl {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                for i in 0..<n {
                    let g = s.fade.step(sampleRate: 44_100)
                    data[i] = s.generator.next() * g * s.volume
                }
            }
        }
    }
}


/// Предлагает включить релакс-музыку сразу после отметки привычки на концентрацию или сон.
@MainActor
@Observable
final class RelaxOfferCenter {
    static let shared = RelaxOfferCenter()

    private(set) var offer: RelaxOffer?
    private var lastOffered: Date?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func consider(habitName: String) {
        guard !SoundService.shared.isRelaxing else { return }
        if let last = lastOffered, Date().timeIntervalSince(last) < 30 * 60 { return }
        guard let o = RelaxPlanner.offer(afterCompleting: habitName, strict: Appearance.shared.s.tone == .strict) else { return }
        lastOffered = .now
        offer = o
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.offer = nil
        }
    }

    func accept() {
        guard let o = offer else { return }
        SoundService.shared.startRelax(o.scene, timerMinutes: o.theme == .sleep ? 30 : nil)
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        offer = nil
    }
}
