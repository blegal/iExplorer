import AppKit
import Darwin

/// Widgets du bas de la barre latérale : horloges, yeux, charge système, aquarium, pluie Matrix,
/// espace disque, réseau, minuteur, calendrier. Ajoutés, retirés et réordonnés par le bouton « + ».
enum SidebarWidgetKind: String, CaseIterable {
    case analogClock, digitalClock, eyes, load, aquarium, matrix, disk, network, timer, calendar

    var title: String {
        switch self {
        case .analogClock: L("Horloge analogique")
        case .digitalClock: L("Horloge numérique")
        case .eyes: L("Yeux (xeyes)")
        case .load: L("Charge processeur et mémoire (xload)")
        case .aquarium: L("Aquarium (xfish)")
        case .matrix: L("Pluie Matrix (cmatrix)")
        case .disk: L("Espace disque")
        case .network: L("Débit réseau")
        case .timer: L("Minuteur")
        case .calendar: L("Calendrier du mois")
        }
    }

    var symbol: String {
        switch self {
        case .analogClock: "clock"
        case .digitalClock: "textformat.123"
        case .eyes: "eyes"
        case .load: "cpu"
        case .aquarium: "fish"
        case .matrix: "chevron.left.forwardslash.chevron.right"
        case .disk: "internaldrive"
        case .network: "network"
        case .timer: "timer"
        case .calendar: "calendar"
        }
    }

    var height: CGFloat {
        switch self {
        case .analogClock: 120
        case .digitalClock: 56
        case .eyes: 70
        case .load: 74
        case .aquarium, .matrix: 96
        case .disk: 46
        case .network: 64
        case .timer: 92
        case .calendar: 132
        }
    }

    func makeView() -> SidebarWidget {
        switch self {
        case .analogClock: AnalogClockWidget()
        case .digitalClock: DigitalClockWidget()
        case .eyes: EyesWidget()
        case .load: LoadWidget()
        case .aquarium: AquariumWidget()
        case .matrix: MatrixWidget()
        case .disk: DiskWidget()
        case .network: NetworkWidget()
        case .timer: TimerWidget()
        case .calendar: CalendarWidget()
        }
    }

    static let changed = Notification.Name("SidebarWidgetsChanged")

    static var enabled: [SidebarWidgetKind] {
        get { (UserDefaults.standard.stringArray(forKey: "sidebarWidgets") ?? []).compactMap(SidebarWidgetKind.init(rawValue:)) }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: "sidebarWidgets")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

/// Base des widgets : un minuteur qui ne tourne que lorsque le widget est à l'écran.
class SidebarWidget: NSView {
    var kind: SidebarWidgetKind { .digitalClock }
    var interval: TimeInterval { 1 }
    private var timer: Timer?
    /// Petite croix en haut à droite, visible au survol : retire le widget.
    var onClose: (() -> Void)?
    private lazy var closeButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("Retirer le widget"))!,
                              target: self, action: #selector(closeWidget))
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = L("Retirer ce widget")
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([button.topAnchor.constraint(equalTo: topAnchor, constant: 1),
                                     button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1)])
        return button
    }()

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = onClose == nil }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    @objc private func closeWidget() { onClose?() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Mise à jour périodique (par défaut : redessiner).
    func tick() { needsDisplay = true }

    /// Entrées propres au widget, en tête de son menu contextuel.
    func extraMenuItems() -> [NSMenuItem] { [] }

    var ink: NSColor { Theme.text }
    var faint: NSColor { Theme.secondaryText }
    var accent: NSColor { Theme.accent }

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil, monospaced: Bool = false) -> NSAttributedString {
        let font = monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color ?? ink])
    }
}

// MARK: - Horloges

final class AnalogClockWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .analogClock }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height) - 12
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2
        let face = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: side, height: side))
        faint.withAlphaComponent(0.12).setFill()
        face.fill()
        faint.withAlphaComponent(0.5).setStroke()
        face.lineWidth = 1
        face.stroke()
        for mark in 0..<12 {
            let angle = CGFloat(mark) / 12 * 2 * .pi
            let inner = radius * (mark % 3 == 0 ? 0.78 : 0.86)
            let path = NSBezierPath()
            path.move(to: point(center, angle, inner))
            path.line(to: point(center, angle, radius * 0.94))
            path.lineWidth = mark % 3 == 0 ? 2 : 1
            faint.setStroke()
            path.stroke()
        }
        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: Date())
        let seconds = CGFloat(parts.second ?? 0)
        let minutes = CGFloat(parts.minute ?? 0) + seconds / 60
        let hours = CGFloat((parts.hour ?? 0) % 12) + minutes / 60
        hand(center, hours / 12, radius * 0.5, 3, ink)
        hand(center, minutes / 60, radius * 0.75, 2, ink)
        hand(center, seconds / 60, radius * 0.85, 1, .systemRed)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
    }

    /// Angle 0 en haut, sens horaire (vue retournée : y vers le bas).
    private func point(_ center: NSPoint, _ angle: CGFloat, _ length: CGFloat) -> NSPoint {
        NSPoint(x: center.x + sin(angle) * length, y: center.y - cos(angle) * length)
    }

    private func hand(_ center: NSPoint, _ fraction: CGFloat, _ length: CGFloat, _ width: CGFloat, _ color: NSColor) {
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: point(center, fraction * 2 * .pi, length))
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

final class DigitalClockWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .digitalClock }
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = AppLanguage.locale; f.setLocalizedDateFormatFromTemplate("EEEEdMMMM"); return f }()

    override func draw(_ dirtyRect: NSRect) {
        let now = Date()
        let clock = text(Self.time.string(from: now), size: 26, weight: .light, monospaced: true)
        clock.draw(at: NSPoint(x: (bounds.width - clock.size().width) / 2, y: 2))
        let date = text(Self.day.string(from: now).capitalized, size: 11, color: faint)
        date.draw(at: NSPoint(x: (bounds.width - date.size().width) / 2, y: 36))
    }
}

