import AppKit

/// Fenêtre Réglages (⌘,). Premier onglet : les outils externes, leur état et leur installation par Homebrew.
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    enum Tab: Int { case general, contextMenu, fileActions, customActions, tools, animations }

    /// Ouvre la fenêtre, sur un onglet donné si besoin ; renvoie le contrôleur de l'onglet affiché.
    @discardableResult
    static func show(tab: Tab? = nil) -> NSViewController? {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        if let tab { controller.tabs.selectedTabViewItemIndex = tab.rawValue }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller.tabs.tabViewItems[controller.tabs.selectedTabViewItemIndex].viewController
    }

    private let tabs: NSTabViewController

    private init() {
        let tabs = SettingsTabsController()
        tabs.tabStyle = .toolbar
        // Le titre de chaque onglet devient celui de la fenêtre ; l'ordre suit `Tab`.
        func add(_ controller: NSViewController, _ title: String, _ symbol: String) {
            controller.title = title
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        add(GeneralSettingsViewController(), L("Général"), "gearshape")
        add(ContextMenuSettingsViewController(), L("Menu contextuel"), "contextualmenu.and.cursorarrow")
        let fileActions = FileActionsEditorController()
        fileActions.preferredContentSize = NSSize(width: 980, height: 640)
        add(fileActions, L("Actions par type"), "doc.badge.gearshape")
        let customActions = CustomActionsController()
        customActions.showsDoneButton = false
        customActions.preferredContentSize = NSSize(width: 760, height: 420)
        add(customActions, L("Actions personnalisées"), "bolt")
        add(ExternalToolsViewController(), L("Outils externes"), "shippingbox")
        add(AnimationSettingsViewController(), L("Animations"), "wand.and.sparkles")
        let window = NSWindow(contentViewController: tabs)
        window.title = L("Réglages")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.tabs = tabs
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Onglets des Réglages : la fenêtre prend la taille de chaque onglet (les éditeurs d'actions sont bien plus grands).
private final class SettingsTabsController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let controller = tabViewItem?.viewController, let window = view.window else { return }
        let size = controller.preferredContentSize == .zero ? controller.view.fittingSize : controller.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        // Le haut de la fenêtre reste en place.
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

final class ExternalToolsViewController: NSViewController {
    static let toolsChanged = Notification.Name("ExternalToolsChanged")

    private let rows = NSStackView()
    private let log = NSTextView()
    private var installing: ExternalTool?

    override func loadView() {
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        let intro = NSTextField(wrappingLabelWithString: L("Ces outils sont facultatifs : sans eux, les fonctions concernées restent grisées. « Installer » lance Homebrew en arrière-plan ; le journal s’affiche ci-dessous."))
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)

        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        log.textColor = .secondaryLabelColor
        log.drawsBackground = false
        let logScroll = NSScrollView()
        logScroll.documentView = log
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        log.autoresizingMask = [.width]

        // Liste longue : elle défile, le journal reste visible dessous.
        let rowsScroll = NSScrollView()
        let flipped = FlippedClipContent()
        flipped.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        rowsScroll.documentView = flipped
        flipped.translatesAutoresizingMaskIntoConstraints = false
        rowsScroll.hasVerticalScroller = true
        rowsScroll.drawsBackground = false
        rowsScroll.heightAnchor.constraint(equalToConstant: 470).isActive = true
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: flipped.topAnchor),
            rows.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
            flipped.widthAnchor.constraint(equalTo: rowsScroll.contentView.widthAnchor),
        ])
        let stack = NSStackView(views: [intro, rowsScroll, logScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 660),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            rowsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        view = root
        rebuild()
    }

    private func rebuild() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Homebrew d'abord : sans lui, pas d'installation automatique.
        if let brew = ExternalTool.homebrew {
            rows.addArrangedSubview(row(installed: true, title: "Homebrew", purpose: L("Installe les outils ci-dessous"), detail: brew.path, button: nil))
        } else {
            let button = NSButton(title: L("Installer Homebrew…"), target: self, action: #selector(openHomebrewSite))
            rows.addArrangedSubview(row(installed: false, title: "Homebrew", purpose: L("Nécessaire pour installer les outils ci-dessous"), detail: "brew.sh", button: button))
        }
        for category in ExternalTool.Category.allCases {
            rows.addArrangedSubview(separator())
            rows.addArrangedSubview(sectionTitle(category.title))
            for tool in ExternalTool.allCases where tool.category == category { addRow(for: tool) }
        }
        rows.addArrangedSubview(separator())
        rows.addArrangedSubview(sectionTitle(L("Déjà intégrés")))
        for library in ExternalTool.builtIn {
            rows.addArrangedSubview(row(installed: true, title: library.title, purpose: library.purpose, detail: nil, button: nil))
        }
    }

    private func sectionTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func addRow(for tool: ExternalTool) {
            let path = tool.path
            var button: NSButton?
            if path == nil {
                let title = installing == tool ? L("Installation…") : (tool == .developerTools ? L("Installer…") : L("Installer"))
                let install = NSButton(title: title, target: self, action: #selector(install(_:)))
                install.tag = ExternalTool.allCases.firstIndex(of: tool) ?? 0
                install.isEnabled = installing == nil && (tool == .developerTools || ExternalTool.homebrew != nil)
                button = install
            }
            let package = tool.brewPackage.map { "brew install \($0.cask ? "--cask " : "")\($0.name)" } ?? "xcode-select --install"
            // Outil utile mais pas encore exploité par l'app : on le dit.
            let purpose = tool.isUsed ? tool.purpose : tool.purpose + L(" — intégration à venir")
            rows.addArrangedSubview(row(installed: path != nil, title: tool.title, purpose: purpose,
                                        detail: path?.path ?? package, button: button))
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return box
    }

    private func row(installed: Bool, title: String, purpose: String, detail: String?, button: NSButton?) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: installed ? "checkmark.circle.fill" : "circle.dashed", accessibilityDescription: installed ? L("Installé") : L("Absent"))!)
        icon.contentTintColor = installed ? .systemGreen : .tertiaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: purpose)
        text.font = .systemFont(ofSize: 11.5)
        text.textColor = .secondaryLabelColor
        var lines: [NSView] = [name, text]
        if let detail {
            let path = NSTextField(labelWithString: detail)
            path.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            path.textColor = .tertiaryLabelColor
            path.isSelectable = true
            lines.append(path)
        }
        let texts = NSStackView(views: lines)
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let line = NSStackView(views: [icon, texts] + (button.map { [NSView(), $0] } ?? []))
        line.alignment = .top
        line.spacing = 10
        line.widthAnchor.constraint(equalToConstant: 600).isActive = true
        text.preferredMaxLayoutWidth = 480
        return line
    }

    @objc private func openHomebrewSite() {
        if let url = URL(string: AppLanguage.current == "fr" ? "https://brew.sh/fr/" : "https://brew.sh/") { NSWorkspace.shared.open(url) }
    }

    @objc private func install(_ sender: NSButton) {
        let tool = ExternalTool.allCases[sender.tag]
        if tool == .developerTools {
            // Fenêtre d'installation d'Apple.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            process.arguments = ["--install"]
            try? process.run()
            append(L("xcode-select --install : suivez la fenêtre d’Apple, puis rouvrez ces réglages.\n"))
            return
        }
        guard let brew = ExternalTool.homebrew, let package = tool.brewPackage else { return }
        installing = tool
        rebuild()
        let arguments = ["install"] + (package.cask ? ["--cask"] : []) + [package.name]
        append("$ brew " + arguments.joined(separator: " ") + "\n")
        let process = Process()
        process.executableURL = brew
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = brew.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["NONINTERACTIVE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self?.append(text) }
        }
        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.append(process.terminationStatus == 0 ? L("✓ \(tool.title) installé.\n") : L("✗ L’installation a échoué (code \(process.terminationStatus)).\n"))
                self.installing = nil
                self.rebuild()
                NotificationCenter.default.post(name: Self.toolsChanged, object: nil)
            }
        }
        do { try process.run() } catch {
            append("✗ \(error.localizedDescription)\n")
            installing = nil
            rebuild()
        }
    }

    private func append(_ text: String) {
        log.textStorage?.append(NSAttributedString(string: text, attributes: [.font: log.font!, .foregroundColor: NSColor.secondaryLabelColor]))
        log.scrollToEndOfDocument(nil)
    }
}

