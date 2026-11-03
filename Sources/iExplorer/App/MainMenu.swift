import AppKit
import UpdateKit

enum MainMenu {
    /// Menu « Actions » : actions personnalisées (avec leurs raccourcis) et gestion.
    static func fillActionsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for action in CustomAction.all { menu.addItem(action.menuItem()) }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        let manage = NSMenuItem(title: L("Gérer les actions…"), action: #selector(AppDelegate.manageCustomActions(_:)), keyEquivalent: "")
        manage.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(manage)
        let byType = NSMenuItem(title: L("Actions par type de fichier…"), action: #selector(AppDelegate.manageFileActions(_:)), keyEquivalent: "")
        byType.image = NSImage(systemSymbolName: "doc.badge.gearshape", accessibilityDescription: nil)
        menu.addItem(byType)
    }

    /// Fournit le sous-menu « Dossiers récents » (gardé en vie pour toute la durée de l'app).
    /// Fichier › Créer un lien : symbolique ou physique, ici ou dans l'autre panneau.
    private static func linkMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("Créer un lien"))
        for (title, action, key, modifiers) in [(L("Lien symbolique ici"), #selector(Panel.symlinkHere(_:)), "l", NSEvent.ModifierFlags([.command, .control])),
                                                (L("Lien symbolique dans l’autre panneau"), #selector(Panel.symlinkInOtherPanel(_:)), String(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!)), [.control]),
                                                (L("Lien physique ici"), #selector(Panel.hardLinkHere(_:)), "", []),
                                                (L("Lien physique dans l’autre panneau"), #selector(Panel.hardLinkInOtherPanel(_:)), "", [])] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            menu.addItem(entry)
        }
        let item = NSMenuItem(title: L("Créer un lien"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static let recentProvider = HistoryMenuProvider(kind: .recent) { nil }

    private typealias Panel = PanelViewController

    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = "iExplorer"

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.tag = tag
            return item
        }
        @discardableResult
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
            return menu
        }
        func functionKey(_ key: Int) -> String { String(Character(UnicodeScalar(UInt32(key))!)) }
        let separator = { NSMenuItem.separator() }

        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu

        let updates = item(L("Rechercher les mises à jour…"), #selector(Updater.checkForUpdates(_:)))
        updates.target = MainActor.assumeIsolated { Updater.shared }

        submenu(appName, [
            item(L("À propos de \(appName)"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            updates,
            separator(),
            item(L("Réglages…"), #selector(AppDelegate.showSettings(_:)), ","),
            item(L("Raccourcis clavier…"), #selector(AppDelegate.showKeyboardShortcuts(_:)), ",", [.command, .option]),
            separator(),
            services,
            separator(),
            item(L("Masquer \(appName)"), #selector(NSApplication.hide(_:)), "h"),
            item(L("Masquer les autres"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(L("Tout afficher"), #selector(NSApplication.unhideAllApplications(_:))),
            separator(),
            item(L("Quitter \(appName)"), #selector(NSApplication.terminate(_:)), "q"),
        ])

        submenu(L("Fichier"), [
            item(L("Nouvel onglet"), #selector(Panel.newTab(_:)), "t"),
            item(L("Dupliquer l’onglet"), #selector(Panel.duplicateTab(_:)), ""),
            item(L("Nouveau dossier"), #selector(Panel.newFolder(_:)), "n", [.command, .shift]),
            {
                let item = NSMenuItem(title: L("Nouveau document"), action: nil, keyEquivalent: "")
                item.submenu = NSMenu(title: L("Nouveau document"))
                item.submenu?.delegate = NewDocumentMenuDelegate.shared
                return item
            }(),
            separator(),
            item(L("Ouvrir"), #selector(Panel.openSelection(_:)), "o"),
            item(L("Ouvrir dans un nouvel onglet"), #selector(Panel.openInNewTab(_:)), "o", [.command, .shift]),
            item(L("Coup d’œil"), #selector(Panel.quickLook(_:)), "y"),
            item(L("Afficher dans le Finder"), #selector(Panel.revealInFinder(_:)), "r", [.command, .shift]),
            item(L("Ouvrir dans le Terminal"), #selector(Panel.openInTerminal(_:)), "t", [.command, .option]),
            item(L("Ajouter aux favoris"), #selector(Panel.addToFavorites(_:)), "t", [.command, .control]),
            item(L("Partager…"), #selector(Panel.shareSelection(_:))),
            item(L("Sommes de contrôle…"), #selector(Panel.showChecksums(_:)), "k", [.command, .control]),
            item(L("Découper le fichier…"), #selector(Panel.splitFile(_:))),
            item(L("Réassembler les morceaux…"), #selector(Panel.joinFiles(_:))),
            separator(),
            item(L("Renommer"), #selector(Panel.renameSelection(_:)), functionKey(NSF2FunctionKey), []),
            item(L("Renommer par lot…"), #selector(Panel.batchRename(_:)), "r", [.command, .control]),
            item(L("Copier vers l’autre panneau"), #selector(Panel.copyToOtherPanel(_:)), functionKey(NSF5FunctionKey), []),
            item(L("Déplacer vers l’autre panneau"), #selector(Panel.moveToOtherPanel(_:)), functionKey(NSF6FunctionKey), []),
            linkMenuItem(),
            item(L("Placer dans la corbeille"), #selector(Panel.moveToTrash(_:)), "\u{8}"),
            item(L("Vérifier les copies"), #selector(AppDelegate.toggleVerifyCopies(_:))),
            separator(),
            item(L("Compresser"), #selector(Panel.compressSelection(_:)), "k", [.command, .option]),
            item(L("Compresser…"), #selector(Panel.compressCustom(_:)), "k", [.command, .option, .shift]),
            item(L("Chiffrer…"), #selector(Panel.encryptFiles(_:)), "e", [.command, .control, .option]),
            item(L("Déchiffrer…"), #selector(Panel.decryptFiles(_:)), "d", [.command, .control, .option]),
            item(L("Décompresser ici"), #selector(Panel.extractHere(_:)), "e", [.command, .option]),
            item(L("Décompresser vers l’autre panneau"), #selector(Panel.extractToOtherPanel(_:)), "e", [.command, .option, .shift]),
            separator(),
            item(L("Se connecter au serveur…"), #selector(MainWindowController.connectToServer(_:)), "k"),
            separator(),
            item(L("Fermer l’onglet"), #selector(Panel.closeTab(_:)), "w"),
            item(L("Fermer la fenêtre"), #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
        ])

        submenu(L("Édition"), [
            // « Annuler » et « Rétablir » servent aussi de boutons (Cancel, Restore) : noms standard posés directement.
            item(AppLanguage.current == "fr" ? "Annuler" : "Undo", Selector(("undo:")), "z"),
            item(AppLanguage.current == "fr" ? "Rétablir" : "Redo", Selector(("redo:")), "z", [.command, .shift]),
            separator(),
            item(L("Couper"), #selector(Panel.cut(_:)), "x"),
            item(L("Copier"), #selector(Panel.copy(_:)), "c"),
            item(L("Coller"), #selector(Panel.paste(_:)), "v"),
            item(L("Déplacer l’élément ici"), #selector(Panel.pasteMove(_:)), "v", [.command, .option]),
            item(L("Dupliquer"), #selector(Panel.duplicate(_:)), "d"),
            item(L("Copier le chemin"), #selector(Panel.copyPath(_:)), "c", [.command, .option]),
            separator(),
            item(L("Tout sélectionner"), #selector(NSResponder.selectAll(_:)), "a"),
            item(L("Sélectionner selon un motif…"), #selector(Panel.selectByPattern(_:)), "a", [.command, .option]),
            item(L("Désélectionner selon un motif…"), #selector(Panel.deselectByPattern(_:)), "a", [.command, .option, .shift]),
            item(L("Inverser la sélection"), #selector(Panel.invertSelection(_:)), "i", [.command, .control]),
            item(L("Sélectionner les éléments du même type"), #selector(Panel.selectSameType(_:))),
            separator(),
            item(L("Rechercher…"), #selector(Panel.showSearch(_:)), "f"),
            item(L("Filtrer ce dossier…"), #selector(Panel.showFilter(_:)), "f", [.command, .option]),
            separator(),
            item(L("Touches de Total Commander (F3 à F8, + − *)"), #selector(AppDelegate.toggleCommanderKeys(_:))),
        ])

        let sortMenu = NSMenuItem(title: L("Trier par"), action: nil, keyEquivalent: "")
        sortMenu.submenu = NSMenu(title: L("Trier par"))
        for (index, title) in [L("Nom"), L("Taille"), L("Date de modification"), L("Type")].enumerated() {
            sortMenu.submenu?.addItem(item(title, #selector(Panel.sortBy(_:)), "\(index + 1)", [.command, .control, .option], tag: index))
        }

        let groupMenu = NSMenuItem(title: L("Regrouper par"), action: nil, keyEquivalent: "")
        groupMenu.submenu = NSMenu(title: L("Regrouper par"))
        for value in PanelGrouping.allCases {
            groupMenu.submenu?.addItem(item(value.title, #selector(Panel.groupBy(_:)), tag: value.rawValue))
            if value == .none { groupMenu.submenu?.addItem(.separator()) }
        }

        let themeMenu = NSMenuItem(title: L("Thème d’icônes"), action: nil, keyEquivalent: "")
        themeMenu.submenu = NSMenu(title: L("Thème d’icônes"))
        for theme in IconTheme.allCases {
            themeMenu.submenu?.addItem(item(theme.title, #selector(AppDelegate.setIconTheme(_:)), tag: theme.rawValue))
            if theme == .system { themeMenu.submenu?.addItem(.separator()) }
        }

        let layoutMenuItem = NSMenuItem(title: L("Disposition"), action: nil, keyEquivalent: "")
        layoutMenuItem.submenu = MainWindowController.layoutMenu()

        let colorThemeMenu = NSMenuItem(title: L("Thème de couleurs"), action: nil, keyEquivalent: "")
        colorThemeMenu.submenu = ColorTheme.menu()

        submenu(L("Présentation"), [
            item(L("Icônes"), #selector(Panel.showAsIcons(_:)), "1"),
            item(L("Liste"), #selector(Panel.showAsList(_:)), "2"),
            item(L("Liste détaillée"), #selector(Panel.showAsDetails(_:)), "3"),
            item(L("Colonnes"), #selector(Panel.showAsColumns(_:)), "4"),
            item(L("Occupation du disque"), #selector(Panel.toggleDiskUsage(_:)), "5"),
            item(L("Agrandir"), #selector(Panel.increaseIconSize(_:)), "+"),
            item(L("Réduire"), #selector(Panel.decreaseIconSize(_:)), "-"),
            item(L("Taille par défaut"), #selector(Panel.resetZoom(_:)), "0"),
            item(L("Masquer la barre d’état"), #selector(Panel.toggleStatusBar(_:)), "/"),
            item(L("Éditeur à côté du panneau unique"), #selector(MainWindowController.toggleEditor(_:)), "e", [.command, .control]),
            item(L("Éditeur : aperçu seul"), #selector(MainWindowController.setEditorMode(_:)), "1", [.command, .control], tag: EditorMode.preview.rawValue),
            item(L("Éditeur : texte et aperçu"), #selector(MainWindowController.setEditorMode(_:)), "2", [.command, .control], tag: EditorMode.mixed.rawValue),
            item(L("Éditeur : texte seul"), #selector(MainWindowController.setEditorMode(_:)), "3", [.command, .control], tag: EditorMode.source.rawValue),
            sortMenu,
            groupMenu,
            item(L("Vue à plat"), #selector(Panel.toggleFlatView(_:)), "b", [.command, .control]),
            item(L("Taille des dossiers en direct"), #selector(Panel.toggleLiveFolderSizes(_:))),
            item(L("Calculer la taille des dossiers sélectionnés"), #selector(Panel.computeSelectedFolderSizes(_:)), " ", .option),
            item(L("Calculer la taille de tous les dossiers"), #selector(Panel.computeAllFolderSizes(_:)), " ", [.option, .shift]),
            themeMenu,
            colorThemeMenu,
            separator(),
            layoutMenuItem,
            item(L("Répartir les panneaux équitablement"), #selector(MainWindowController.equalizePanels(_:)), "=", [.command, .option]),
            item(L("Panneau suivant"), #selector(MainWindowController.focusNextPanel(_:))),
            separator(),
            item(L("Onglet suivant"), #selector(Panel.nextTab(_:)), "\t", .control),
            item(L("Onglet précédent"), #selector(Panel.previousTab(_:)), "\t", [.control, .shift]),
            separator(),
            item(L("Afficher les fichiers cachés"), #selector(AppDelegate.toggleHiddenFiles(_:)), ".", [.command, .shift]),
            item(L("Actualiser"), #selector(Panel.refresh(_:)), "r"),
            separator(),
            item(L("Afficher l’inspecteur"), #selector(MainWindowController.toggleInspectorPane(_:)), "i", [.command, .option]),
            item(L("Afficher le terminal"), #selector(MainWindowController.toggleTerminal(_:)), "`", .control),
            item(L("État Git dans les panneaux"), #selector(AppDelegate.toggleGit(_:)), "g", [.command, .control]),
            item(L("Afficher/masquer la barre latérale"), #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            item(L("Plein écran"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        let recentItem = NSMenuItem(title: L("Historique"), action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu(title: L("Historique"))
        recentItem.submenu?.delegate = recentProvider

        submenu(L("Aller"), [
            item(L("Précédent"), #selector(Panel.goBack(_:)), "["),
            item(L("Suivant"), #selector(Panel.goForward(_:)), "]"),
            item(L("Dossier parent"), #selector(Panel.goUp(_:)), functionKey(NSUpArrowFunctionKey)),
            item(L("Ouvrir"), #selector(Panel.openSelection(_:)), functionKey(NSDownArrowFunctionKey)),
            separator(),
            item(L("Ordinateur"), #selector(Panel.goComputer(_:)), "c", [.command, .shift]),
            item(L("Départ"), #selector(Panel.goHome(_:)), "h", [.command, .shift]),
            item(L("Bureau"), #selector(Panel.goDesktop(_:)), "d", [.command, .shift]),
            item(L("Documents"), #selector(Panel.goDocuments(_:)), "o", [.command, .shift, .option]),
            item(L("Téléchargements"), #selector(Panel.goDownloads(_:)), "l", [.command, .option]),
            item(L("Applications"), #selector(Panel.goApplications(_:)), "a", [.command, .shift]),
            separator(),
            item(L("Même dossier dans l’autre panneau"), #selector(Panel.syncOtherPanel(_:)), "=", .command),
            item(L("Navigation synchronisée"), #selector(MainWindowController.toggleSyncNavigation(_:)), "y", [.command, .control]),
            item(L("Comparer et synchroniser les panneaux…"), #selector(Panel.compareWithOtherPanel(_:)), "c", [.command, .control]),
            item(L("Aller au dossier…"), #selector(Panel.goToFolder(_:)), "g", [.command, .shift]),
            recentItem,
        ])

        let actions = submenu("Actions", [])
        fillActionsMenu(actions)

        let window = submenu(L("Fenêtre"), [
            item(L("Placer dans le Dock"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(L("Réduire/agrandir"), #selector(NSWindow.performZoom(_:))),
            separator(),
            item(L("Tout ramener au premier plan"), #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window

        let help = submenu(L("Aide"), [
            item(L("Diagnostic des favoris du Finder…"), #selector(AppDelegate.showFinderFavoritesDiagnostic(_:))),
        ])
        NSApp.helpMenu = help

        return main
    }
}