// MARK: - Yeux

/// Styles des yeux, choisis au clic droit.
enum EyeStyle: String, CaseIterable {
    case classic, makeup, man, woman, child, cyclops, crowd, cat, alien, robot, sleepy

    var title: String {
        switch self {
        case .classic: L("Classiques (xeyes)")
        case .makeup: L("Maquillés")
        case .man: L("Homme")
        case .woman: L("Femme")
        case .child: L("Enfant")
        case .cyclops: L("Cyclope")
        case .crowd: L("Groupe d’yeux")
        case .cat: L("Chat")
        case .alien: L("Extraterrestre")
        case .robot: L("Robot")
        case .sleepy: L("Endormis")
        }
    }

    static var current: EyeStyle {
        get { EyeStyle(rawValue: UserDefaults.standard.string(forKey: "eyesStyle") ?? "") ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "eyesStyle") }
    }
}

final class EyesWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .eyes }
    override var interval: TimeInterval { 1.0 / 30 }
    private var lastMouse = NSPoint.zero

    private struct Look {
        enum Pupil { case round, slit, led }
        var sclera = NSColor.white
        var iris: NSColor?
        var pupil = Pupil.round
        var square = false
        var lid: CGFloat = 0
        var lashes = false
        var liner = false
        var shadow: NSColor?
        var brow: CGFloat = 0
        var arched = false
        var highlight = false
        var outline: CGFloat = 2.5
    }

    override func tick() {
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse { lastMouse = mouse; needsDisplay = true }
    }

    override func extraMenuItems() -> [NSMenuItem] {
        let style = NSMenuItem(title: L("Style des yeux"), action: nil, keyEquivalent: "")
        style.image = NSImage(systemSymbolName: "eyes", accessibilityDescription: nil)
        let menu = NSMenu()
        for choice in EyeStyle.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == EyeStyle.current ? .on : .off
            menu.addItem(item)
        }
        style.submenu = menu
        return [style]
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = EyeStyle(rawValue: raw) else { return }
        EyeStyle.current = style
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window else { return }
        let mouse = convert(window.convertPoint(fromScreen: lastMouse), from: nil)
        let height = bounds.height - 12
        func pair(width: CGFloat, height: CGFloat, gap: CGFloat = 10, y: CGFloat = 8) -> [NSRect] {
            let x = (bounds.width - 2 * width - gap) / 2
            return [NSRect(x: x, y: y, width: width, height: height), NSRect(x: x + width + gap, y: y, width: width, height: height)]
        }
        switch EyeStyle.current {
        case .classic:
            pair(width: height * 0.75, height: height).forEach { eye($0, Look(), mouse) }
        case .makeup:
            let look = Look(iris: .systemBlue, lashes: true, liner: true, shadow: NSColor.systemPurple.withAlphaComponent(0.55), brow: 2, arched: true, highlight: true)
            pair(width: height * 0.95, height: height * 0.62, gap: 14, y: 20).forEach { eye($0, look, mouse) }
        case .man:
            let look = Look(iris: NSColor(calibratedRed: 0.45, green: 0.3, blue: 0.15, alpha: 1), brow: 5)
            pair(width: height * 0.95, height: height * 0.55, gap: 16, y: 22).forEach { eye($0, look, mouse) }
        case .woman:
            let look = Look(iris: NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.4, alpha: 1), lashes: true,
                            shadow: NSColor.systemPink.withAlphaComponent(0.35), brow: 1.5, arched: true, highlight: true)
            pair(width: height * 0.9, height: height * 0.6, gap: 14, y: 20).forEach { eye($0, look, mouse) }
        case .child:
            let look = Look(iris: NSColor(calibratedRed: 0.35, green: 0.65, blue: 0.95, alpha: 1), highlight: true)
            pair(width: height * 0.95, height: height * 0.95, gap: 6, y: 6).forEach { eye($0, look, mouse) }
        case .cyclops:
            let side = height
            eye(NSRect(x: (bounds.width - side * 1.25) / 2, y: 6, width: side * 1.25, height: side),
                Look(iris: .systemRed, brow: 4, highlight: true), mouse)
        case .crowd:
            // Des yeux de tailles différentes, disposés une fois pour toutes selon la largeur.
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.08, 0.15, 0.55), (0.3, 0.05, 0.85), (0.52, 0.35, 0.5), (0.66, 0.08, 0.7),
                                                         (0.86, 0.3, 0.45), (0.2, 0.6, 0.35), (0.78, 0.65, 0.3)]
            for (fx, fy, scale) in spots {
                let size = height * scale
                eye(NSRect(x: fx * (bounds.width - size), y: fy * (bounds.height - size) + 2, width: size * 0.8, height: size),
                    Look(iris: scale > 0.6 ? .systemTeal : nil, outline: 1.5), mouse)
            }
        case .cat:
            let look = Look(sclera: NSColor(calibratedRed: 0.85, green: 0.8, blue: 0.2, alpha: 1), iris: NSColor(calibratedRed: 0.55, green: 0.75, blue: 0.15, alpha: 1), pupil: .slit)
            pair(width: height * 0.85, height: height * 0.8, gap: 18, y: 10).forEach { eye($0, look, mouse) }
        case .alien:
            let look = Look(sclera: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.08, alpha: 1), iris: NSColor(calibratedRed: 0.3, green: 1, blue: 0.4, alpha: 1), highlight: true, outline: 1)
            pair(width: height * 0.7, height: height, gap: 16).forEach { eye($0, look, mouse) }
        case .robot:
            let look = Look(sclera: NSColor(calibratedWhite: 0.15, alpha: 1), iris: .systemRed, pupil: .led, square: true)
            pair(width: height * 0.9, height: height * 0.75, gap: 12, y: 12).forEach { eye($0, look, mouse) }
        case .sleepy:
            pair(width: height * 0.85, height: height * 0.8, gap: 12, y: 12).forEach { eye($0, Look(iris: NSColor(calibratedRed: 0.45, green: 0.3, blue: 0.15, alpha: 1), lid: 0.45, lashes: true), mouse) }
        }
    }

    private func eye(_ rect: NSRect, _ look: Look, _ mouse: NSPoint) {
        let shape = look.square ? NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8) : NSBezierPath(ovalIn: rect)
        if let shadow = look.shadow {
            shadow.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX - 4, y: rect.minY - rect.height * 0.35, width: rect.width + 8, height: rect.height * 0.9)).fill()
        }
        look.sclera.setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        // L'iris et la pupille suivent la souris sans sortir de l'œil.
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let dx = mouse.x - center.x, dy = mouse.y - center.y
        let distance = max(1, hypot(dx, dy))
        let pupilSize = min(rect.width, rect.height) * (look.iris == nil ? 0.32 : 0.28)
        let irisSize = look.iris == nil ? pupilSize : min(rect.width, rect.height) * 0.62
        let reachX = max(0, rect.width / 2 - irisSize / 2 - 2), reachY = max(0, rect.height / 2 - irisSize / 2 - 2)
        let scale = min(1, distance / 60)
        var at = NSPoint(x: center.x + dx / distance * reachX * scale, y: center.y + dy / distance * reachY * scale)
        // Yeux endormis : le regard reste sous la paupière.
        if look.lid > 0 { at.y = rect.minY + rect.height * (look.lid + (1 - look.lid) / 2) }
        if let iris = look.iris, look.pupil != .led {
            iris.setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - irisSize / 2, y: at.y - irisSize / 2, width: irisSize, height: irisSize)).fill()
        }
        switch look.pupil {
        case .round:
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - pupilSize / 2, y: at.y - pupilSize / 2, width: pupilSize, height: pupilSize)).fill()
        case .slit:
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - pupilSize / 5, y: at.y - irisSize / 2.2, width: pupilSize / 2.5, height: irisSize / 1.1)).fill()
        case .led:
            let glow = look.iris ?? .systemRed
            glow.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - pupilSize, y: at.y - pupilSize, width: pupilSize * 2, height: pupilSize * 2)).fill()
            glow.setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - pupilSize / 2, y: at.y - pupilSize / 2, width: pupilSize, height: pupilSize)).fill()
        }
        if look.highlight {
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x - pupilSize * 0.45, y: at.y - pupilSize * 0.55, width: pupilSize * 0.35, height: pupilSize * 0.35)).fill()
        }
        if look.lid > 0 {
            NSColor(calibratedRed: 0.93, green: 0.78, blue: 0.66, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * look.lid)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        ink.setStroke()
        shape.lineWidth = look.liner ? 3.5 : look.outline
        shape.stroke()
        if look.lid > 0 {
            let lidLine = NSBezierPath()
            lidLine.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + rect.height * look.lid))
            lidLine.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + rect.height * look.lid))
            lidLine.lineWidth = 2
            lidLine.stroke()
        }
        if look.lashes {
            // Cils sur le haut de l'œil (y vers le bas : le haut est minY).
            let top = look.lid > 0 ? rect.minY + rect.height * look.lid : rect.minY
            for index in 0..<5 {
                let t = CGFloat(index + 1) / 6
                let x = rect.minX + rect.width * t
                let base = look.lid > 0 ? top : rect.midY - sqrt(max(0, 1 - pow((x - rect.midX) / (rect.width / 2), 2))) * rect.height / 2
                let lash = NSBezierPath()
                lash.move(to: NSPoint(x: x, y: base))
                lash.line(to: NSPoint(x: x + (t - 0.5) * 6, y: look.lid > 0 ? base + 6 : base - 6))
                lash.lineWidth = 1.5
                lash.stroke()
            }
        }
        if look.brow > 0 {
            let brow = NSBezierPath()
            brow.move(to: NSPoint(x: rect.minX, y: rect.minY - 4))
            if look.arched {
                brow.curve(to: NSPoint(x: rect.maxX, y: rect.minY - 4),
                           controlPoint1: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY - 14),
                           controlPoint2: NSPoint(x: rect.minX + rect.width * 0.7, y: rect.minY - 14))
            } else {
                brow.line(to: NSPoint(x: rect.maxX, y: rect.minY - 6))
            }
            brow.lineWidth = look.brow
            brow.lineCapStyle = .round
            ink.setStroke()
            brow.stroke()
        }
    }
}

