import AppKit

/// Éléments des Réglages façon iPadOS : pages sur fond gris, cartes arrondies, lignes avec pastille d'icône colorée.
enum SettingsUI {
    static let pageColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.11, alpha: 1) : NSColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    }
    static let cardColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.175, alpha: 1) : .white
    }

    /// Pastille carrée arrondie, symbole blanc sur couleur (comme dans Réglages sur iPhone).
    static func tile(_ symbol: String, _ color: NSColor, size: CGFloat = 26) -> NSView {
        let view = TileView(color: color)
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: size * 0.5, weight: .semibold)
        image.contentTintColor = .white
        image.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(image)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size),
            image.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    /// Titre de section au-dessus d'une carte, en petites capitales grises.
    static func caption(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return inset(label, top: 14, left: 14, bottom: 2)
    }

    /// Note sous une carte.
    static func footnote(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        return inset(label, top: 2, left: 14, bottom: 4)
    }

    private static func inset(_ view: NSView, top: CGFloat, left: CGFloat, bottom: CGFloat) -> NSView {
        let stack = NSStackView(views: [view])
        stack.edgeInsets = NSEdgeInsets(top: top, left: left, bottom: bottom, right: 14)
        return stack
    }

    /// Ligne de carte : pastille, titre (et sous-titre), puis l'accessoire à droite (interrupteur, bouton, menu…).
    static func row(_ title: String, subtitle: String? = nil, tile: NSView? = nil, accessory: NSView? = nil,
                    bold: Bool = false, indent: Bool = false) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        name.lineBreakMode = .byTruncatingTail
        var lines: [NSView] = [name]
        if let subtitle {
            let detail = NSTextField(wrappingLabelWithString: subtitle)
            detail.font = .systemFont(ofSize: 11.5)
            detail.textColor = .secondaryLabelColor
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            lines.append(detail)
        }
        let texts = NSStackView(views: lines)
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = []
        if let tile { views.append(tile) }
        views.append(texts)
        if let accessory {
            // L'accessoire est calé à droite, quelle que soit la longueur du titre.
            let spacer = NSView()
            spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            views.append(spacer)
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(accessory)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: indent ? 50 : 12, bottom: 8, right: 14)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return stack
    }

    /// Interrupteur des Réglages, relié à une action.
    static func toggle(_ isOn: Bool, target: AnyObject, action: Selector, identifier: String, label: String) -> NSSwitch {
        let control = NSSwitch()
        control.state = isOn ? .on : .off
        control.target = target
        control.action = action
        control.identifier = NSUserInterfaceItemIdentifier(identifier)
        control.setAccessibilityLabel(label)
        return control
    }

    /// Page défilante : grand titre, présentation, puis les sections, sur une colonne centrée.
    static func page(title: String, intro: String?, sections: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        var views: [NSView] = [inset(heading, top: 0, left: 2, bottom: 0)]
        if let intro {
            let text = NSTextField(wrappingLabelWithString: intro)
            text.font = .systemFont(ofSize: 12.5)
            text.textColor = .secondaryLabelColor
            views.append(inset(text, top: 2, left: 2, bottom: 6))
        }
        views += sections
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }

        let document = FlippedClipContent()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = pageColor
        let width = column.widthAnchor.constraint(equalToConstant: 620)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
            column.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 24),
            width,
        ])
        return scroll
    }
}

/// Carte arrondie : ses lignes l'une sous l'autre, séparées par un filet décalé après la pastille.
final class SettingsCard: NSView {
    private let stack = NSStackView()
    private let separatorInset: CGFloat

    /// `separatorInset` : début des filets (50 après une pastille, 12 pour des lignes sans pastille).
    init(rows: [NSView], separatorInset: CGFloat = 50) {
        self.separatorInset = separatorInset
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setRows(rows)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRows(_ rows: [NSView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            if index > 0 { stack.addArrangedSubview(SeparatorLine(inset: separatorInset)) }
            stack.addArrangedSubview(row)
        }
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    /// Masque une ligne et le filet qui la précède.
    func setRow(_ row: NSView, hidden: Bool) {
        row.isHidden = hidden
        if let index = stack.arrangedSubviews.firstIndex(of: row), index > 0 { stack.arrangedSubviews[index - 1].isHidden = hidden }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = SettingsUI.cardColor.cgColor }
}

private final class SeparatorLine: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    private let inset: CGFloat
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: inset, y: 0, width: bounds.width - inset, height: 1).fill()
    }
    init(inset: CGFloat) {
        self.inset = inset
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class TileView: NSView {
    private let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor }
}
