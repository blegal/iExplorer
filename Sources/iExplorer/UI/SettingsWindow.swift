import AppKit

/// Fenêtre Réglages (⌘,), façon Réglages d'iPadOS : barre latérale à pastilles colorées, pages en cartes.
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    enum Tab: Int, CaseIterable { case general, contextMenu, fileActions, customActions, tools, animations }

    /// Ouvre la fenêtre, sur une page donnée si besoin ; renvoie le contrôleur de la page affichée.
    @discardableResult
    static func show(tab: Tab? = nil) -> NSViewController? {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        if let tab { controller.select(tab) }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        let page = controller.tabs.tabViewItems[controller.tabs.selectedTabViewItemIndex].viewController
        return (page as? BelowTitlebar)?.content ?? page
    }

    private let tabs: SettingsTabsController
    private let sidebar: SettingsSidebarController

    private init() {
        let tabs = SettingsTabsController()
        tabs.tabStyle = .unspecified
        let pages: [(NSViewController, String, String, NSColor)] = [
            (GeneralSettingsViewController(), L("Général"), "gearshape.fill", .systemGray),
            (ContextMenuSettingsViewController(), L("Menu contextuel"), "contextualmenu.and.cursorarrow", .systemBlue),
            (BelowTitlebar(FileActionsEditorController(), size: NSSize(width: 980, height: 640)),
             L("Actions par type"), "doc.badge.gearshape.fill", .systemOrange),
            (BelowTitlebar({ let editor = CustomActionsController(); editor.showsDoneButton = false; return editor }(), size: NSSize(width: 760, height: 440)),
             L("Actions personnalisées"), "bolt.fill", .systemPurple),
            (ExternalToolsViewController(), L("Outils externes"), "shippingbox.fill", .systemBrown),
            (AnimationSettingsViewController(), L("Animations"), "wand.and.sparkles", .systemPink),
        ]
        for (controller, title, _, _) in pages {
            controller.title = title
            tabs.addTabViewItem(NSTabViewItem(viewController: controller))
        }
        let sidebar = SettingsSidebarController(entries: pages.map { ($0.1, $0.2, $0.3) })
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = SettingsSidebarController.width
        sidebarItem.maximumThickness = SettingsSidebarController.width
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: tabs))
        let window = NSWindow(contentViewController: split)
        window.title = L("Réglages")
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsSidebarController.width + 660, height: 640))
        window.contentMinSize = NSSize(width: SettingsSidebarController.width + 560, height: 440)
        self.tabs = tabs
        self.sidebar = sidebar
        super.init(window: window)
        sidebar.onSelect = { [weak self] index in self?.select(Tab(rawValue: index) ?? .general) }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func select(_ tab: Tab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
        sidebar.select(tab.rawValue)
    }
}

/// Éditeur d'actions placé sous la barre de titre transparente (les pages en cartes, elles, défilent dessous).
private final class BelowTitlebar: NSViewController {
    let content: NSViewController

    init(_ content: NSViewController, size: NSSize) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: size.width, height: size.height + 28)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
    }
}