// MARK: - Charge système

final class LoadWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .load }
    private var cpuHistory: [Double] = []
    private var memoryHistory: [Double] = []
    private var previous: (busy: UInt64, total: UInt64)?

    override func tick() {
        if let cpu = Self.cpuTicks() {
            if let previous, cpu.total > previous.total {
                cpuHistory.append(Double(cpu.busy - previous.busy) / Double(cpu.total - previous.total))
            }
            previous = cpu
        }
        memoryHistory.append(Self.memoryUsage())
        let capacity = Int(bounds.width / 3)
        if cpuHistory.count > capacity { cpuHistory.removeFirst(cpuHistory.count - capacity) }
        if memoryHistory.count > capacity { memoryHistory.removeFirst(memoryHistory.count - capacity) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let graph = NSRect(x: 0, y: 18, width: bounds.width, height: bounds.height - 18)
        faint.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: graph, xRadius: 4, yRadius: 4).fill()
        draw(memoryHistory, in: graph, color: .systemTeal, filled: true)
        draw(cpuHistory, in: graph, color: .systemOrange, filled: false)
        let cpu = Int((cpuHistory.last ?? 0) * 100), memory = Int((memoryHistory.last ?? 0) * 100)
        text(L("Processeur \(cpu) %"), size: 10.5, color: .systemOrange, monospaced: true).draw(at: NSPoint(x: 2, y: 1))
        let mem = text(L("Mémoire \(memory) %"), size: 10.5, color: .systemTeal, monospaced: true)
        mem.draw(at: NSPoint(x: bounds.width - mem.size().width - 2, y: 1))
    }

    private func draw(_ values: [Double], in rect: NSRect, color: NSColor, filled: Bool) {
        guard values.count > 1 else { return }
        let step = rect.width / CGFloat(max(1, Int(rect.width / 3) - 1))
        let path = NSBezierPath()
        for (index, value) in values.enumerated() {
            let point = NSPoint(x: rect.maxX - CGFloat(values.count - 1 - index) * step, y: rect.maxY - CGFloat(value) * (rect.height - 4) - 2)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        if filled {
            let area = path.copy() as! NSBezierPath
            area.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            area.line(to: NSPoint(x: rect.maxX - CGFloat(values.count - 1) * step, y: rect.maxY))
            area.close()
            color.withAlphaComponent(0.25).setFill()
            area.fill()
        }
        color.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0), system = UInt64(ticks.1), idle = UInt64(ticks.2), nice = UInt64(ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    static func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * UInt64(vm_kernel_page_size)
        return min(1, Double(used) / Double(ProcessInfo.processInfo.physicalMemory))
    }
}

