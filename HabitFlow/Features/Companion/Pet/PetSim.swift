import SwiftUI

/// События игры с питомцем — сцена сообщает о них наружу (фразы, счётчики).
enum PetEvent: Equatable {
    case tap, tickle, petted, pickedUp, thrown, landed, fed, woke, sleep
}

/// Физика и игры одного питомца. Обычный класс без наблюдения: его шаг считается
/// в кадре анимации, поэтому изменения не вызывают лишних перерисовок.
@MainActor
final class PetSim {
    // Касание для «желе»
    var touch = CGPoint(x: 0.5, y: 0.5)   // доля от размера слоя персонажа
    var touchTime = Date.distantPast
    var touchAmp: CGFloat = 0

    // Прыжок и сальто
    var jumpStart = Date.distantPast
    var spin = false
    var tapCount = 0
    private var recentTaps: [Date] = []

    // Щекотка
    var tickleUntil = Date.distantPast

    // Перетаскивание и бросок
    enum Hold { case none, pending, holding }
    var hold: Hold = .none
    var downAt = Date.distantPast
    var downPoint = CGPoint.zero
    var moved: CGFloat = 0
    var offset = CGSize.zero            // от точки покоя
    var velocity = CGSize.zero
    var airborne = false
    var squash: CGFloat = 0             // >0 — приплюснут
    private var squashVel: CGFloat = 0
    private var lastFinger = CGPoint.zero
    private var lastFingerTime = Date()

    // Поглаживание
    var petDistance: CGFloat = 0
    struct Heart: Identifiable { let id: Int; let x: CGFloat; let y: CGFloat; let born: Date }
    struct Crumb: Identifiable { let id: Int; let x: CGFloat; let vx: CGFloat; let vy: CGFloat; let born: Date }
    var hearts: [Heart] = []
    private var heartID = 0

    // Кормление
    var feedStart = Date.distantPast
    var treatEmoji = "🍓"
    var crumbs: [Crumb] = []

    // Взгляд и поглаживание (для 3D-питомцев)
    var lookPoint = CGPoint(x: 0.5, y: 0.4)
    var lookTime = Date.distantPast
    var pettingUntil = Date.distantPast

    // Сон
    var lastInteraction = Date()
    var asleep = false
    var wakeAt = Date.distantPast

    private var lastStep = Date()
    var onEvent: ((PetEvent) -> Void)?

    // MARK: - Касания

    func poke(at p: CGPoint, strength: CGFloat = 1) {
        touch = p
        touchTime = .now
        touchAmp = strength
        look(at: p)
    }

    /// Куда смотреть: точка в долях от размера слоя персонажа.
    func look(at p: CGPoint) {
        lookPoint = p
        lookTime = .now
    }

    /// Взгляд на палец −1…1, пока касание свежее; иначе nil.
    func gazeAtFinger(_ now: Date) -> (x: Double, y: Double)? {
        guard fingerActive || now.timeIntervalSince(lookTime) < 1.4 else { return nil }
        let x = max(-1, min(1, Double(lookPoint.x - 0.5) * 2.6))
        let y = max(-1, min(1, Double(lookPoint.y - 0.38) * 2.2))
        return (x, y)
    }

