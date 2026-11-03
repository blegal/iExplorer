import AppKit

/// Désinstallation propre d'une app : l'app et ce qu'elle a laissé dans ~/Library (réglages, caches, conteneurs…),
/// placés ensemble dans la corbeille après confirmation (⌘Z les remet en place).
enum AppUninstaller {
    /// Dossiers de ~/Library où les apps rangent leurs données, et ce qui y désigne l'app.
    private enum Match { case identifier, identifierOrName, containsIdentifier }
    private static let places: [(String, Match)] = [
        ("Application Support", .identifierOrName), ("Caches", .identifierOrName), ("Logs", .identifierOrName),
        ("Preferences", .identifier), ("Preferences/ByHost", .identifier), ("Containers", .identifier),
        ("Group Containers", .containsIdentifier), ("Application Scripts", .identifier),
        ("Saved Application State", .identifier), ("HTTPStorages", .identifier), ("WebKit", .identifier),
        ("Cookies", .identifier), ("LaunchAgents", .identifier),
    ]

    struct App {
        let url: URL
        let name: String
        let identifier: String
    }

    /// L'app du paquet, ou un message expliquant pourquoi elle ne peut pas être désinstallée.
    static func app(at url: URL) -> Result<App, UninstallRefusal> {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return .failure(.notAnApp) }
        if identifier.hasPrefix("com.apple.") || url.path.hasPrefix("/System/") { return .failure(.system) }
        if identifier == Bundle.main.bundleIdentifier { return .failure(.itself) }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        return .success(App(url: url, name: name, identifier: identifier))
    }

    /// Fichiers et dossiers de ~/Library appartenant à l'app.
    static func leftovers(of app: App) -> [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let identifier = app.identifier.lowercased()
        let name = app.name.lowercased()
        var found: [URL] = []
        for (place, match) in places {
            let folder = library.appendingPathComponent(place)
            guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let entryName = entry.lastPathComponent.lowercased()
                let byIdentifier = entryName == identifier || entryName.hasPrefix(identifier + ".")
                let matches = switch match {
                case .identifier: byIdentifier
                // Un nom trop court (« Go », « R ») désignerait d'autres dossiers.
                case .identifierOrName: byIdentifier || (name.count >= 3 && entryName == name)
                case .containsIdentifier: entryName.contains(identifier)
                }
                if matches { found.append(entry) }
            }
        }
        return found
    }

    static func size(of url: URL) -> Int64 {
        if url.hasDirectoryPath || url.isExistingDirectory { return FolderSizeCalculator.size(of: url) { false } ?? 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

enum UninstallRefusal: Error {
    case notAnApp, system, itself

    var message: String {
        switch self {
        case .notAnApp: L("Ce paquet n’est pas une application.")
        case .system: L("Les applications d’Apple livrées avec macOS ne peuvent pas être désinstallées.")
        case .itself: L("iExplorer ne peut pas se désinstaller lui-même.")
        }
    }
}

extension PanelViewController {
    @objc func uninstallApp(_ sender: Any?) {
        guard let url = selectedItems.first?.url, url.pathExtension == "app", let window = view.window else { return }
        let app: AppUninstaller.App
        switch AppUninstaller.app(at: url) {
        case .success(let found): app = found
        case .failure(let refusal):
            let alert = NSAlert()
            alert.messageText = L("Impossible de désinstaller « \(url.deletingPathExtension().lastPathComponent) »")
            alert.informativeText = refusal.message
            alert.beginSheetModal(for: window)
            return
        }
        // Recherche et tailles hors du fil principal (les caches peuvent être gros).
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = ([url] + AppUninstaller.leftovers(of: app)).map { ($0, AppUninstaller.size(of: $0)) }
            DispatchQueue.main.async { [weak self] in self?.confirmUninstall(app, entries: entries, in: window) }
        }
    }

    private func confirmUninstall(_ app: AppUninstaller.App, entries: [(URL, Int64)], in window: NSWindow) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let boxes = entries.map { url, size in
            let path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
            let box = NSButton(checkboxWithTitle: "\(path)  (\(Format.fileSize(size)))", target: nil, action: nil)
            box.state = .on
            box.lineBreakMode = .byTruncatingMiddle
            box.toolTip = url.path
            return box
        }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: min(CGFloat(boxes.count) * 24 + 10, 260)))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        stack.frame = NSRect(x: 0, y: 0, width: 440, height: stack.fittingSize.height)
        scroll.documentView = stack

        let total = entries.reduce(0) { $0 + $1.1 }
        let alert = NSAlert()
        alert.messageText = L("Désinstaller « \(app.name) » ?")
        var details = entries.count == 1
            ? L("Aucun fichier de l’app n’a été trouvé dans votre bibliothèque.")
            : L("L’app et \(entries.count - 1) éléments de votre bibliothèque (réglages, caches, données) seront placés dans la corbeille, \(Format.fileSize(total)) en tout. ⌘Z les remet en place.")
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.identifier)
        if !running.isEmpty { details += "\n\n" + L("L’app est ouverte : elle sera quittée d’abord.") }
        alert.informativeText = details
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("Placer dans la corbeille")).hasDestructiveAction = true
        alert.addButton(withTitle: L("Annuler"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let chosen = zip(entries, boxes).filter { $0.1.state == .on }.map(\.0.0)
            guard !chosen.isEmpty else { return }
            self?.trashUninstalled(chosen, running: running)
        }
    }

    private func trashUninstalled(_ urls: [URL], running: [NSRunningApplication]) {
        running.forEach { $0.terminate() }
        // On laisse quelques secondes à l'app pour se fermer et enregistrer ses réglages.
        let deadline = Date().addingTimeInterval(5)
        func attempt() {
            if running.contains(where: { !$0.isTerminated }), Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: attempt)
                return
            }
            FileOperationCenter.shared.trash(urls, undoManager: undoManager, actionName: L("Désinstaller l’app"))
            reload()
        }
        attempt()
    }
}