// MARK: - Aquarium

/// Styles de l'aquarium, choisis au clic droit.
enum AquariumStyle: String, CaseIterable {
    case tropical, abyss, school, koi

    var title: String {
        switch self {
        case .tropical: L("Lagon tropical")
        case .abyss: L("Abysses (méduses lumineuses)")
        case .school: L("Banc de poissons")
        case .koi: L("Bassin de carpes koï")
        }
    }

    static var current: AquariumStyle {
        get { AquariumStyle(rawValue: UserDefaults.standard.string(forKey: "aquariumStyle") ?? "") ?? .tropical }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aquariumStyle") }
    }
}

final class AquariumWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .aquarium }
    override var interval: TimeInterval { 1.0 / 30 }

    private struct Fish { var x: CGFloat; var y: CGFloat; var speed: CGFloat; var size: CGFloat; var color: NSColor; var phase: CGFloat; var spots: Bool }
    private struct Bubble { var x: CGFloat; var y: CGFloat; var radius: CGFloat }
    private struct Jelly { var x: CGFloat; var y: CGFloat; var size: CGFloat; var hue: CGFloat; var phase: CGFloat }
    private var fishes: [Fish] = []
    private var bubbles: [Bubble] = []
    private var jellies: [Jelly] = []
    private var time: CGFloat = 0
    private var populated: AquariumStyle?

    override func extraMenuItems() -> [NSMenuItem] {
        let style = NSMenuItem(title: L("Style de l’aquarium"), action: nil, keyEquivalent: "")
        style.image = NSImage(systemSymbolName: "fish", accessibilityDescription: nil)
        let menu = NSMenu()
        for choice in AquariumStyle.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == AquariumStyle.current ? .on : .off
            menu.addItem(item)
        }
        style.submenu = menu
        return [style]
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = AquariumStyle(rawValue: raw) else { return }
        AquariumStyle.current = style
        populated = nil
    }

    /// Peuple le bocal selon le style (une fois la taille du widget connue).
    private func populate(_ style: AquariumStyle) {
        let width = bounds.width, height = bounds.height
        func fish(_ size: ClosedRange<CGFloat>, _ speed: ClosedRange<CGFloat>, _ color: NSColor, flip: Bool, spots: Bool = false, y: CGFloat? = nil) -> Fish {
            Fish(x: .random(in: 0...width), y: y ?? .random(in: 14...max(15, height - 24)), speed: .random(in: speed) * (flip ? -1 : 1),
                 size: .random(in: size), color: color, phase: .random(in: 0...6), spots: spots)
        }
        jellies = []
        switch style {
        case .tropical:
            let colors: [NSColor] = [.systemOrange, .systemYellow, .systemPink, .systemTeal, .systemRed]
            fishes = (0..<5).map { fish(9...15, 0.4...1.2, colors[$0 % colors.count], flip: $0 % 2 == 1) }
        case .abyss:
            fishes = (0..<3).map { _ in fish(7...11, 0.2...0.5, NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.6, alpha: 1), flip: Bool.random(), spots: true) }
            jellies = (0..<3).map { index in
                Jelly(x: width * (0.2 + 0.3 * CGFloat(index)), y: .random(in: 20...max(21, height - 30)), size: .random(in: 10...16),
                      hue: [0.55, 0.8, 0.95][index], phase: .random(in: 0...6))
            }
        case .school:
            // Un banc qui nage ensemble, à quelques écarts près.
            let base = height * 0.45
            fishes = (0..<16).map { _ in
                var member = fish(4...6, 0.9...1.0, NSColor(calibratedWhite: 0.85, alpha: 1), flip: false, y: base + .random(in: -18...18))
                member.x = .random(in: 0...width * 0.5)
                return member
            }
        case .koi:
            let colors: [NSColor] = [.systemOrange, .white, NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.2, alpha: 1)]
            fishes = (0..<3).map { fish(16...20, 0.25...0.45, colors[$0 % colors.count], flip: $0 % 2 == 1, spots: true) }
        }
        populated = style
    }

    override func tick() {
        // Tant que le widget n'a pas sa taille (premier affichage), rien à animer.
        guard bounds.width > 40, bounds.height > 50 else { return }
        let style = AquariumStyle.current
        if populated != style { populate(style) }
        time += 0.05
        for index in fishes.indices {
            fishes[index].x += fishes[index].speed
            if fishes[index].x > bounds.width + 20 || fishes[index].x < -20 {
                if style == .school { fishes[index].x = -15 } else { fishes[index].speed *= -1 }
            }
        }
        for index in jellies.indices {
            // Les méduses montent par pulsations, puis redescendent doucement.
            jellies[index].y -= max(0, sin(time * 2 + jellies[index].phase)) * 0.6 - 0.15
            if jellies[index].y < 10 { jellies[index].y = bounds.height - 20 }
        }
        if style != .koi, Int.random(in: 0..<14) == 0 {
            bubbles.append(Bubble(x: .random(in: 8...(bounds.width - 8)), y: bounds.height - 6, radius: .random(in: 1.5...3.5)))
        }
        for index in bubbles.indices { bubbles[index].y -= 0.8; bubbles[index].x += sin(time + bubbles[index].y / 9) * 0.3 }
        bubbles.removeAll { $0.y < 4 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let style = AquariumStyle.current
        let tank = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        let colors: (NSColor, NSColor) = switch style {
        case .tropical: (NSColor(calibratedRed: 0.1, green: 0.45, blue: 0.75, alpha: 1), NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.3, alpha: 1))
        case .abyss: (NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.12, alpha: 1), NSColor(calibratedRed: 0, green: 0, blue: 0.03, alpha: 1))
        case .school: (NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.7, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.4, alpha: 1))
        case .koi: (NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.3, alpha: 1), NSColor(calibratedRed: 0.08, green: 0.2, blue: 0.15, alpha: 1))
        }
        NSGradient(starting: colors.0, ending: colors.1)?.draw(in: tank, angle: -90)
        // Les poissons qui font demi-tour au bord restent dans le bocal.
        tank.addClip()
        if style == .tropical || style == .school {
            NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.5, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 1, y: bounds.height - 9, width: bounds.width - 2, height: 8)).fill()
            for plant in stride(from: CGFloat(14), to: bounds.width, by: 46) {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: plant, y: bounds.height - 8))
                path.curve(to: NSPoint(x: plant + sin(time) * 4, y: bounds.height - 40),
                           controlPoint1: NSPoint(x: plant - 8, y: bounds.height - 20), controlPoint2: NSPoint(x: plant + 8, y: bounds.height - 30))
                path.lineWidth = 3
                NSColor.systemGreen.withAlphaComponent(0.8).setStroke()
                path.stroke()
            }
        }
        if style == .koi {
            // Nénuphars à la surface du bassin.
            for (index, x) in [0.15, 0.62, 0.88].enumerated() {
                NSColor(calibratedRed: 0.25, green: 0.6, blue: 0.25, alpha: 0.9).setFill()
                let size: CGFloat = [22, 16, 18][index]
                NSBezierPath(ovalIn: NSRect(x: bounds.width * CGFloat(x) - size / 2, y: 8 + CGFloat(index * 22), width: size, height: size * 0.7)).fill()
            }
        }
        for jelly in jellies {
            let color = NSColor(calibratedHue: jelly.hue, saturation: 0.6, brightness: 1, alpha: 0.75)
            color.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: jelly.x - jelly.size, y: jelly.y - jelly.size, width: jelly.size * 2, height: jelly.size * 2)).fill()
            color.setFill()
            let dome = NSBezierPath()
            dome.appendArc(withCenter: NSPoint(x: jelly.x, y: jelly.y), radius: jelly.size * 0.6, startAngle: 180, endAngle: 360, clockwise: false)
            dome.close()
            dome.fill()
            color.setStroke()
            for tentacle in 0..<4 {
                let path = NSBezierPath()
                let x = jelly.x - jelly.size * 0.45 + CGFloat(tentacle) * jelly.size * 0.3
                path.move(to: NSPoint(x: x, y: jelly.y))
                path.curve(to: NSPoint(x: x + sin(time * 3 + CGFloat(tentacle)) * 3, y: jelly.y + jelly.size * 1.3),
                           controlPoint1: NSPoint(x: x - 3, y: jelly.y + jelly.size * 0.5), controlPoint2: NSPoint(x: x + 3, y: jelly.y + jelly.size * 0.9))
                path.lineWidth = 1
                path.stroke()
            }
        }
        for fish in fishes {
            let direction: CGFloat = fish.speed > 0 ? 1 : -1
            let y = fish.y + sin(time * 2 + fish.phase) * 2
            fish.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: fish.x - fish.size, y: y - fish.size / 2.4, width: fish.size * 2, height: fish.size / 1.2)).fill()
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: fish.x - direction * fish.size * 0.9, y: y))
            tail.line(to: NSPoint(x: fish.x - direction * fish.size * 1.6, y: y - fish.size / 2))
            tail.line(to: NSPoint(x: fish.x - direction * fish.size * 1.6, y: y + fish.size / 2))
            tail.close()
            tail.fill()
            if fish.spots {
                // Koï : taches orangées ; abysses : lanterne lumineuse devant la tête.
                if style == .abyss {
                    NSColor(calibratedRed: 1, green: 0.95, blue: 0.5, alpha: 0.9).setFill()
                    NSBezierPath(ovalIn: NSRect(x: fish.x + direction * fish.size * 1.3 - 2, y: y - fish.size * 0.8, width: 4, height: 4)).fill()
                } else {
                    NSColor.systemRed.withAlphaComponent(0.8).setFill()
                    NSBezierPath(ovalIn: NSRect(x: fish.x - fish.size * 0.3, y: y - fish.size / 4, width: fish.size * 0.6, height: fish.size / 2.5)).fill()
                }
            }
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: fish.x + direction * fish.size * 0.5 - 1.5, y: y - 3, width: 3, height: 3)).fill()
        }
        NSColor.white.withAlphaComponent(0.6).setStroke()
        for bubble in bubbles {
            NSBezierPath(ovalIn: NSRect(x: bubble.x - bubble.radius, y: bubble.y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)).stroke()
        }
    }
}