    func tap(at p: CGPoint, allowSpin: Bool) {
        let now = Date.now
        interacted(now)
        recentTaps = recentTaps.filter { now.timeIntervalSince($0) < 1.3 } + [now]
        poke(at: p, strength: 1)
        if recentTaps.count >= 4 {
            // Щекотка: быстрая дрожь без прыжков
            tickleUntil = now.addingTimeInterval(1.1)
            recentTaps = []
            emit(.tickle)
            Haptics.tickle()
            return
        }
        tapCount += 1
        if !airborne && hold == .none {
            jumpStart = now
            spin = allowSpin && tapCount % 3 == 0
            Haptics.tap()
            if spin { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Haptics.soft() } }
        }
        emit(.tap)
    }

    func interacted(_ now: Date = .now) {
        lastInteraction = now
        if asleep {
            asleep = false
            wakeAt = now
            emit(.woke)
        }
    }

    // MARK: - Палец на питомце (полный режим)

    var fingerActive = false

    func fingerDown(_ p: CGPoint, charRect: CGRect) {
        // Поднять можно, только если палец лёг на самого питомца.
        hold = charRect.insetBy(dx: -10, dy: -10).contains(p) ? .pending : .none
        downAt = .now
        downPoint = p
        look(at: CGPoint(x: (p.x - charRect.minX) / max(1, charRect.width),
                         y: (p.y - charRect.minY) / max(1, charRect.height)))
        lastFinger = p
        lastFingerTime = .now
        moved = 0
        interacted()
    }

    /// Палец двигается: держим — тащим, нет — гладим.
    func fingerMoved(_ p: CGPoint, charRect: CGRect, scale: CGSize) {
        let now = Date.now
        let dx = p.x - lastFinger.x, dy = p.y - lastFinger.y
        let dt = max(0.001, now.timeIntervalSince(lastFingerTime))
        moved += hypot(dx, dy)
        lastInteraction = now
        look(at: CGPoint(x: (p.x - charRect.minX) / max(1, charRect.width),
                         y: (p.y - charRect.minY) / max(1, charRect.height)))

        switch hold {
        case .holding:
            offset.width += dx
            offset.height += dy
            // Скорость для броска — сглаженная
            velocity.width = velocity.width * 0.6 + (dx / dt) * 0.4
            velocity.height = velocity.height * 0.6 + (dy / dt) * 0.4
            squash = max(-0.18, min(0.12, -abs(velocity.height) / 6000))
        case .pending, .none:
            // Ведём пальцем по питомцу — гладим
            if charRect.insetBy(dx: -12, dy: -12).contains(p), moved > 6 {
                hold = .none
                petDistance += hypot(dx, dy)
                pettingUntil = now.addingTimeInterval(0.4)
                poke(at: CGPoint(x: (p.x - charRect.minX) / max(1, charRect.width),
                                 y: (p.y - charRect.minY) / max(1, charRect.height)), strength: 0.35)
                if petDistance > 55 {
                    petDistance = 0
                    heartID += 1
                    hearts.append(Heart(id: heartID, x: p.x, y: p.y - 10, born: now))
                    if hearts.count > 14 { hearts.removeFirst(hearts.count - 14) }
                    Haptics.purr()
                    emit(.petted)
                }
            }
        }
        lastFinger = p
        lastFingerTime = now
    }

    func fingerUp(_ p: CGPoint, charRect: CGRect, allowSpin: Bool) {
        defer { hold = .none }
        switch hold {
        case .holding:
            airborne = true
            velocity.width = max(-2200, min(2200, velocity.width))
            velocity.height = max(-2600, min(2200, velocity.height))
            emit(.thrown)
            Haptics.soft()
        case .pending:
            if moved < 10 && charRect.insetBy(dx: -16, dy: -16).contains(p) {
                tap(at: CGPoint(x: (p.x - charRect.minX) / max(1, charRect.width),
                                y: (p.y - charRect.minY) / max(1, charRect.height)), allowSpin: allowSpin)
            }
        case .none:
            break
        }
    }

    // MARK: - Кормление

    func feed(_ emoji: String) {
        treatEmoji = emoji
        feedStart = .now
        interacted()
    }

    // MARK: - Шаг физики

    /// Вызывается из кадра анимации.
    func step(_ now: Date, canHold: Bool, sleepy: Bool) {
        let dt = CGFloat(min(1.0 / 20, max(0, now.timeIntervalSince(lastStep))))
        lastStep = now

        // Удержание: палец замер на питомце — поднимаем
        if canHold && hold == .pending && moved < 8 && now.timeIntervalSince(downAt) > 0.32 {
            hold = .holding
            velocity = .zero
            emit(.pickedUp)
            DispatchQueue.main.async { Haptics.tap() }
        }

        if airborne {
            velocity.height += 2600 * dt
            offset.width += velocity.width * dt
            offset.height += velocity.height * dt
            velocity.width *= (1 - 0.6 * dt)
            // Стенки сцены
            let limitX: CGFloat = 160
            if abs(offset.width) > limitX {
                offset.width = offset.width > 0 ? limitX : -limitX
                velocity.width *= -0.5
            }
            if offset.height < -420 { offset.height = -420; velocity.height = abs(velocity.height) * 0.3 }
            // Приземление на островок
            if offset.height >= 0 && velocity.height > 0 {
                offset.height = 0
                let impact = velocity.height
                if impact > 260 {
                    velocity.height = -impact * 0.42
                    squash = min(0.22, impact / 7000)
                    squashVel = 0
                    touch = CGPoint(x: 0.5, y: 0.95)
                    touchTime = now
                    touchAmp = min(1.4, impact / 1400)
                    DispatchQueue.main.async { Haptics.land(strength: min(1, impact / 2200)) }
                } else {
                    velocity = .zero
                    airborne = false
                    emit(.landed)
                }
            }
        } else if hold != .holding {
            // Пружина возвращает на место
            let k: CGFloat = 60, damp: CGFloat = 12
            velocity.width += (-k * offset.width - damp * velocity.width) * dt
            velocity.height += (-k * offset.height - damp * velocity.height) * dt
            offset.width += velocity.width * dt
            offset.height += velocity.height * dt
            if abs(offset.width) < 0.3 && abs(offset.height) < 0.3 && hypot(velocity.width, velocity.height) < 2 {
                offset = .zero
                velocity = .zero
            }
        }

        // Сплющивание пружинит обратно
        if hold != .holding {
            let k: CGFloat = 320, damp: CGFloat = 14
            squashVel += (-k * squash - damp * squashVel) * dt
            squash += squashVel * dt
        }

        // Сердечки и крошки живут 1.4 с
        hearts.removeAll { now.timeIntervalSince($0.born) > 1.4 }
        crumbs.removeAll { now.timeIntervalSince($0.born) > 0.9 }

        // Сон: давно не трогали
        if sleepy && !asleep && now.timeIntervalSince(lastInteraction) > 45 && hold == .none && !airborne {
            asleep = true
            emit(.sleep)
        }
    }

    /// Еда: 0…1 — угощение падает, затем три «ням».
    func feedPhase(_ now: Date) -> Double? {
        let t = now.timeIntervalSince(feedStart)
        guard t >= 0 && t < 2.2 else { return nil }
        return t / 2.2
    }

    func addHeart(x: CGFloat, y: CGFloat) {
        heartID += 1
        hearts.append(Heart(id: heartID, x: x, y: y, born: .now))
    }

    func spawnCrumbs(at x: CGFloat, now: Date) {
        for i in 0..<6 {
            heartID += 1
            crumbs.append(Crumb(id: heartID, x: x, vx: CGFloat(i - 3) * 45, vy: -CGFloat(120 + i * 25), born: now))
        }
    }

    private func emit(_ e: PetEvent) {
        let cb = onEvent
        DispatchQueue.main.async { cb?(e) }
    }
}
