import AppKit
import UpdateKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var windowControllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.apply()
        AppIconChoice.apply()
        Effects.installDiskEffects()
        // Écrire dans un tube dont le lecteur est parti (tar interrompu) renvoie une erreur au lieu de tuer l'app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.mainMenu = MainMenu.build()
        KeyboardShortcuts.apply()
        FileActionStore.shared.installDefaults()
        DocumentTemplates.installDefaults()
        DispatchQueue.global(qos: .utility).async { ArchiveBrowser.purge() }
        // PATH du shell de connexion, lu d'avance pour ne pas ralentir le premier menu contextuel.
        DispatchQueue.global(qos: .utility).async { _ = ShellEnvironment.path }
        NotificationCenter.default.addObserver(forName: CustomAction.changed, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildActionsMenu()
        }
        // Une seule fenêtre principale : on restaure la dernière session.
        openWindow(state: SessionStore.load().first)
        // Sauvegarde aussi quand l'app passe en arrière-plan (au cas où elle serait arrêtée brutalement).
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveSession()
        }
        NSApp.activate()
        Updater.shared.beforeRelaunch = { [weak self] in self?.saveSession() }
        if Preferences.checksUpdatesAtLaunch { Updater.shared.checkAtLaunch() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if EditorViewController.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = L("Des fichiers modifiés dans l’éditeur ne sont pas enregistrés.")
            alert.informativeText = L("Si vous quittez maintenant, ces modifications seront perdues.")
            alert.addButton(withTitle: L("Annuler"))
            alert.addButton(withTitle: L("Quitter sans enregistrer"))
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        guard FileOperationCenter.shared.hasActiveJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("Des opérations sur les fichiers sont en cours.")
        alert.informativeText = L("Si vous quittez maintenant, elles seront interrompues.")
        alert.addButton(withTitle: L("Continuer"))
        alert.addButton(withTitle: L("Quitter"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !windowControllers.isEmpty { saveSession() }
    }

    private func openWindow(state: WindowState?) {
        let controller = MainWindowController(state: state)
        controller.onClose = { [weak self] closed in
            guard let self else { return }
            // La dernière fenêtre fermée devient la session restaurée au prochain lancement.
            if windowControllers.count == 1 { saveSession() }
            windowControllers.removeAll { $0 === closed }
        }
        windowControllers.append(controller)
        controller.showWindow(nil)
    }

    private func saveSession() {
        SessionStore.save(windowControllers.map(\.windowState))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowControllers.first?.showWindow(nil)
        return false
    }

    @objc func toggleGit(_ sender: Any?) {
        if !GitService.isEnabled, !GitService.shared.isAvailable {
            let alert = NSAlert()
            alert.messageText = L("Git n’est pas disponible.")
            alert.informativeText = L("Installez les outils de ligne de commande (xcode-select --install) pour afficher l’état Git.")
            alert.runModal()
            (sender as? NSButton)?.state = .off
            return
        }
        GitService.isEnabled.toggle()
    }

    @objc func clearRecentFolders(_ sender: Any?) { RecentFolders.clear() }

    @objc func manageCustomActions(_ sender: Any?) {
        SettingsWindowController.show(tab: .customActions)
    }

    /// Actions par type de fichier ; depuis le menu contextuel, l'élément porte la règle à afficher.
    @objc func manageFileActions(_ sender: Any?) {
        let file = (sender as? NSMenuItem)?.representedObject as? URL
        let directory = (NSApp.mainWindow?.windowController as? MainWindowController)?.activePanel.currentURL
        FileActionsEditorController.show(selecting: file, projectDirectory: directory?.isFileURL == true ? directory : nil)
    }

    /// Reconstruit le menu « Actions » (raccourcis compris) après une modification.
    private func rebuildActionsMenu() {
        guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == "Actions" })?.submenu else { return }
        MainMenu.fillActionsMenu(menu)
    }

    @objc func toggleVerifyCopies(_ sender: Any?) { Preferences.verifyCopies.toggle() }

    @objc func showFinderFavoritesDiagnostic(_ sender: Any?) {
        FinderFavorites.showDiagnostic()
    }

    @objc func setColorTheme(_ sender: NSMenuItem) {
        withThemeWave { ColorTheme.current = ColorTheme(rawValue: sender.tag) ?? .system }
    }

    @objc func chooseAppearance(_ sender: NSMenuItem) {
        withThemeWave { AppAppearance.current = AppAppearance(rawValue: sender.tag) ?? .automatic }
    }

    /// Whaouh+++ : le nouveau thème se propage en vague depuis le haut à droite (bouton Thèmes).
    private func withThemeWave(_ apply: () -> Void) {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        let origin = window.map { CGPoint(x: $0.frame.width - 150, y: $0.frame.height - 30) } ?? .zero
        Effects.themeWave(in: window, from: origin, apply: apply)
    }

    @objc func setIconTheme(_ sender: NSMenuItem) {
        IconTheme.current = IconTheme(rawValue: sender.tag) ?? .system
    }

    @objc func toggleCommanderKeys(_ sender: Any?) {
        Preferences.commanderKeys.toggle()
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        Preferences.showHiddenFiles.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setColorTheme(_:)) {
            menuItem.state = menuItem.tag == ColorTheme.current.rawValue ? .on : .off
        }
        if menuItem.action == #selector(chooseAppearance(_:)) {
            menuItem.state = menuItem.tag == AppAppearance.current.rawValue ? .on : .off
        }
        if menuItem.action == #selector(setIconTheme(_:)) {
            menuItem.state = menuItem.tag == IconTheme.current.rawValue ? .on : .off
        }
        if menuItem.action == #selector(toggleVerifyCopies(_:)) {
            menuItem.state = Preferences.verifyCopies ? .on : .off
        }
        if menuItem.action == #selector(toggleCommanderKeys(_:)) {
            menuItem.state = Preferences.commanderKeys ? .on : .off
        }
        if menuItem.action == #selector(toggleGit(_:)) {
            menuItem.state = GitService.isEnabled ? .on : .off
        }
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.state = Preferences.showHiddenFiles ? .on : .off
        }
        return true
    }
}