// MARK: - Pluie Matrix

/// Styles de la pluie de caractères, choisis au clic droit.
enum MatrixStyle: String, CaseIterable {
    case green, amber, blue, rainbow, binary, red

    var title: String {
        switch self {
        case .green: L("Vert classique")
        case .amber: L("Ambre (vieux terminal)")
        case .blue: L("Bleu néon")
        case .rainbow: L("Arc-en-ciel")
        case .binary: L("Binaire (0 et 1)")
        case .red: L("Rouge alerte")
        }
    }

    static var current: MatrixStyle {
        get { MatrixStyle(rawValue: UserDefaults.standard.string(forKey: "matrixStyle") ?? "") ?? .green }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "matrixStyle") }
    }

    var glyphs: [Character] {
        self == .binary ? Array("01") : Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ0123456789ABCDEFﾊﾋﾌﾍﾎ")
    }

    /// Couleur d'une traînée (`column` sert à l'arc-en-ciel).
    func color(column: Int, fade: CGFloat) -> NSColor {
        switch self {
        case .green, .binary: NSColor(calibratedRed: 0, green: 0.9, blue: 0.3, alpha: fade)
        case .amber: NSColor(calibratedRed: 1, green: 0.7, blue: 0.1, alpha: fade)
        case .blue: NSColor(calibratedRed: 0.2, green: 0.7, blue: 1, alpha: fade)
        case .rainbow: NSColor(calibratedHue: CGFloat(column % 12) / 12, saturation: 0.8, brightness: 1, alpha: fade)
        case .red: NSColor(calibratedRed: 1, green: 0.15, blue: 0.15, alpha: fade)
        }
    }
}

