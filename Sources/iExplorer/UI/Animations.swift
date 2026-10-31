import AppKit
import QuartzCore

/// Trois niveaux d'animation, réglés depuis la barre d'outils : aucune, légères (fondus discrets),
/// complètes (navigation qui glisse, éléments qui apparaissent en cascade, corbeille, étincelles…).
enum AnimationMode: Int, CaseIterable {
    case none, light, full

    static let changed = Notification.Name("AnimationModeChanged")

    static var current: AnimationMode {
        get { AnimationMode(rawValue: UserDefaults.standard.object(forKey: "animationMode") as? Int ?? 1) ?? .light }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "animationMode")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    var title: String {
        switch self {
        case .none: "Sans animation"
        case .light: "Animations légères"
        case .full: "Animations complètes"
        }
    }

    var symbol: String {
        switch self {
        case .none: "sparkle"
        case .light: "sparkles"
        case .full: "wand.and.sparkles"
        }
    }

    /// Icône de la barre d'outils : grise sans animation, colorée en mode complet.
    var icon: NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        switch self {
        case .none: return image?.withSymbolConfiguration(.init(paletteColors: [.tertiaryLabelColor]))
        case .light: return image
        case .full: return image?.withSymbolConfiguration(.init(paletteColors: [.systemPurple, .systemPink]))
        }
    }

    /// Lignes insérées ou retirées (dossiers dépliés).
    var rowInsertion: NSTableView.AnimationOptions {
        switch self {
        case .none: []
        case .light: .effectFade
        case .full: .slideDown
        }
    }

    var rowRemoval: NSTableView.AnimationOptions {
        switch self {
        case .none: []
        case .light: .effectFade
        case .full: .slideUp
        }
    }
}

/// Sens d'un changement de dossier : on descend (glisse depuis la droite), on remonte, ou autre (fondu).
enum NavigationDirection {
    case forward, backward, other

    static func between(_ old: URL, _ new: URL) -> NavigationDirection {
        if new.isInside(old) { return .forward }
        if old.isInside(new) { return .backward }
        return .other
    }
}

enum Effects {
    private static var mode: AnimationMode { AnimationMode.current }

    /// Le contenu d'un panneau change de dossier.
    static func navigate(_ view: NSView, _ direction: NavigationDirection) {
        guard mode != .none else { return }
        view.wantsLayer = true
        let transition = CATransition()
        if mode == .full, direction != .other {
            transition.type = .push
            transition.subtype = direction == .forward ? .fromRight : .fromLeft
            transition.duration = 0.28
        } else {
            transition.type = .fade
            transition.duration = mode == .full ? 0.22 : 0.15
        }
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(transition, forKey: "navigation")
    }

    /// Mode complet : les éléments visibles apparaissent en cascade (léger zoom et fondu).
    static func cascade(_ views: [NSView]) {
        guard mode == .full else { return }
        for (index, view) in views.prefix(40).enumerated() {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let delay = CACurrentMediaTime() + Double(index) * 0.012
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = -6
            lift.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [fade, lift]
            group.duration = 0.24
            group.beginTime = delay
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: "cascade")
        }
    }

    /// Mode complet : les éléments partent à la corbeille (rétrécissent et s'effacent), puis `completion`.
    static func trash(_ views: [NSView], completion: @escaping () -> Void) {
        guard mode == .full, !views.isEmpty else { completion(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for view in views { view.animator().alphaValue = 0 }
        }, completionHandler: {
            completion()
            for view in views { view.alphaValue = 1 }
        })
    }

    /// Le liseré du panneau actif : fondu (léger) ou déploiement depuis le centre (complet).
    static func accent(_ view: NSView, visible: Bool) {
        guard mode != .none, let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visible ? 0 : 1
        fade.toValue = 1
        fade.duration = 0.2
        layer.add(fade, forKey: "accentFade")
        if mode == .full, visible {
            let grow = CASpringAnimation(keyPath: "transform.scale.x")
            grow.fromValue = 0.1
            grow.toValue = 1
            grow.damping = 12
            grow.duration = grow.settlingDuration
            layer.add(grow, forKey: "accentGrow")
        }
    }

    /// Mode complet : gerbe d'étincelles (opération terminée).
    static func celebrate(in view: NSView, at point: CGPoint) {
        guard mode == .full else { return }
        view.wantsLayer = true
        guard let host = view.layer else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.zPosition = 1000
        let colors: [NSColor] = [.systemPurple, .systemPink, .systemOrange, .systemYellow, .systemTeal]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = sparkle(color)
            cell.birthRate = 60
            cell.lifetime = 1.1
            cell.velocity = 180
            cell.velocityRange = 90
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 2.2
            cell.yAcceleration = -260
            cell.scale = 0.5
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.35
            cell.alphaSpeed = -0.9
            cell.spin = 2
            cell.spinRange = 4
            return cell
        }
        host.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { emitter.removeFromSuperlayer() }
    }

    private static func sparkle(_ color: NSColor) -> CGImage? {
        let size = 12
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