/// Onglet Animations : le niveau choisi, puis chaque effet à cocher, rangé par niveau.
/// Onglet Général : langue de l'interface.
final class GeneralSettingsViewController: NSViewController {
    private let language = NSPopUpButton()
    private let icon = NSPopUpButton()

    override func loadView() {
        for choice in AppLanguage.allCases { language.addItem(withTitle: choice.title) }
        language.selectItem(at: AppLanguage.allCases.firstIndex(of: AppLanguage.chosen) ?? 0)
        language.target = self
        language.action = #selector(changeLanguage)
        let line = NSStackView(views: [NSTextField(labelWithString: L("Langue :")), language])
        let intro = NSTextField(wrappingLabelWithString: L("Par défaut, iExplorer suit la langue de macOS. Le changement s’applique au prochain lancement."))
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)
        for choice in AppIconChoice.allCases {
            icon.addItem(withTitle: choice.title)
            let image = choice.image?.copy() as? NSImage
            image?.size = NSSize(width: 18, height: 18)
            icon.lastItem?.image = image
        }
        icon.selectItem(at: AppIconChoice.allCases.firstIndex(of: AppIconChoice.chosen) ?? 0)
        icon.target = self
        icon.action = #selector(changeIcon)
        let iconLine = NSStackView(views: [NSTextField(labelWithString: L("Icône du Dock :")), icon])
        let iconNote = NSTextField(wrappingLabelWithString: L("L’icône choisie s’affiche dans le Dock quand iExplorer est ouvert ; le Finder garde l’icône d’origine."))
        iconNote.textColor = .secondaryLabelColor
        iconNote.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [line, intro, iconLine, iconNote])
        stack.setCustomSpacing(18, after: intro)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stack.widthAnchor.constraint(equalToConstant: 520).isActive = true
        view = stack
    }

    @objc private func changeIcon() {
        AppIconChoice.chosen = AppIconChoice.allCases[max(0, icon.indexOfSelectedItem)]
    }

    @objc private func changeLanguage() {
        let choice = AppLanguage.allCases[max(0, language.indexOfSelectedItem)]
        guard choice != AppLanguage.chosen else { return }
        AppLanguage.chosen = choice
        let alert = NSAlert()
        alert.messageText = L("Relancer iExplorer maintenant ?")
        alert.informativeText = L("La nouvelle langue s’appliquera au redémarrage.")
        alert.addButton(withTitle: L("Relancer"))
        alert.addButton(withTitle: L("Plus tard"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppLanguage.applyAtLaunch()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

final class AnimationSettingsViewController: NSViewController {
    private let mode = NSPopUpButton()
    private var boxes: [AnimationEffect: NSButton] = [:]
    private var headers: [AnimationMode: NSTextField] = [:]

    override func loadView() {
        for choice in AnimationMode.allCases { mode.addItem(withTitle: choice.title) }
        mode.selectItem(at: AnimationMode.chosen.rawValue)
        mode.target = self
        mode.action = #selector(changeAnimationLevel)
        let modeLine = NSStackView(views: [NSTextField(labelWithString: L("Niveau :")), mode])
        let intro = NSTextField(wrappingLabelWithString: L("Le niveau active tous les effets jusqu’à lui ; décochez ceux que vous ne voulez pas. Le bouton Animations de la barre d’outils change aussi le niveau."))
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)
        var views: [NSView] = [modeLine, intro]
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let warning = NSTextField(wrappingLabelWithString: L("« Réduire les animations » est activé dans les réglages d’accessibilité de macOS : aucune animation n’est jouée."))
            warning.textColor = .systemOrange
            warning.font = .systemFont(ofSize: 12)
            views.append(warning)
        }
        let disabled = AnimationEffect.disabled
        for level in [AnimationMode.light, .full, .wow] {
            let header = NSTextField(labelWithString: level.title)
            header.font = .systemFont(ofSize: 12, weight: .semibold)
            headers[level] = header
            views.append(header)
            for effect in AnimationEffect.allCases where effect.level == level {
                let box = NSButton(checkboxWithTitle: effect.title, target: self, action: #selector(toggle(_:)))
                box.state = disabled.contains(effect) ? .off : .on
                box.identifier = NSUserInterfaceItemIdentifier(effect.rawValue)
                boxes[effect] = box
                views.append(box)
            }
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        for header in headers.values { stack.setCustomSpacing(4, after: header) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 660),
            intro.widthAnchor.constraint(equalToConstant: 610),
        ])
        view = root
        NotificationCenter.default.addObserver(forName: AnimationMode.changed, object: nil, queue: .main) { [weak self] _ in
            self?.mode.selectItem(at: AnimationMode.chosen.rawValue)
            self?.updateAvailability()
        }
        updateAvailability()
    }

    /// Les effets d'un niveau supérieur au niveau choisi restent cochables, mais apparaissent grisés.
    private func updateAvailability() {
        let chosen = AnimationMode.chosen
        for (effect, box) in boxes { box.alphaValue = effect.level.rawValue <= chosen.rawValue ? 1 : 0.45 }
        for (level, header) in headers {
            header.stringValue = level.title + (level.rawValue <= chosen.rawValue ? "" : L(" — actifs à partir de ce niveau"))
            header.textColor = level.rawValue <= chosen.rawValue ? .labelColor : .tertiaryLabelColor
        }
    }

    @objc private func changeAnimationLevel() {
        AnimationMode.current = AnimationMode(rawValue: mode.indexOfSelectedItem) ?? .light
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let effect = AnimationEffect(rawValue: raw) else { return }
        var disabled = AnimationEffect.disabled
        if sender.state == .on { disabled.remove(effect) } else { disabled.insert(effect) }
        AnimationEffect.disabled = disabled
    }
}

final class FlippedClipContent: NSView {
    override var isFlipped: Bool { true }
}

extension AppDelegate {
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.show() }
}