final class MatrixWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .matrix }
    override var interval: TimeInterval { 1.0 / 14 }
    private var drops: [CGFloat] = []
    private var speeds: [CGFloat] = []
    private let cell: CGFloat = 11

    override func extraMenuItems() -> [NSMenuItem] {
        let style = NSMenuItem(title: L("Style de la pluie"), action: nil, keyEquivalent: "")
        style.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
        let menu = NSMenu()
        for choice in MatrixStyle.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == MatrixStyle.current ? .on : .off
            menu.addItem(item)
        }
        style.submenu = menu
        return [style]
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = MatrixStyle(rawValue: raw) else { return }
        MatrixStyle.current = style
        needsDisplay = true
    }

    override func tick() {
        let columns = Int(bounds.width / cell)
        if drops.count != columns {
            drops = (0..<columns).map { _ in .random(in: -20...0) }
            speeds = (0..<columns).map { _ in .random(in: 0.5...1.2) }
        }
        for index in drops.indices {
            drops[index] += speeds[index]
            if drops[index] * cell > bounds.height + 80 { drops[index] = .random(in: -12...0) }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let style = MatrixStyle.current
        let glyphs = style.glyphs
        let screen = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.black.setFill()
        screen.fill()
        screen.addClip()
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        for (column, head) in drops.enumerated() {
            for trail in 0..<9 {
                let row = Int(head) - trail
                guard row >= 0, CGFloat(row) * cell < bounds.height else { continue }
                let color = trail == 0 ? NSColor.white.blended(withFraction: 0.3, of: style.color(column: column, fade: 1)) ?? .white
                    : style.color(column: column, fade: 1 - CGFloat(trail) / 9)
                let glyph = String(glyphs[(column * 7 + row * 13) % glyphs.count])
                NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
                    .draw(at: NSPoint(x: CGFloat(column) * cell + 1, y: CGFloat(row) * cell))
            }
        }
    }
}

// MARK: - Espace disque, réseau

final class DiskWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .disk }
    override var interval: TimeInterval { 30 }

    override func draw(_ dirtyRect: NSRect) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey])
        let total = Double(values?.volumeTotalCapacity ?? 0)
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = total > 0 ? 1 - free / total : 0
        text(values?.volumeLocalizedName ?? L("Disque"), size: 11, weight: .semibold).draw(at: NSPoint(x: 2, y: 2))
        let free​Text = text(L("\(Format.size(Int64(free))) libres"), size: 10.5, color: faint, monospaced: true)
        free​Text.draw(at: NSPoint(x: bounds.width - free​Text.size().width - 2, y: 3))
        let bar = NSRect(x: 2, y: 24, width: bounds.width - 4, height: 10)
        faint.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
        (used > 0.9 ? NSColor.systemRed : used > 0.75 ? NSColor.systemOrange : accent).setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * used, height: bar.height), xRadius: 5, yRadius: 5).fill()
    }
}

