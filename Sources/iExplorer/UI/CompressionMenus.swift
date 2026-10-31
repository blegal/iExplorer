import AppKit

/// Couleurs des familles d'actions du menu contextuel.
enum MenuTint {
    static let open = NSColor.systemBlue
    static let compress = NSColor.systemOrange
    static let checksum = NSColor.systemGreen
    static let encrypt = NSColor.systemPurple
    static let organize = NSColor.secondaryLabelColor
    static let danger = NSColor.systemRed

    static func icon(_ symbol: String, _ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }
}

extension PanelViewController {
    private func menuItem(_ title: String, _ action: Selector?, icon: String? = nil, tint: NSColor = MenuTint.organize,
                          hint: String? = nil, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        if let icon { item.image = MenuTint.icon(icon, tint) }
        if let hint { item.badge = NSMenuItemBadge(string: hint) }
        return item
    }

    // MARK: Groupe « Transformer »

    /// Compresser / Décompresser, Somme de contrôle / Vérifier, Chiffrer / Déchiffrer : chaque entrée s'inverse
    /// quand la sélection est déjà une archive, a une somme à côté, ou est chiffrée.
    func transformMenuItems(for selection: [FileItem]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let files = selection.filter { !$0.isNavigableDirectory }

        if !selection.isEmpty, selection.allSatisfy({ FileOperationCenter.isArchive($0.url) }) {
            items.append(menuItem("Décompresser ici", #selector(extractHere(_:)), icon: "archivebox.circle", tint: MenuTint.compress))
            if !(host?.targetPanels(for: self).isEmpty ?? true) {
                items.append(menuItem("Décompresser vers l’autre panneau", #selector(extractToOtherPanel(_:)), icon: "arrow.right.circle", tint: MenuTint.compress))
            }
        } else if !selection.isEmpty {
            items.append(compressMenuItem())
        }

        if let verify = verificationTarget(for: files) {
            items.append(menuItem("Vérifier la somme de contrôle", #selector(validateChecksumFile(_:)), icon: "checkmark.seal",
                                  tint: MenuTint.checksum, hint: verify.algorithm, represented: verify.list))
        } else if !files.isEmpty {
            items.append(checksumMenuItem())
        }

        if !files.isEmpty, encryptedFiles.count == files.count, files.count == selection.count {
            let cipher = FileCipher(encryptedFile: files[0].url)
            items.append(menuItem("Déchiffrer…", #selector(decryptFiles(_:)), icon: "lock.open", tint: MenuTint.encrypt, hint: cipher?.title))
        } else if !selection.isEmpty {
            items.append(encryptMenuItem(hasFiles: !encryptableFiles.isEmpty))
        }

        if joinCandidate != nil {
            items.append(menuItem("Réassembler les morceaux…", #selector(joinFiles(_:)), icon: "square.stack.3d.up", tint: MenuTint.compress))
        } else if let candidate = splitCandidate, (candidate.size ?? 0) > 50_000_000 {
            // Découper ne sert que pour les gros fichiers : le menu reste court pour les autres (toujours dans Fichier).
            items.append(menuItem("Découper le fichier…", #selector(splitFile(_:)), icon: "scissors", tint: MenuTint.compress))
        }
        if !selection.isEmpty, selection.allSatisfy({ Volumes.isDiskImage($0.url) }) {
            items.append(menuItem("Monter l’image disque", #selector(mountDiskImages(_:)), icon: "opticaldiscdrive", tint: MenuTint.open))
        }
        return items
    }

    /// Fichier de sommes à vérifier : la sélection elle-même (.sha256…), ou celui posé à côté du fichier sélectionné.
    private func verificationTarget(for files: [FileItem]) -> (list: URL, algorithm: String)? {
        guard files.count == 1 else { return nil }
        let url = files[0].url
        let ext = url.pathExtension.lowercased()
        if Checksums.listExtensions.contains(ext) {
            return (url, ChecksumAlgorithm.allCases.first { $0.fileExtension == ext }?.rawValue ?? ext.uppercased())
        }
        return Checksums.existingSidecars(for: url).first.map { ($0.url, $0.algorithm.rawValue) }
    }

    // MARK: Compresser › format › niveau

    private func compressMenuItem() -> NSMenuItem {
        let item = menuItem("Compresser", nil, icon: "archivebox", tint: MenuTint.compress)
        let formats = NSMenu()
        for format in ArchiveFormat.menuOrder {
            let entry = NSMenuItem(title: format.fileExtension, action: nil, keyEquivalent: "")
            let levels = NSMenu()
            for level in CompressionLevel.allCases {
                let choice = menuItem(level.title, #selector(compressQuick(_:)), represented: [format.rawValue, level.rawValue])
                choice.state = format.lastLevel == level ? .on : .off
                choice.toolTip = format.levelDescription(level)
                levels.addItem(choice)
            }
            levels.addItem(.separator())
            levels.addItem(menuItem("Personnalisé…", #selector(compressCustom(_:)), represented: format.rawValue))
            entry.submenu = levels
            formats.addItem(entry)
        }
        formats.addItem(.separator())
        formats.addItem(menuItem("Personnalisé…", #selector(compressCustom(_:))))
        item.submenu = formats
        return item
    }

    @objc func compressQuick(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Int], values.count == 2,
              let format = ArchiveFormat(rawValue: values[0]), let level = CompressionLevel(rawValue: values[1]) else { return }
        compress(format: format, level: level)
    }

    /// ⌥⌘K : dernier format et dernier niveau utilisés.
    @objc func compressSelection(_ sender: Any?) {
        let format = ArchiveFormat.lastUsed
        compress(format: format, level: format.lastLevel)
    }

    private func compress(format: ArchiveFormat, level: CompressionLevel) {
        let urls = selectedURLs
        guard !urls.isEmpty, !currentURL.isRemote else { return }
        let request = CompressionRequest(urls: urls, format: format, level: level, name: CompressionRequest.defaultName(for: urls), destination: currentURL)
        FileOperationCenter.shared.compress(request, undoManager: undoManager) { [weak self] archive in
            if let archive { self?.reload(selecting: [archive]) }
        }
    }

    /// « Personnalisé… » (avec ou sans format choisi) et ⇧⌥⌘K : panneau de réglages.
    @objc func compressCustom(_ sender: Any?) {
        let format = ((sender as? NSMenuItem)?.representedObject as? Int).flatMap(ArchiveFormat.init(rawValue:))
        showCompressionPanel(format: format, password: false)
    }

    // MARK: Somme de contrôle

    private func checksumMenuItem() -> NSMenuItem {
        let item = menuItem("Somme de contrôle", nil, icon: "number.square", tint: MenuTint.checksum)
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Écrire un fichier à côté"))
        for algorithm in ChecksumAlgorithm.allCases {
            menu.addItem(menuItem(algorithm.rawValue, #selector(createChecksumFiles(_:)), hint: "." + algorithm.fileExtension,
                                  represented: algorithm.rawValue))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Afficher toutes les sommes…", #selector(showChecksums(_:))))
        menu.addItem(menuItem("Comparer avec une empreinte…", #selector(compareChecksum(_:))))
        item.submenu = menu
        return item
    }

    @objc func compareChecksum(_ sender: Any?) {
        ChecksumWindowController.show(files: selectedItems.filter { !$0.isNavigableDirectory }.map(\.url), focusComparison: true)
    }

    // MARK: Chiffrer

    private func encryptMenuItem(hasFiles: Bool) -> NSMenuItem {
        let item = menuItem("Chiffrer", nil, icon: "lock.shield", tint: MenuTint.encrypt)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "Fichier chiffré"))
        for cipher in FileCipher.allCases {
            let entry = menuItem(cipher.title + "…", #selector(encryptFiles(_:)), hint: "." + cipher.fileExtension, represented: cipher.rawValue)
            entry.isEnabled = hasFiles
            if !hasFiles { entry.toolTip = "Les dossiers se chiffrent dans une archive avec mot de passe." }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Archive avec mot de passe"))
        menu.addItem(menuItem("zip AES-256…", #selector(compressWithPassword(_:)), hint: "7-Zip, WinRAR, Keka", represented: ArchiveFormat.zip.rawValue))
        let sevenZ = menuItem("7z AES-256, noms masqués…", #selector(compressWithPassword(_:)), hint: "7-Zip", represented: ArchiveFormat.sevenZ.rawValue)
        sevenZ.isEnabled = FileOperationCenter.sevenZip != nil
        if !sevenZ.isEnabled { sevenZ.toolTip = "Installez 7-Zip : brew install sevenzip" }
        menu.addItem(sevenZ)
        item.submenu = menu
        return item
    }

    @objc func compressWithPassword(_ sender: Any?) {
        let format = ((sender as? NSMenuItem)?.representedObject as? Int).flatMap(ArchiveFormat.init(rawValue:)) ?? .zip
        showCompressionPanel(format: format, password: true)
    }

    // MARK: Panneau de réglages

    func showCompressionPanel(format: ArchiveFormat?, password: Bool) {
        let urls = selectedURLs
        guard !urls.isEmpty, !currentURL.isRemote, let window = view.window else { return }
        let panel = CompressionPanel(urls: urls, format: format ?? ArchiveFormat.lastUsed, password: password,
                                     otherPanel: host?.targetPanels(for: self).first?.currentURL, here: currentURL)
        panel.run(in: window) { [weak self] request in
            guard let self, let request else { return }
            let target = request.destination
            FileOperationCenter.shared.compress(request, undoManager: undoManager) { [weak self] archive in
                guard let self, let archive else { return }
                for panel in [self] + (host?.targetPanels(for: self) ?? []) where panel.currentURL.isSameLocation(as: target) {
                    panel.reload(selecting: [archive])
                }
            }
        }
    }
}

/// Panneau « Compresser… » : nom, format, niveau, mot de passe (zip, 7z), destination, options.
final class CompressionPanel: NSObject {
    private let urls: [URL]
    private let here: URL
    private let otherPanel: URL?
    private let name = NSTextField()
    private let extensionLabel = NSTextField(labelWithString: "")
    private let formats = NSSegmentedControl()
    private let levels = NSSegmentedControl(labels: CompressionLevel.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let levelInfo = NSTextField(labelWithString: "")
    private let usePassword = NSButton(checkboxWithTitle: "Protéger par un mot de passe (AES-256)", target: nil, action: nil)
    private let password = NSSecureTextField()
    private let confirm = NSSecureTextField()
    private let hideNames = NSButton(checkboxWithTitle: "Masquer les noms des fichiers (7z)", target: nil, action: nil)
    private let passwordInfo = NSTextField(labelWithString: "")
    private let destination = NSSegmentedControl(labels: ["Ce dossier", "Autre panneau"], trackingMode: .selectOne, target: nil, action: nil)
    private let excludeSystem = NSButton(checkboxWithTitle: "Exclure .DS_Store et fichiers système macOS", target: nil, action: nil)
    private let remember = NSButton(checkboxWithTitle: "Retenir ce format et ce niveau par défaut", target: nil, action: nil)
    private let order = ArchiveFormat.menuOrder

    init(urls: [URL], format: ArchiveFormat, password usePassword: Bool, otherPanel: URL?, here: URL) {
        self.urls = urls
        self.here = here
        self.otherPanel = otherPanel
        super.init()
        name.stringValue = CompressionRequest.defaultName(for: urls)
        formats.segmentCount = order.count
        for (index, format) in order.enumerated() { formats.setLabel(format.fileExtension, forSegment: index) }
        formats.trackingMode = .selectOne
        formats.selectedSegment = order.firstIndex(of: format) ?? 0
        levels.selectedSegment = format.lastLevel.rawValue
        self.usePassword.state = usePassword ? .on : .off
        hideNames.state = .on
        destination.selectedSegment = 0
        destination.setEnabled(otherPanel != nil, forSegment: 1)
        excludeSystem.state = .on
        remember.state = .on
        for control in [formats, levels, self.usePassword] as [NSControl] {
            control.target = self
            control.action = #selector(update)
        }
        password.placeholderString = "Mot de passe"
        confirm.placeholderString = "Confirmer"
        for label in [levelInfo, passwordInfo] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        extensionLabel.textColor = .secondaryLabelColor
        update()
    }

    private var format: ArchiveFormat { order[max(0, formats.selectedSegment)] }
    private var level: CompressionLevel { CompressionLevel(rawValue: levels.selectedSegment) ?? .normal }

    @objc private func update() {
        extensionLabel.stringValue = "." + format.fileExtension
        levelInfo.stringValue = format.levelDescription(level)
        let canEncrypt = format.supportsPassword && (format != .sevenZ || FileOperationCenter.sevenZip != nil)
        usePassword.isEnabled = canEncrypt
        if !canEncrypt { usePassword.state = .off }
        let on = usePassword.state == .on
        password.isEnabled = on
        confirm.isEnabled = on
        hideNames.isEnabled = on
        hideNames.isHidden = format != .sevenZ
        passwordInfo.stringValue = format.supportsPassword
            ? (format == .sevenZ && FileOperationCenter.sevenZip == nil ? "Le 7z chiffré demande 7-Zip (brew install sevenzip)." : "")
            : "Non disponible en .\(format.fileExtension) : choisissez zip ou 7z pour chiffrer."
        passwordInfo.isHidden = passwordInfo.stringValue.isEmpty
    }

    private func row(_ title: String, _ views: [NSView]) -> [NSView] {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return [label, stack]
    }

    func run(in window: NSWindow, completion: @escaping (CompressionRequest?) -> Void) {
        let nameLine = NSStackView(views: [name, extensionLabel])
        name.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let passwords = NSStackView(views: [password, confirm])
        password.widthAnchor.constraint(equalToConstant: 160).isActive = true
        confirm.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let grid = NSGridView(views: [
            row("Nom de l’archive", [nameLine]),
            row("Format", [formats]),
            row("Niveau", [levels, levelInfo]),
            row("Mot de passe", [usePassword, passwords, hideNames, passwordInfo]),
            row("Destination", [destination]),
            row("", [excludeSystem, remember]),
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? "Compresser « \(urls[0].lastPathComponent) »" : "Compresser \(urls.count) éléments"
        alert.accessoryView = grid
        alert.addButton(withTitle: "Compresser")
        alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = usePassword.state == .on ? password : name
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { completion(nil); return }
            let trimmed = name.stringValue.trimmingCharacters(in: .whitespaces)
            var request = CompressionRequest(urls: urls, format: format, level: level,
                                             name: trimmed.isEmpty ? CompressionRequest.defaultName(for: urls) : trimmed,
                                             destination: destination.selectedSegment == 1 ? otherPanel ?? here : here)
            request.excludeSystemFiles = excludeSystem.state == .on
            request.hideNames = hideNames.state == .on
            if usePassword.state == .on {
                guard !password.stringValue.isEmpty, password.stringValue == confirm.stringValue else {
                    FileOperationCenter.shared.showError(password.stringValue.isEmpty ? "Le mot de passe est vide." : "Les deux mots de passe ne correspondent pas.")
                    completion(nil)
                    return
                }
                request.password = password.stringValue
            }
            let previous = (ArchiveFormat.lastUsed, format.lastLevel)
            completion(request)
            // Sans « retenir », la compression ne change pas les choix par défaut.
            if remember.state == .off {
                ArchiveFormat.lastUsed = previous.0
                format.lastLevel = previous.1
            }
        }
    }
}
