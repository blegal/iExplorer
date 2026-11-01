import AppKit

/// Groupes du menu contextuel, dans l'ordre du menu (celui du Finder), masquables en entier ;
/// un groupe affiché laisse choisir ses éléments un à un.
/// Masquer une entrée ne retire que le menu contextuel : la barre de menus et les raccourcis restent.
enum ContextMenuGroup: String, CaseIterable {
    case palette, open, organize, fileActions, transform, share, create, trash, view

    var title: String {
        switch self {
        case .palette: L("Barre d’actions rapides")
        case .fileActions: L("Actions")
        case .open: L("Ouvrir")
        case .transform: L("Transformer")
        case .organize: L("Organiser")
        case .share: L("Partager et tags")
        case .create: L("Créer")
        case .trash: L("Corbeille")
        case .view: L("Présentation")
        }
    }

    var entries: [ContextMenuEntry] { ContextMenuEntry.allCases.filter { $0.group == self } }

    private static let hiddenKey = "contextMenuHiddenGroups"

    var isShown: Bool {
        get { !(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).contains(rawValue) }
        nonmutating set { ContextMenuEntry.toggle(rawValue, shown: newValue, key: Self.hiddenKey) }
    }
}

enum ContextMenuEntry: String, CaseIterable {
    case quickActions, tagDots
    case open, openWith, openInNewTab, packageContents
    case newFolderWithSelection, copyMoveTo, links, copyPath
    case fileTypeActions, customActions
    case compress, checksum, encrypt, split
    case tags, share
    case newFolder, newDocument, terminal, diskUsage
    case trash
    case flatView, grouping

    var group: ContextMenuGroup {
        switch self {
        case .quickActions, .tagDots: .palette
        case .fileTypeActions, .customActions: .fileActions
        case .open, .openWith, .openInNewTab, .packageContents: .open
        case .compress, .checksum, .encrypt, .split: .transform
        case .newFolderWithSelection, .copyMoveTo, .links, .copyPath: .organize
        case .tags, .share: .share
        case .newFolder, .newDocument, .terminal, .diskUsage: .create
        case .trash: .trash
        case .flatView, .grouping: .view
        }
    }

    var title: String {
        switch self {
        case .quickActions: L("Icônes d’actions courantes")
        case .tagDots: L("Pastilles de tags")
        case .fileTypeActions: L("Actions par type de fichier (make, latexmk, typst…)")
        case .open: L("Ouvrir")
        case .openWith: L("Ouvrir avec")
        case .openInNewTab: L("Ouvrir dans un nouvel onglet")
        case .packageContents: L("Afficher le contenu du paquet")
        case .compress: L("Compresser / Décompresser")
        case .checksum: L("Somme de contrôle / Vérifier")
        case .encrypt: L("Chiffrer / Déchiffrer")
        case .split: L("Découper / Réassembler")
        case .newFolderWithSelection: L("Nouveau dossier avec la sélection")
        case .copyMoveTo: L("Copier vers / Déplacer vers")
        case .links: L("Créer un lien")
        case .copyPath: L("Copier le chemin")
        case .tags: L("Tags")
        case .customActions: L("Actions personnalisées")
        case .share: L("Partager")
        case .newFolder: L("Nouveau dossier")
        case .newDocument: L("Nouveau document")
        case .terminal: L("Ouvrir dans le Terminal")
        case .diskUsage: L("Occupation du disque")
        case .trash: L("Placer dans la corbeille")
        case .flatView: L("Vue à plat")
        case .grouping: L("Regroupement")
        }
    }

    private static let hiddenKey = "contextMenuHiddenEntries"

    /// Coché pour lui-même (indépendamment de son groupe).
    var isChecked: Bool {
        get { !(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).contains(rawValue) }
        nonmutating set { Self.toggle(rawValue, shown: newValue, key: Self.hiddenKey) }
    }

    /// Affiché dans le menu : son groupe et lui-même sont cochés.
    var isShown: Bool { group.isShown && isChecked }

    fileprivate static func toggle(_ id: String, shown: Bool, key: String) {
        var hidden = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if shown { hidden.remove(id) } else { hidden.insert(id) }
        UserDefaults.standard.set(hidden.sorted(), forKey: key)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: "contextMenuHiddenGroups")
    }
}