final class NetworkWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .network }
    private var previous: (input: UInt64, output: UInt64, time: Date)?
    private var downHistory: [Double] = []
    private var upHistory: [Double] = []

    override func tick() {
        let counters = Self.counters()
        let now = Date()
        if let previous {
            let seconds = max(0.1, now.timeIntervalSince(previous.time))
            // Les compteurs 32 bits peuvent repartir de zéro : un écart négatif est ignoré.
            downHistory.append(counters.input >= previous.input ? Double(counters.input - previous.input) / seconds : 0)
            upHistory.append(counters.output >= previous.output ? Double(counters.output - previous.output) / seconds : 0)
        }
        previous = (counters.input, counters.output, now)
        let capacity = Int(bounds.width / 3)
        if downHistory.count > capacity { downHistory.removeFirst(downHistory.count - capacity) }
        if upHistory.count > capacity { upHistory.removeFirst(upHistory.count - capacity) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let graph = NSRect(x: 0, y: 18, width: bounds.width, height: bounds.height - 18)
        faint.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: graph, xRadius: 4, yRadius: 4).fill()
        let peak = max(1, (downHistory + upHistory).max() ?? 1)
        for (values, color) in [(downHistory, NSColor.systemBlue), (upHistory, NSColor.systemPink)] where values.count > 1 {
            let path = NSBezierPath()
            for (index, value) in values.enumerated() {
                let point = NSPoint(x: graph.maxX - CGFloat(values.count - 1 - index) * 3, y: graph.maxY - CGFloat(value / peak) * (graph.height - 4) - 2)
                if index == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        text("↓ \(Format.size(Int64(downHistory.last ?? 0)))/s", size: 10.5, color: .systemBlue, monospaced: true).draw(at: NSPoint(x: 2, y: 1))
        let up = text("↑ \(Format.size(Int64(upHistory.last ?? 0)))/s", size: 10.5, color: .systemPink, monospaced: true)
        up.draw(at: NSPoint(x: bounds.width - up.size().width - 2, y: 1))
    }

    static func counters() -> (input: UInt64, output: UInt64) {
        var input: UInt64 = 0, output: UInt64 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data,
                  String(cString: entry.ifa_name) != "lo0" else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            input += UInt64(stats.ifi_ibytes)
            output += UInt64(stats.ifi_obytes)
        }
        return (input, output)
    }
}

// MARK: - Minuteur, calendrier

/// Bouton rond « flat » : pastille colorée, symbole blanc.
final class FlatRoundButton: NSButton {
    var fill: NSColor = .systemRed { didSet { needsDisplay = true } }

    convenience init(symbol: String, fill: NSColor, tip: String, target: AnyObject, action: Selector) {
        self.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.fill = fill
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tip
        self.target = target
        self.action = action
        symbolConfiguration = .init(pointSize: 10, weight: .bold)
        contentTintColor = .white
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? fill.shadow(withLevel: 0.2) ?? fill : fill).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        super.draw(dirtyRect)
    }
}

final class TimerWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .timer }
    private var endDate: Date?
    private var remainingWhenPaused: TimeInterval?
    private static let durations = [5, 10, 15, 20, 25, 30, 45, 50, 60, 90]

    private var minutes: Int {
        get { UserDefaults.standard.object(forKey: "pomodoroMinutes") as? Int ?? 25 }
        set { UserDefaults.standard.set(newValue, forKey: "pomodoroMinutes") }
    }
    private var duration: TimeInterval { TimeInterval(minutes * 60) }

    private lazy var playButton = FlatRoundButton(symbol: "play.fill", fill: .systemGreen, tip: L("Démarrer"), target: self, action: #selector(toggle))
    private lazy var stopButton = FlatRoundButton(symbol: "stop.fill", fill: .systemRed, tip: L("Arrêter et remettre à zéro"), target: self, action: #selector(reset))
    private lazy var configureButton = FlatRoundButton(symbol: "gearshape.fill", fill: .systemGray, tip: L("Durée"), target: self, action: #selector(configure(_:)))
    private lazy var extendButton = FlatRoundButton(symbol: "plus", fill: .systemBlue, tip: L("Ajouter 5 minutes"), target: self, action: #selector(extend))
    /// Les quatre boutons en matrice 2 × 2, à droite de l'anneau.
    private lazy var buttons: NSGridView = {
        let grid = NSGridView(views: [[playButton, stopButton], [extendButton, configureButton]])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarWidgetKind.timer.height + 6),
                                     grid.centerYAnchor.constraint(equalTo: centerYAnchor)])
        return grid
    }()

    private var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSinceNow) }
        return remainingWhenPaused ?? duration
    }

    override func tick() {
        _ = buttons
        if endDate != nil, remaining <= 0 {
            endDate = nil
            remainingWhenPaused = nil
            updatePlayButton()
            NSSound(named: "Glass")?.play()
            NSApp.requestUserAttention(.informationalRequest)
        }
        needsDisplay = true
    }

    private func updatePlayButton() {
        let running = endDate != nil
        playButton.image = NSImage(systemSymbolName: running ? "pause.fill" : "play.fill", accessibilityDescription: running ? L("Pause") : L("Démarrer"))
        playButton.fill = running ? .systemOrange : .systemGreen
        playButton.toolTip = running ? L("Pause") : (remainingWhenPaused != nil ? L("Reprendre") : L("Démarrer"))
    }

    @objc private func toggle() {
        if endDate != nil {
            remainingWhenPaused = remaining
            endDate = nil
        } else {
            endDate = Date().addingTimeInterval(remaining > 0 ? remaining : duration)
            remainingWhenPaused = nil
        }
        updatePlayButton()
        needsDisplay = true
    }

    @objc private func reset() {
        endDate = nil
        remainingWhenPaused = nil
        updatePlayButton()
        needsDisplay = true
    }

    @objc private func extend() {
        if let endDate {
            self.endDate = endDate.addingTimeInterval(300)
        } else {
            remainingWhenPaused = remaining + 300
        }
        updatePlayButton()
        needsDisplay = true
    }

    @objc private func configure(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: L("Durée")))
        for value in Self.durations {
            let item = NSMenuItem(title: L("\(value) minutes"), action: #selector(setDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == minutes ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func setDuration(_ sender: NSMenuItem) {
        minutes = sender.tag
        reset()
    }

    override func extraMenuItems() -> [NSMenuItem] {
        let reset = NSMenuItem(title: L("Remettre à zéro"), action: #selector(reset), keyEquivalent: "")
        reset.target = self
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        return [reset]
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = bounds.height - 12
        let ring = NSRect(x: 6, y: 6, width: side, height: side)
        let center = NSPoint(x: ring.midX, y: ring.midY)
        let track = NSBezierPath(ovalIn: ring.insetBy(dx: 3, dy: 3))
        track.lineWidth = 5
        faint.withAlphaComponent(0.2).setStroke()
        track.stroke()
        let progress = max(0, 1 - remaining / duration)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: side / 2 - 3, startAngle: -90, endAngle: -90 + 360 * progress, clockwise: false)
        arc.lineWidth = 5
        arc.lineCapStyle = .round
        NSColor.systemRed.setStroke()
        arc.stroke()
        let seconds = Int(remaining.rounded(.up))
        let label = text(String(format: "%02d:%02d", seconds / 60, seconds % 60), size: 15, weight: .medium, monospaced: true)
        label.draw(at: NSPoint(x: center.x - label.size().width / 2, y: center.y - label.size().height / 2))
    }
}

