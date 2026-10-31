import AppKit
import QuartzCore

/// Trois niveaux d'animation, réglés depuis la barre d'outils : aucune, légères (fondus discrets),
/// complètes (navigation qui glisse, éléments qui apparaissent en cascade, corbeille, étincelles…).
enum AnimationMode: Int, CaseIterable {
    case none, light, full, wow

    static let changed = Notification.Name("AnimationModeChanged")

    /// Mode choisi, sauf si macOS demande de réduire les animations (accessibilité).
    static var current: AnimationMode {
        get {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .none }
            return chosen
        }
        set { chosen = newValue }
    }

    /// Complet ou Whaouh+++ : les effets du mode complet s'appliquent aussi au mode Whaouh+++.
    var isFull: Bool { rawValue >= AnimationMode.full.rawValue }

    static var chosen: AnimationMode {
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
        case .wow: "Whaouh+++"
        }
    }

    var symbol: String {
        switch self {
        case .none: "sparkle"
        case .light: "sparkles"
        case .full: "wand.and.sparkles"
        case .wow: "flame.fill"
        }
    }

    /// Icône de la barre d'outils : grise sans animation, colorée en mode complet.
    var icon: NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        switch self {
        case .none: return image?.withSymbolConfiguration(.init(paletteColors: [.tertiaryLabelColor]))
        case .light: return image
        case .full: return image?.withSymbolConfiguration(.init(paletteColors: [.systemPurple, .systemPink]))
        case .wow: return image?.withSymbolConfiguration(.init(paletteColors: [.systemOrange, .systemPink]))
        }
    }

    /// Lignes insérées ou retirées (dossiers dépliés).
    var rowInsertion: NSTableView.AnimationOptions {
        guard Effects.isOn(.rowAnimation) else { return [] }
        return switch self {
        case .none: []
        case .light: .effectFade
        case .full, .wow: .slideDown
        }
    }

    var rowRemoval: NSTableView.AnimationOptions {
        guard Effects.isOn(.rowAnimation) else { return [] }
        return switch self {
        case .none: []
        case .light: .effectFade
        case .full, .wow: .slideUp
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

/// Chaque effet, rattaché au niveau qui l'active ; on peut le couper un à un (Réglages › Animations).
enum AnimationEffect: String, CaseIterable {
    case fadeNavigation, accentFade, rowAnimation
    case pushNavigation, cascade, trashFade, accentSpring, sparkles
    case portal, spiral, hoverGlow, selectionRipple, iconPop, panelDim, flyingFiles, dropParticles
    case crumple, typewriter, stamps, fireworks, themeWave, sidebarBounce

    var level: AnimationMode {
        switch self {
        case .fadeNavigation, .accentFade, .rowAnimation: .light
        case .pushNavigation, .cascade, .trashFade, .accentSpring, .sparkles: .full
        default: .wow
        }
    }

    var title: String {
        switch self {
        case .fadeNavigation: "Fondu au changement de dossier ou d’onglet"
        case .accentFade: "Liseré du panneau actif en fondu"
        case .rowAnimation: "Dossiers dépliés animés"
        case .pushNavigation: "Le contenu glisse quand on descend ou remonte"
        case .cascade: "Les éléments apparaissent en cascade"
        case .trashFade: "Les fichiers s’effacent avant la corbeille"
        case .accentSpring: "Le liseré du panneau actif se déploie avec un rebond"
        case .sparkles: "Étincelles quand une opération se termine"
        case .portal: "Effet portail : on plonge dans le dossier ouvert"
        case .spiral: "Les icônes du dossier ouvert apparaissent en spirale"
        case .hoverGlow: "Halo et icône qui grossit au survol"
        case .selectionRipple: "Onde lumineuse au clic"
        case .iconPop: "« Pop » des icônes sélectionnées et créées"
        case .panelDim: "Panneau inactif légèrement estompé"
        case .flyingFiles: "Les fichiers volent vers l’autre panneau (F5, F6)"
        case .dropParticles: "Particules au dépôt d’un glisser-déposer"
        case .crumple: "Fichiers froissés qui tombent à la corbeille"
        case .typewriter: "Nouveau nom écrit lettre par lettre"
        case .stamps: "Cadenas qui apparaît au chiffrement"
        case .fireworks: "Feu d’artifice après une opération de plus de 30 s"
        case .themeWave: "Nouveau thème en vague circulaire"
        case .sidebarBounce: "Icônes de la barre latérale qui rebondissent au survol"
        }
    }

    static let changed = Notification.Name("AnimationEffectsChanged")

    static var disabled: Set<AnimationEffect> {
        get { Set((UserDefaults.standard.stringArray(forKey: "disabledAnimationEffects") ?? []).compactMap(AnimationEffect.init(rawValue:))) }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: "disabledAnimationEffects")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

enum Effects {
    private static var mode: AnimationMode { AnimationMode.current }

    /// L'effet est-il actif ? (niveau atteint par le mode choisi, et non décoché)
    static func isOn(_ effect: AnimationEffect) -> Bool {
        mode.rawValue >= effect.level.rawValue && !AnimationEffect.disabled.contains(effect)
    }

    /// Le contenu d'un panneau change de dossier.
    static func navigate(_ view: NSView, _ direction: NavigationDirection) {
        guard isOn(.fadeNavigation) || isOn(.pushNavigation) || isOn(.portal) else { return }
        view.wantsLayer = true
        let transition = CATransition()
        if isOn(.portal), direction != .other, let layer = view.layer {
            // Effet portail : on plonge dans le dossier (ou on en ressort).
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = direction == .forward ? 0.72 : 1.3
            zoom.toValue = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [zoom, fade]
            group.duration = 0.34
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
            centerAnchor(layer)
            layer.add(group, forKey: "portal")
            return
        }
        if isOn(.pushNavigation), direction != .other {
            transition.type = .push
            transition.subtype = direction == .forward ? .fromRight : .fromLeft
            transition.duration = 0.28
        } else {
            guard isOn(.fadeNavigation) else { return }
            transition.type = .fade
            transition.duration = mode.isFull ? 0.22 : 0.15
        }
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(transition, forKey: "navigation")
    }

    /// Mode complet : les éléments visibles apparaissent en cascade (léger zoom et fondu).
    static func cascade(_ views: [NSView]) {
        guard isOn(.cascade) else { return }
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
        guard !views.isEmpty, isOn(.crumple) || isOn(.trashFade) else { completion(); return }
        if isOn(.crumple) {
            crumple(views, completion: completion)
            return
        }
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
        guard let layer = view.layer else { return }
        if isOn(.accentFade) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = visible ? 0 : 1
            fade.toValue = 1
            fade.duration = 0.2
            layer.add(fade, forKey: "accentFade")
        }
        if isOn(.accentSpring), visible {
            let grow = CASpringAnimation(keyPath: "transform.scale.x")
            grow.fromValue = 0.1
            grow.toValue = 1
            grow.damping = 12
            grow.duration = grow.settlingDuration
            layer.add(grow, forKey: "accentGrow")
        }
    }

    /// Mode complet : gerbe d'étincelles (opération terminée).
    static func celebrate(in view: NSView, at point: CGPoint, colors: [NSColor]? = nil, amount: Float = 60) {
        guard mode != .none else { return }
        view.wantsLayer = true
        guard let host = view.layer else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.zPosition = 1000
        let palette = colors ?? [.systemPurple, .systemPink, .systemOrange, .systemYellow, .systemTeal]
        emitter.emitterCells = palette.map { color in
            let cell = CAEmitterCell()
            cell.contents = sparkle(color)
            cell.birthRate = amount
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

    // MARK: Whaouh+++

    /// Ancre au centre (les vues AppKit ont leur ancre en bas à gauche).
    static func centerAnchor(_ layer: CALayer) {
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Survol d'une ligne : halo doux et icône qui grossit avec un rebond.
    static func hover(_ row: NSView?, icon: NSView?, previous: NSView?, previousIcon: NSView?) {
        if let previous {
            previous.layer?.sublayers?.filter { $0.name == "wowGlow" }.forEach { glow in
                CATransaction.begin()
                CATransaction.setCompletionBlock { glow.removeFromSuperlayer() }
                glow.opacity = 0
                CATransaction.commit()
            }
        }
        previousIcon?.layer?.removeAnimation(forKey: "hoverGrow")
        previousIcon?.layer?.transform = CATransform3DIdentity
        guard isOn(.hoverGlow), let row else { return }
        row.wantsLayer = true
        if let layer = row.layer, layer.sublayers?.contains(where: { $0.name == "wowGlow" }) != true {
            let glow = CALayer()
            glow.name = "wowGlow"
            glow.frame = row.bounds.insetBy(dx: 4, dy: 1)
            glow.cornerRadius = 6
            glow.backgroundColor = Theme.accent.withAlphaComponent(0.14).cgColor
            glow.shadowColor = Theme.accent.cgColor
            glow.shadowRadius = 8
            glow.shadowOpacity = 0.5
            glow.shadowOffset = .zero
            glow.opacity = 0
            layer.insertSublayer(glow, at: 0)
            glow.opacity = 1
        }
        if let icon {
            icon.wantsLayer = true
            guard let layer = icon.layer else { return }
            centerAnchor(layer)
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 1.12
            grow.damping = 9
            grow.duration = grow.settlingDuration
            grow.fillMode = .forwards
            grow.isRemovedOnCompletion = false
            layer.add(grow, forKey: "hoverGrow")
        }
    }

    /// Sélection : onde lumineuse qui part du point cliqué.
    static func ripple(in view: NSView, at point: CGPoint) {
        guard isOn(.selectionRipple) else { return }
        view.wantsLayer = true
        guard let host = view.layer else { return }
        let ring = CAShapeLayer()
        let radius: CGFloat = 60
        ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        ring.position = point
        ring.fillColor = Theme.accent.withAlphaComponent(0.25).cgColor
        ring.strokeColor = Theme.accent.cgColor
        ring.lineWidth = 1.5
        host.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.05
        grow.toValue = 1.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ring.removeFromSuperlayer() }
    }

    /// Petit « pop » élastique (icône sélectionnée, élément créé).
    static func pop(_ view: NSView?, delay: TimeInterval = 0, from scale: CGFloat = 0.75, axis: String = "transform.scale",
                    effect: AnimationEffect = .iconPop) {
        guard isOn(effect), let view else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        centerAnchor(layer)
        let spring = CASpringAnimation(keyPath: axis)
        spring.fromValue = scale
        spring.toValue = 1
        spring.damping = 8
        spring.initialVelocity = 4
        spring.duration = spring.settlingDuration
        spring.beginTime = CACurrentMediaTime() + delay
        spring.fillMode = .backwards
        layer.add(spring, forKey: "pop")
    }

    /// Panneau inactif légèrement estompé.
    static func dim(_ view: NSView, active: Bool) {
        let target: CGFloat = isOn(.panelDim) && !active ? 0.86 : 1
        guard abs(view.alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            view.animator().alphaValue = target
        }
    }

    /// Des icônes « volent » d'un panneau à l'autre (copie, déplacement).
    static func fly(_ images: [NSImage], from start: CGRect, to end: CGPoint, in window: NSWindow?) {
        guard isOn(.flyingFiles), let content = window?.contentView else { return }
        content.wantsLayer = true
        guard let host = content.layer else { return }
        for (index, image) in images.prefix(6).enumerated() {
            let layer = CALayer()
            layer.contents = image
            layer.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
            let origin = CGPoint(x: start.midX + CGFloat(index) * 6, y: start.midY - CGFloat(index) * 4)
            layer.position = end
            layer.zPosition = 1000
            layer.opacity = 0
            host.addSublayer(layer)
            let path = CGMutablePath()
            path.move(to: origin)
            path.addQuadCurve(to: end, control: CGPoint(x: (origin.x + end.x) / 2, y: max(origin.y, end.y) + 120))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let spin = CABasicAnimation(keyPath: "transform.rotation")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            let shrink = CAKeyframeAnimation(keyPath: "opacity")
            shrink.values = [0, 1, 1, 0]
            shrink.keyTimes = [0, 0.1, 0.8, 1]
            let group = CAAnimationGroup()
            group.animations = [move, spin, shrink]
            group.duration = 0.75
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.06
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(group, forKey: "fly")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { layer.removeFromSuperlayer() }
        }
    }

    /// Corbeille : les lignes se froissent (rétrécissent en tournant) et tombent.
    private static func crumple(_ views: [NSView], completion: @escaping () -> Void) {
        for (index, view) in views.enumerated() {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            centerAnchor(layer)
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.toValue = 0.08
            let spin = CABasicAnimation(keyPath: "transform.rotation")
            spin.toValue = CGFloat.pi * (index % 2 == 0 ? 1.5 : -1.5)
            let fall = CABasicAnimation(keyPath: "transform.translation.y")
            fall.toValue = view.isFlipped ? 60 : -60
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [shrink, spin, fall, fade]
            group.duration = 0.42
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.04
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "crumple")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + Double(min(views.count, 10)) * 0.04) {
            completion()
            views.forEach { $0.layer?.removeAnimation(forKey: "crumple") }
        }
    }

    /// Le nouveau nom s'écrit lettre par lettre.
    static func typewriter(_ field: NSTextField?) {
        guard isOn(.typewriter), let field else { return }
        let full = field.stringValue
        let characters = Array(full)
        guard characters.count > 1 else { return }
        field.stringValue = ""
        var index = 0
        Timer.scheduledTimer(withTimeInterval: min(0.04, 0.6 / Double(characters.count)), repeats: true) { timer in
            index += 1
            field.stringValue = String(characters.prefix(index))
            if index >= characters.count { timer.invalidate(); field.stringValue = full }
        }
    }

    /// Symbole qui apparaît brièvement sur une ligne (cadenas après chiffrement…).
    static func stamp(_ symbol: String, color: NSColor, on view: NSView?) {
        guard isOn(.stamps), let view, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .bold).applying(.init(paletteColors: [color]))) else { return }
        view.wantsLayer = true
        guard let host = view.layer else { return }
        let layer = CALayer()
        layer.contents = image
        layer.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        layer.position = CGPoint(x: view.bounds.maxX - 30, y: view.bounds.midY)
        layer.zPosition = 100
        host.addSublayer(layer)
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 2.5
        pop.toValue = 1
        pop.damping = 7
        pop.duration = pop.settlingDuration
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.1, 0.75, 1]
        fade.duration = 1.4
        layer.add(pop, forKey: "pop")
        layer.add(fade, forKey: "fade")
        layer.opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { layer.removeFromSuperlayer() }
    }

    /// Opération longue terminée : feu d'artifice en plusieurs gerbes.
    static func fireworks(in view: NSView) {
        guard isOn(.fireworks) else { return }
        for burst in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(burst) * 0.25) {
                let point = CGPoint(x: .random(in: view.bounds.width * 0.2...view.bounds.width * 0.8),
                                    y: .random(in: view.bounds.height * 0.3...view.bounds.height * 0.8))
                celebrate(in: view, at: point, amount: 90)
            }
        }
    }

    /// Changement de thème : le nouveau se propage en vague circulaire depuis `origin`.
    static func themeWave(in window: NSWindow?, from origin: CGPoint, apply: () -> Void) {
        guard isOn(.themeWave), let window, let content = window.contentView?.superview ?? window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { apply(); return }
        content.cacheDisplay(in: content.bounds, to: rep)
        let snapshot = NSImage(size: content.bounds.size)
        snapshot.addRepresentation(rep)
        apply()
        content.wantsLayer = true
        guard let host = content.layer else { return }
        let old = CALayer()
        old.frame = content.bounds
        old.contents = snapshot
        old.zPosition = 2000
        host.addSublayer(old)
        // Le masque laisse voir l'ancien thème hors du cercle, qui grandit jusqu'à tout couvrir.
        let radius = hypot(content.bounds.width, content.bounds.height)
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        func path(_ r: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.addRect(content.bounds.insetBy(dx: -10, dy: -10))
            p.addEllipse(in: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
            return p
        }
        mask.path = path(radius)
        old.mask = mask
        let wave = CABasicAnimation(keyPath: "path")
        wave.fromValue = path(1)
        wave.toValue = path(radius)
        wave.duration = 0.7
        wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mask.add(wave, forKey: "wave")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { old.removeFromSuperlayer() }
    }

    /// Petit rebond (icônes de la barre latérale au survol).
    static func bounce(_ view: NSView?) {
        guard isOn(.sidebarBounce), let view else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        centerAnchor(layer)
        let jump = CASpringAnimation(keyPath: "transform.translation.y")
        jump.fromValue = view.isFlipped ? -5 : 5
        jump.toValue = 0
        jump.damping = 6
        jump.duration = jump.settlingDuration
        layer.add(jump, forKey: "bounce")
    }
}