/// Page « Menu contextuel » des Réglages : une carte par groupe, son interrupteur en tête,
/// puis un interrupteur par élément (cachés quand le groupe est masqué).
final class ContextMenuSettingsViewController: NSViewController {
    private var groupSwitches: [ContextMenuGroup: NSSwitch] = [:]
    private var entrySwitches: [ContextMenuEntry: NSSwitch] = [:]
    private var entryRows: [ContextMenuEntry: NSView] = [:]
    private var cards: [ContextMenuGroup: SettingsCard] = [:]
    private var groupStatus: [ContextMenuGroup: NSTextField] = [:]

    override func loadView() {
        var sections: [NSView] = []
        for group in ContextMenuGroup.allCases {
            let groupSwitch = SettingsUI.toggle(group.isShown, target: self, action: #selector(toggleGroup(_:)), identifier: group.rawValue, label: group.title)
            groupSwitches[group] = groupSwitch
            let status = NSTextField(labelWithString: "")
            status.textColor = .secondaryLabelColor
            groupStatus[group] = status
            let accessory = NSStackView(views: [status, groupSwitch])
            accessory.spacing = 10
            var rows = [SettingsUI.row(group.title, tile: SettingsUI.tile(group.symbol, group.color), accessory: accessory, bold: true)]
            // Un groupe d'un seul élément n'a que son interrupteur.
            if group.entries.count > 1 {
                for entry in group.entries {
                    let entrySwitch = SettingsUI.toggle(entry.isChecked, target: self, action: #selector(toggleEntry(_:)), identifier: entry.rawValue, label: entry.title)
                    entrySwitch.controlSize = .small
                    entrySwitches[entry] = entrySwitch
                    let row = SettingsUI.row(entry.title, accessory: entrySwitch, indent: true)
                    entryRows[entry] = row
                    rows.append(row)
                }
            }
            let card = SettingsCard(rows: rows)
            cards[group] = card
            sections += [SettingsUI.caption(""), card]
        }
        let reset = NSButton(title: L("Tout réafficher"), target: self, action: #selector(resetAll))
        let resetRow = NSStackView(views: [NSView(), reset])
        resetRow.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 0, right: 0)
        sections.append(resetRow)
        view = SettingsUI.page(title: L("Menu contextuel"),
                               intro: L("Un groupe désactivé disparaît du clic droit ; sinon, choisissez ses éléments un à un. Tout reste dans la barre de menus, avec les raccourcis."),
                               sections: sections)
        refresh()
    }

    private func refresh() {
        for group in ContextMenuGroup.allCases {
            groupSwitches[group]?.state = group.isShown ? .on : .off
            let checked = group.entries.filter(\.isChecked).count
            groupStatus[group]?.stringValue = !group.isShown ? L("masqué")
                : (group.entries.count > 1 && checked < group.entries.count ? L("\(checked) sur \(group.entries.count)") : "")
            for entry in group.entries {
                entrySwitches[entry]?.state = entry.isChecked ? .on : .off
                if let row = entryRows[entry] { cards[group]?.setRow(row, hidden: !group.isShown) }
            }
        }
    }

    @objc private func toggleGroup(_ sender: NSSwitch) {
        guard let group = sender.identifier.flatMap({ ContextMenuGroup(rawValue: $0.rawValue) }) else { return }
        group.isShown = sender.state == .on
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            refresh()
            view.layoutSubtreeIfNeeded()
        }
    }

    @objc private func toggleEntry(_ sender: NSSwitch) {
        guard let entry = sender.identifier.flatMap({ ContextMenuEntry(rawValue: $0.rawValue) }) else { return }
        entry.isChecked = sender.state == .on
        refresh()
    }

    @objc private func resetAll() {
        ContextMenuEntry.resetAll()
        refresh()
    }
}

extension ContextMenuGroup {
    var symbol: String {
        switch self {
        case .palette: "sparkles"
        case .open: "arrow.up.forward.app.fill"
        case .organize: "folder.fill"
        case .fileActions: "bolt.fill"
        case .transform: "archivebox.fill"
        case .share: "square.and.arrow.up.fill"
        case .create: "plus.square.fill"
        case .trash: "trash.fill"
        case .view: "list.bullet"
        }
    }

    var color: NSColor {
        switch self {
        case .palette: .systemIndigo
        case .open: .systemBlue
        case .organize: .systemCyan
        case .fileActions: .systemPurple
        case .transform: .systemOrange
        case .share: .systemGreen
        case .create: .systemTeal
        case .trash: .systemRed
        case .view: .systemGray
        }
    }
}