final class CalendarWidget: SidebarWidget {
    override var kind: SidebarWidgetKind { .calendar }
    override var interval: TimeInterval { 300 }

    override func draw(_ dirtyRect: NSRect) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.locale
        if AppLanguage.current == "fr" { calendar.firstWeekday = 2 }
        let today = Date()
        let month = DateFormatter()
        month.locale = calendar.locale
        month.dateFormat = "LLLL yyyy"
        let title = text(month.string(from: today).capitalized, size: 11.5, weight: .semibold)
        title.draw(at: NSPoint(x: (bounds.width - title.size().width) / 2, y: 0))
        let cellWidth = bounds.width / 7
        // Initiales des jours, à partir du premier jour de la semaine de la langue (lundi en français).
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let letters = (0..<7).map { symbols[(first + $0) % 7] }
        for (index, letter) in letters.enumerated() {
            let label = text(letter, size: 9.5, weight: .medium, color: faint)
            label.draw(at: NSPoint(x: CGFloat(index) * cellWidth + (cellWidth - label.size().width) / 2, y: 18))
        }
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let days = calendar.range(of: .day, in: .month, for: start) else { return }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let current = calendar.component(.day, from: today)
        for day in days {
            let slot = offset + day - 1
            let x = CGFloat(slot % 7) * cellWidth, y = 34 + CGFloat(slot / 7) * 16
            if day == current {
                accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: x + cellWidth / 2 - 8, y: y - 1, width: 16, height: 16)).fill()
            }
            let label = text("\(day)", size: 10, weight: day == current ? .bold : .regular,
                             color: day == current ? .white : ([0, 6].contains((first + slot) % 7) ? faint : ink), monospaced: true)
            label.draw(at: NSPoint(x: x + (cellWidth - label.size().width) / 2, y: y))
        }
    }
}

// MARK: - Zone des widgets

/// Bas de la barre latérale : titre « Widgets » avec « + », puis les widgets choisis.
final class SidebarWidgetsView: NSView {
    private let stack = NSStackView()
    private let header = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: L("Widgets"))
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = Theme.secondaryText
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: L("Ajouter un widget"))!, target: self, action: #selector(showMenu(_:)))
        add.isBordered = false
        add.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        add.contentTintColor = Theme.secondaryText
        add.toolTip = L("Ajouter, retirer ou réordonner les widgets")
        header.setViews([title, NSView(), add], in: .leading)
        header.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 10, right: 10)
        let separator = NSBox()
        separator.boxType = .separator
        for view in [separator, header, stack] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            header.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: header.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        NotificationCenter.default.addObserver(forName: SidebarWidgetKind.changed, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for kind in SidebarWidgetKind.enabled {
            let widget = kind.makeView()
            widget.translatesAutoresizingMaskIntoConstraints = false
            widget.heightAnchor.constraint(equalToConstant: kind.height).isActive = true
            widget.menu = widgetMenu(for: kind, widget: widget)
            // Retiré après le clic (le bouton ne disparaît pas pendant sa propre action).
            widget.onClose = { DispatchQueue.main.async { SidebarWidgetKind.enabled = SidebarWidgetKind.enabled.filter { $0 != kind } } }
            stack.addArrangedSubview(widget)
            widget.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        }
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let enabled = SidebarWidgetKind.enabled
        for kind in SidebarWidgetKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(toggleWidget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = enabled.contains(kind) ? .on : .off
            item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func toggleWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = SidebarWidgetKind(rawValue: raw) else { return }
        var enabled = SidebarWidgetKind.enabled
        if let index = enabled.firstIndex(of: kind) { enabled.remove(at: index) } else { enabled.append(kind) }
        SidebarWidgetKind.enabled = enabled
    }

    /// Clic droit sur un widget : monter, descendre, retirer.
    private func widgetMenu(for kind: SidebarWidgetKind, widget: SidebarWidget) -> NSMenu {
        let menu = NSMenu()
        let extra = widget.extraMenuItems()
        if !extra.isEmpty {
            extra.forEach(menu.addItem)
            menu.addItem(.separator())
        }
        for (title, action, symbol) in [(L("Monter"), #selector(moveWidgetUp(_:)), "arrow.up"), (L("Descendre"), #selector(moveWidgetDown(_:)), "arrow.down"),
                                        (L("Retirer"), #selector(remove(_:)), "minus.circle")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }

    private func move(_ sender: NSMenuItem, by offset: Int) {
        guard let raw = sender.representedObject as? String, let kind = SidebarWidgetKind(rawValue: raw) else { return }
        var enabled = SidebarWidgetKind.enabled
        guard let index = enabled.firstIndex(of: kind), enabled.indices.contains(index + offset) else { return }
        enabled.swapAt(index, index + offset)
        SidebarWidgetKind.enabled = enabled
    }

    @objc private func moveWidgetUp(_ sender: NSMenuItem) { move(sender, by: -1) }
    @objc private func moveWidgetDown(_ sender: NSMenuItem) { move(sender, by: 1) }

    @objc private func remove(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = SidebarWidgetKind(rawValue: raw) else { return }
        SidebarWidgetKind.enabled = SidebarWidgetKind.enabled.filter { $0 != kind }
    }
}
