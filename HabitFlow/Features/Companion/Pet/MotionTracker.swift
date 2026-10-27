import CoreMotion
import UIKit

/// Наклон телефона для объёма сцены (параллакс). Работает, пока сцена на экране.
/// Значения сглажены и ограничены, читаются из кадра анимации — без лишних перерисовок.
@MainActor
final class MotionTracker {
    static let shared = MotionTracker()

    /// −1…1 по горизонтали и вертикали.
    private(set) var tilt = CGPoint.zero

    private let manager = CMMotionManager()
    private var users = 0
    private var baseRoll = 0.0
    private var basePitch = 0.0
    private var hasBase = false
    private var raw = CGPoint.zero
    private var lastStep = Date()

    private init() {}

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable, Motion.enabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        hasBase = false
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            MainActor.assumeIsolated {
                let roll = data.attitude.roll, pitch = data.attitude.pitch
                if !self.hasBase { self.baseRoll = roll; self.basePitch = pitch; self.hasBase = true }
                // Нейтральное положение медленно подстраивается под то, как держат телефон (~4 с).
                self.baseRoll += (roll - self.baseRoll) * 0.008
                self.basePitch += (pitch - self.basePitch) * 0.008
                let x = max(-1, min(1, (roll - self.baseRoll) / 0.35))
                let y = max(-1, min(1, (pitch - self.basePitch) / 0.35))
                self.raw = CGPoint(x: x, y: y)
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 {
            manager.stopDeviceMotionUpdates()
            raw = .zero
        }
    }

    /// Плавное следование за датчиком; опорное положение медленно «привыкает» к тому, как держат телефон.
    func step(_ now: Date) -> CGPoint {
        let dt = min(0.1, max(0, now.timeIntervalSince(lastStep)))
        lastStep = now
        guard Motion.enabled else { tilt = .zero; return .zero }
        let k = CGFloat(1 - exp(-dt * 8))
        tilt.x += (raw.x - tilt.x) * k
        tilt.y += (raw.y - tilt.y) * k
        return tilt
    }
}
