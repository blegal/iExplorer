import AppKit

/// Calcul de la taille des dossiers en arrière-plan : d'office (Présentation › Taille des dossiers en direct)
/// ou à la demande (⌥Espace).
enum FolderSizeCalculator {
    /// Calculs en attente, le plus récent d'abord : le dossier qu'on vient d'ouvrir passe avant ceux de la veille.
    /// Manipulés sur le fil principal.
    private static var pending: [() -> Void] = []
    private static var running = 0
    private static let maxRunning = 3

    /// Taille logique totale du contenu ; `isCancelled` est consulté régulièrement.
    static func size(of url: URL, isCancelled: @escaping () -> Bool) -> Int64? {
        if url.isRemote {
            guard let session = try? SFTPManager.shared.session(for: url) else { return nil }
            func walk(_ path: String) -> Int64 {
                guard !isCancelled(), let listing = try? session.list(path) else { return 0 }
                return listing.entries.reduce(0) { total, entry in total + (entry.isDirectory ? walk(entry.path) : entry.size) }
            }
            return walk(url.path)
        }
        if isCancelled() { return nil }
        var total: Int64 = 0
        var visited = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                        options: [], errorHandler: { _, _ in true })
        while let child = enumerator?.nextObject() as? URL {
            visited += 1
            if visited % 1000 == 0, isCancelled() { return nil }
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    static func enqueue(_ work: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        pending.append(work)
        pump()
    }

    private static func pump() {
        while running < maxRunning, let work = pending.popLast() {
            running += 1
            DispatchQueue.global(qos: .utility).async {
                work()
                DispatchQueue.main.async {
                    running -= 1
                    pump()
                }
            }
        }
    }

    /// Tailles déjà calculées, partagées par les panneaux : revenir dans un dossier ne relance pas tout.
    /// Une taille vieille de plus de cinq minutes est recalculée.
    private static var cache: [String: (size: Int64, date: Date)] = [:]
    private static let lifetime: TimeInterval = 300

    static func cachedSize(_ key: String) -> Int64? {
        guard let entry = cache[key], Date().timeIntervalSince(entry.date) < lifetime else { return nil }
        return entry.size
    }

    static func store(_ size: Int64, for key: String) { cache[key] = (size, Date()) }

    /// Dossiers calculés d'office : sur un disque local, hors archive dépliée et hors serveur.
    static func allowsLiveSizes(in url: URL) -> Bool {
        guard Preferences.liveFolderSizes, url.isFileURL, ArchiveBrowser.archive(containing: url) == nil else { return false }
        return (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? false
    }
}

extension PanelViewController {
    /// ⌥Espace : taille des dossiers sélectionnés.
    @objc func computeSelectedFolderSizes(_ sender: Any?) {
        computeFolderSizes(selectedItems.filter(\.isNavigableDirectory))
    }

    /// ⇧⌥Espace : taille de tous les dossiers affichés.
    @objc func computeAllFolderSizes(_ sender: Any?) {
        computeFolderSizes(items.filter(\.isNavigableDirectory))
    }

    @objc func toggleLiveFolderSizes(_ sender: Any?) { Preferences.liveFolderSizes.toggle() }

    /// Taille des dossiers en direct : lancée dès l'affichage d'un dossier (ou le dépliage d'un sous-dossier).
    func computeLiveFolderSizes(_ list: [FileItem]) {
        guard FolderSizeCalculator.allowsLiveSizes(in: currentURL) else { return }
        computeFolderSizes(list.filter(\.isNavigableDirectory))
    }

    private func computeFolderSizes(_ folders: [FileItem]) {
        for folder in folders where folderSizes[folder.url.normalizedPath] == nil {
            if let size = FolderSizeCalculator.cachedSize(folder.url.normalizedPath) {
                folderSizes[folder.url.normalizedPath] = size
                folder.folderSize = size
            }
        }
        let pending = folders.filter { folderSizes[$0.url.normalizedPath] == nil && !computingFolders.contains($0.url.normalizedPath) }
        guard !pending.isEmpty else { scheduleFolderSizesRefresh(); return }
        let generation = folderSizeGeneration
        // Pile : en ordre inverse, pour que les premiers dossiers de la liste passent en premier.
        for folder in pending.reversed() {
            let key = folder.url.normalizedPath
            computingFolders.insert(key)
            let url = folder.url
            FolderSizeCalculator.enqueue { [weak self] in
                let size = FolderSizeCalculator.size(of: url) { [weak self] in
                    // Annulé si le panneau a changé de dossier entre-temps.
                    DispatchQueue.main.sync { self?.folderSizeGeneration != generation }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == folderSizeGeneration else { return }
                    computingFolders.remove(key)
                    if let size {
                        folderSizes[key] = size
                        FolderSizeCalculator.store(size, for: key)
                    }
                    scheduleFolderSizesRefresh()
                }
            }
        }
        // Après la mise en place de la liste en cours (appel depuis `apply`).
        scheduleFolderSizesRefresh()
    }

    /// Regroupe les rafraîchissements : des dizaines de dossiers peuvent finir en même temps.
    private func scheduleFolderSizesRefresh() {
        guard !folderSizesRefreshPending else { return }
        folderSizesRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.folderSizesRefreshPending = false
            self?.applyFolderSizes()
        }
    }

    /// Reporte les tailles connues sur les éléments, retrie si besoin et rafraîchit l'affichage.
    func applyFolderSizes() {
        for item in allItems where item.isNavigableDirectory {
            item.folderSize = folderSizes[item.url.normalizedPath]
        }
        if sortDescriptor.key == "size" {
            let selection = selectedURLs
            allItems = Self.sorted(allItems, by: sortDescriptor)
            if !isShowingSearchResults {
                let filter = isSearching && searchBar.scope == .folder ? Self.nameMatcher(for: searchBar.field.stringValue.trimmingCharacters(in: .whitespaces)) : nil
                items = filter.map { match in allItems.filter { item in match(item.name) { item.finderTags } } } ?? allItems
            }
            reloadViews()
            let paths = Set(selection.map(\.normalizedPath))
            setSelection(IndexSet(items.indices.filter { paths.contains(items[$0].url.normalizedPath) }), scroll: false)
        } else {
            let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("size"))
            if column >= 0, !items.isEmpty {
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows), columnIndexes: [column])
            }
        }
        updateInfo()
    }

    /// Texte de la colonne Taille pour un dossier.
    func folderSizeText(for item: FileItem) -> String {
        if let size = item.folderSize { return Format.fileSize(size) }
        return computingFolders.contains(item.url.normalizedPath) ? "…" : "—"
    }
}