/// Barre latérale des Réglages : une pastille colorée et un nom par page.
private final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 220
    private let entries: [(title: String, symbol: String, color: NSColor)]
    private let table = NSTableView()
    var onSelect: ((Int) -> Void)?

    init(entries: [(String, String, NSColor)]) {
        self.entries = entries.map { (title: $0.0, symbol: $0.1, color: $0.2) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page")))
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 32
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(L("Pages des réglages"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        view = scroll
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
    }

    func select(_ index: Int) {
        guard table.selectedRow != index else { return }
        table.selectRowIndexes([index], byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let label = NSTextField(labelWithString: entry.title)
        label.font = .systemFont(ofSize: 13)
        let stack = NSStackView(views: [SettingsUI.tile(entry.symbol, entry.color, size: 22), label])
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return }
        onSelect?(table.selectedRow)
    }
}

/// Pages des Réglages : la fenêtre s'agrandit pour les éditeurs d'actions, qui demandent plus de place.
private final class SettingsTabsController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let controller = tabViewItem?.viewController, let window = view.window else { return }
        let content = controller.preferredContentSize == .zero ? NSSize(width: 660, height: 640) : controller.preferredContentSize
        let size = NSSize(width: max(content.width, 560) + SettingsSidebarController.width, height: max(content.height, 440))
        // Le haut de la fenêtre reste en place ; elle ne rapetisse pas si l'utilisateur l'a agrandie.
        let current = window.contentRect(forFrameRect: window.frame).size
        let target = NSSize(width: max(size.width, current.width), height: max(size.height, current.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

final class ExternalToolsViewController: NSViewController {
    static let toolsChanged = Notification.Name("ExternalToolsChanged")

    private let container = NSView()
    private let log = NSTextView()
    private lazy var logScroll: NSScrollView = {
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        log.textColor = .secondaryLabelColor
        log.drawsBackground = false
        log.textContainerInset = NSSize(width: 8, height: 8)
        log.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = log
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        return scroll
    }()
    private var installing: ExternalTool?

    override func loadView() {
        view = container
        rebuild()
    }

    private func rebuild() {
        var sections: [NSView] = []
        // Homebrew d'abord : sans lui, pas d'installation automatique.
        let homebrew: NSView
        if let brew = ExternalTool.homebrew {
            homebrew = SettingsUI.row("Homebrew", subtitle: brew.path, tile: SettingsUI.tile("mug.fill", .systemBrown), accessory: installedBadge())
        } else {
            let button = NSButton(title: L("Installer Homebrew…"), target: self, action: #selector(openHomebrewSite))
            homebrew = SettingsUI.row("Homebrew", subtitle: L("Nécessaire pour installer les outils ci-dessous"), tile: SettingsUI.tile("mug.fill", .systemBrown), accessory: button)
        }
        sections += [SettingsUI.caption(L("Installation")), SettingsCard(rows: [homebrew])]
        for category in ExternalTool.Category.allCases {
            let rows = ExternalTool.allCases.filter { $0.category == category }.map(row(for:))
            sections += [SettingsUI.caption(category.title), SettingsCard(rows: rows)]
        }
        let builtIn = ExternalTool.builtIn.map { library in
            SettingsUI.row(library.title, subtitle: library.purpose, tile: SettingsUI.tile("checkmark.seal.fill", .systemGreen), accessory: installedBadge())
        }
        sections += [SettingsUI.caption(L("Déjà intégrés")), SettingsCard(rows: builtIn)]
        logScroll.removeFromSuperview()
        sections += [SettingsUI.caption(L("Journal d’installation")), SettingsCard(rows: [logScroll])]

        container.subviews.forEach { $0.removeFromSuperview() }
        let page = SettingsUI.page(title: L("Outils externes"),
                                   intro: L("Ces outils sont facultatifs : sans eux, les fonctions concernées restent grisées. « Installer » lance Homebrew en arrière-plan ; le journal s’affiche en bas."),
                                   sections: sections)
        page.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: container.topAnchor),
            page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    /// « ✓ Installé », en vert.
    private func installedBadge() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .systemGreen
        let label = NSTextField(labelWithString: L("Installé"))
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .systemGreen
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 4
        return stack
    }

    private func row(for tool: ExternalTool) -> NSView {
        let path = tool.path
        let accessory: NSView
        if path != nil {
            accessory = installedBadge()
        } else if installing == tool {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            let label = NSTextField(labelWithString: L("Installation…"))
            label.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [spinner, label])
            stack.spacing = 6
            accessory = stack
        } else {
            let install = NSButton(title: tool == .developerTools ? L("Installer…") : L("Installer"), target: self, action: #selector(install(_:)))
            install.bezelStyle = .push
            install.tag = ExternalTool.allCases.firstIndex(of: tool) ?? 0
            install.isEnabled = installing == nil && (tool == .developerTools || ExternalTool.homebrew != nil)
            accessory = install
        }
        let package = tool.brewPackage.map { "brew install \($0.cask ? "--cask " : "")\($0.name)" } ?? "xcode-select --install"
        // Outil utile mais pas encore exploité par l'app : on le dit.
        let purpose = (tool.isUsed ? tool.purpose : tool.purpose + L(" — intégration à venir")) + "\n" + (path?.path ?? package)
        return SettingsUI.row(tool.title, subtitle: purpose, tile: SettingsUI.tile(tool.category.symbol, tool.category.color), accessory: accessory)
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

/// Page Général : langue de l'interface et icône du Dock.
final class GeneralSettingsViewController: NSViewController {
    private let language = NSPopUpButton()
    private var iconButtons: [NSButton] = []

    override func loadView() {
        for choice in AppLanguage.allCases { language.addItem(withTitle: choice.title) }
        language.selectItem(at: AppLanguage.allCases.firstIndex(of: AppLanguage.chosen) ?? 0)
        language.target = self
        language.action = #selector(changeLanguage)
        language.setAccessibilityLabel(L("Langue de l’interface"))
        let languageCard = SettingsCard(rows: [
            SettingsUI.row(L("Langue de l’interface"), tile: SettingsUI.tile("globe", .systemBlue), accessory: language),
        ])

        // Les icônes en vignettes, la choisie entourée.
        let grid = NSStackView()
        grid.spacing = 2
        grid.alignment = .top
        for (index, choice) in AppIconChoice.allCases.enumerated() {
            let button = NSButton(title: choice.title, image: choice.image ?? NSImage(), target: self, action: #selector(changeIcon(_:)))
            button.imagePosition = .imageAbove
            button.isBordered = false
            button.font = .systemFont(ofSize: 10)
            button.tag = index
            button.imageScaling = .scaleProportionallyUpOrDown
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 84).isActive = true
            button.heightAnchor.constraint(equalToConstant: 92).isActive = true
            button.setAccessibilityLabel(choice.title)
            iconButtons.append(button)
            grid.addArrangedSubview(button)
        }
        let gridRow = NSStackView(views: [grid])
        gridRow.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        let iconCard = SettingsCard(rows: [gridRow])
        updateIconSelection()

        view = SettingsUI.page(title: L("Général"), intro: nil, sections: [
            SettingsUI.caption(L("Langue")), languageCard,
            SettingsUI.footnote(L("Par défaut, iExplorer suit la langue de macOS. Le changement s’applique au prochain lancement.")),
            SettingsUI.caption(L("Icône du Dock")), iconCard,
            SettingsUI.footnote(L("L’icône choisie s’affiche dans le Dock quand iExplorer est ouvert ; le Finder garde l’icône d’origine.")),
        ])
    }

    private func updateIconSelection() {
        let chosen = AppIconChoice.allCases.firstIndex(of: AppIconChoice.chosen) ?? 0
        for button in iconButtons {
            button.layer?.backgroundColor = button.tag == chosen ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : NSColor.clear.cgColor
            button.state = button.tag == chosen ? .on : .off
        }
    }

    @objc private func changeIcon(_ sender: NSButton) {
        AppIconChoice.chosen = AppIconChoice.allCases[sender.tag]
        updateIconSelection()
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

/// Page Animations : le niveau choisi, puis un interrupteur par effet, rangés par niveau.
final class AnimationSettingsViewController: NSViewController {
    private let mode = NSPopUpButton()
    private var switches: [AnimationEffect: NSSwitch] = [:]
    private var rows: [AnimationEffect: NSView] = [:]
    private var captions: [AnimationMode: NSTextField] = [:]

    override func loadView() {
        for choice in AnimationMode.allCases { mode.addItem(withTitle: choice.title) }
        mode.selectItem(at: AnimationMode.chosen.rawValue)
        mode.target = self
        mode.action = #selector(changeAnimationLevel)
        mode.setAccessibilityLabel(L("Niveau"))
        var sections: [NSView] = [SettingsCard(rows: [SettingsUI.row(L("Niveau"), tile: SettingsUI.tile("wand.and.sparkles", .systemPink), accessory: mode)])]
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            sections.append(SettingsUI.footnote(L("« Réduire les animations » est activé dans les réglages d’accessibilité de macOS : aucune animation n’est jouée.")))
        }
        let disabled = AnimationEffect.disabled
        for level in [AnimationMode.light, .full, .wow] {
            let caption = NSTextField(labelWithString: "")
            caption.font = .systemFont(ofSize: 11, weight: .medium)
            caption.textColor = .secondaryLabelColor
            captions[level] = caption
            let captionRow = NSStackView(views: [caption])
            captionRow.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 2, right: 14)
            var cardRows: [NSView] = []
            for effect in AnimationEffect.allCases where effect.level == level {
                let toggle = SettingsUI.toggle(!disabled.contains(effect), target: self, action: #selector(toggle(_:)), identifier: effect.rawValue, label: effect.title)
                switches[effect] = toggle
                let row = SettingsUI.row(effect.title, accessory: toggle)
                rows[effect] = row
                cardRows.append(row)
            }
            sections += [captionRow, SettingsCard(rows: cardRows, separatorInset: 12)]
        }
        view = SettingsUI.page(title: L("Animations"),
                               intro: L("Le niveau active tous les effets jusqu’à lui ; désactivez ceux que vous ne voulez pas. Le bouton Animations de la barre d’outils change aussi le niveau."),
                               sections: sections)
        NotificationCenter.default.addObserver(forName: AnimationMode.changed, object: nil, queue: .main) { [weak self] _ in
            self?.mode.selectItem(at: AnimationMode.chosen.rawValue)
            self?.updateAvailability()
        }
        updateAvailability()
    }

    /// Les effets d'un niveau supérieur au niveau choisi restent réglables, mais apparaissent estompés.
    private func updateAvailability() {
        let chosen = AnimationMode.chosen
        for (effect, row) in rows { row.alphaValue = effect.level.rawValue <= chosen.rawValue ? 1 : 0.45 }
        for (level, caption) in captions {
            caption.stringValue = (level.title + (level.rawValue <= chosen.rawValue ? "" : L(" — actifs à partir de ce niveau"))).uppercased()
        }
    }

    @objc private func changeAnimationLevel() {
        AnimationMode.current = AnimationMode(rawValue: mode.indexOfSelectedItem) ?? .light
    }

    @objc private func toggle(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let effect = AnimationEffect(rawValue: raw) else { return }
        var disabled = AnimationEffect.disabled
        if sender.state == .on { disabled.remove(effect) } else { disabled.insert(effect) }
        AnimationEffect.disabled = disabled
    }
}

extension ExternalTool.Category {
    var symbol: String {
        switch self {
        case .archives: "archivebox.fill"
        case .previews: "photo.fill"
        case .search: "magnifyingglass"
        case .crypto: "lock.fill"
        case .sync: "arrow.triangle.2.circlepath"
        case .writing: "pencil"
        case .development: "hammer.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .archives: .systemOrange
        case .previews: .systemCyan
        case .search: .systemIndigo
        case .crypto: .systemGray
        case .sync: .systemBlue
        case .writing: .systemGreen
        case .development: .systemBrown
        }
    }
}

final class FlippedClipContent: NSView {
    override var isFlipped: Bool { true }
}

extension AppDelegate {
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.show() }
}
