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

/// Onglet « Menu contextuel » des Réglages : une case par groupe, puis, en retrait, une case par élément.
final class ContextMenuSettingsViewController: NSViewController {
    private var groupBoxes: [ContextMenuGroup: NSButton] = [:]
    private var entryBoxes: [ContextMenuEntry: NSButton] = [:]

    override func loadView() {
        let intro = NSTextField(wrappingLabelWithString: L("Décochez un groupe pour le retirer du clic droit, ou seulement certains de ses éléments. Ils restent dans la barre de menus et gardent leurs raccourcis."))
        intro.textColor = .secondaryLabelColor
        intro.font = .systemFont(ofSize: 12)
        var views: [NSView] = [intro]
        // Vues après lesquelles un groupe commence : un peu d'air entre les groupes.
        var groupEnds: [NSView] = []
        for group in ContextMenuGroup.allCases {
            if views.count > 1, let last = views.last { groupEnds.append(last) }
            let box = NSButton(checkboxWithTitle: group.title, target: self, action: #selector(toggleGroup(_:)))
            box.font = .systemFont(ofSize: 13, weight: .semibold)
            box.identifier = NSUserInterfaceItemIdentifier(group.rawValue)
            groupBoxes[group] = box
            views.append(box)
            // Un groupe d'un seul élément n'a que sa propre case.
            guard group.entries.count > 1 else { continue }
            for entry in group.entries {
                let entryBox = NSButton(checkboxWithTitle: entry.title, target: self, action: #selector(toggleEntry(_:)))
                entryBox.identifier = NSUserInterfaceItemIdentifier(entry.rawValue)
                entryBoxes[entry] = entryBox
                let row = NSStackView(views: [entryBox])
                row.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 0)
                views.append(row)
            }
        }
        let reset = NSButton(title: L("Tout réafficher"), target: self, action: #selector(resetAll))
        views.append(reset)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(12, after: intro)
        stack.setCustomSpacing(14, after: views[views.count - 2])
        groupEnds.forEach { stack.setCustomSpacing(10, after: $0) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedClipContent()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            intro.widthAnchor.constraint(equalToConstant: 500),
        ])
        view = scroll
        preferredContentSize = NSSize(width: 560, height: 620)
        refresh()
    }

    private func refresh() {
        for (group, box) in groupBoxes { box.state = group.isShown ? .on : .off }
        for (entry, box) in entryBoxes {
            box.state = entry.isChecked ? .on : .off
            box.isEnabled = entry.group.isShown
        }
    }

    @objc private func toggleGroup(_ sender: NSButton) {
        guard let group = sender.identifier.flatMap({ ContextMenuGroup(rawValue: $0.rawValue) }) else { return }
        group.isShown = sender.state == .on
        refresh()
    }

    @objc private func toggleEntry(_ sender: NSButton) {
        guard let entry = sender.identifier.flatMap({ ContextMenuEntry(rawValue: $0.rawValue) }) else { return }
        entry.isChecked = sender.state == .on
        refresh()
    }

    @objc private func resetAll() {
        ContextMenuEntry.resetAll()
        refresh()
    }
}
