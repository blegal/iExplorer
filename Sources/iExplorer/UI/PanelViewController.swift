import AppKit
import Quartz

final class TabState {
    var url: URL
    var back: [URL] = []
    var forward: [URL] = []
    var selection: [URL] = []
    var color: TabColor?

    init(url: URL) { self.url = url.isRemote ? url.standardized : url.standardizedFileURL }
}

enum PanelViewMode: Int, CaseIterable {
    case icons, list, details, columns

    var title: String {
        switch self {
        case .icons: L("Icônes")
        case .list: L("Liste")
        case .details: L("Liste détaillée")
        case .columns: L("Colonnes")
        }
    }

    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .details: "list.bullet.rectangle"
        case .columns: "rectangle.split.3x1"
        }
    }

    var action: Selector {
        switch self {
        case .icons: #selector(PanelViewController.showAsIcons(_:))
        case .list: #selector(PanelViewController.showAsList(_:))
        case .details: #selector(PanelViewController.showAsDetails(_:))
        case .columns: #selector(PanelViewController.showAsColumns(_:))
        }
    }

    var icon: NSImage? { NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
}

protocol PanelHost: AnyObject {
    func panelDidBecomeActive(_ panel: PanelViewController)
    func panelDidChangeDirectory(_ panel: PanelViewController)
    /// Déplacement explicite (navigation, retour, colonnes) : sert à la navigation synchronisée.
    func panel(_ panel: PanelViewController, didMoveFrom old: URL, to new: URL)
    func panelSelectionDidChange(_ panel: PanelViewController)
    func panel(_ panel: PanelViewController, focusNextBackwards backwards: Bool)
    /// Les autres panneaux visibles, dans l'ordre (le premier est la cible par défaut de F5/F6).
    func targetPanels(for panel: PanelViewController) -> [PanelViewController]
}

private extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("name")
    static let size = NSUserInterfaceItemIdentifier("size")
    static let date = NSUserInterfaceItemIdentifier("date")
    static let kind = NSUserInterfaceItemIdentifier("kind")
    static let nameCell = NSUserInterfaceItemIdentifier("nameCell")
    static let textCell = NSUserInterfaceItemIdentifier("textCell")
}

/// Un panneau de navigation : onglets, fil d'Ariane, liste des fichiers.
final class PanelViewController: NSViewController {
    let index: Int
    weak var host: PanelHost?

    private(set) var tabs: [TabState]
    private(set) var selectedTabIndex: Int
    /// Éléments affichés (après filtre de recherche) et contenu complet du dossier.
    var items: [FileItem] = []
    var allItems: [FileItem] = []

    // Recherche (⌘F)
    let searchBar = PanelSearchBar()
    var searchBarHeight: NSLayoutConstraint!
    var searchQuery: NSMetadataQuery?
    var isShowingSearchResults = false
    var searchResultsTruncated = false
    var searchGeneration = 0

    let tableView = FileTableView()
    private let scrollView = NSScrollView()
    let collectionView = FileCollectionView()
    // Vue en colonnes
    let browser = FileBrowser()
    var browserCache: [String: [FileItem]] = [:]
    var isSyncingBrowser = false
    private let gridScrollView = NSScrollView()
    // Occupation du disque (⌘5)
    let diskUsageView = DiskUsageView()
    var isShowingDiskUsage = false
    private(set) var viewMode: PanelViewMode
    private(set) var iconSize: CGFloat
    private(set) var listScale: CGFloat
    private let tabBar = TabBarView()
    let breadcrumb = BreadcrumbView()
    /// Contenu du dossier, sélection, avertissements : affichés dans la barre d'état du panneau.
    private(set) var infoText = ""
    let statusBar = PanelStatusBar()
    private let accentLine = NSView()
    private var tabBarHeight: NSLayoutConstraint!

    let watcher = DirectoryWatcher()
    /// Animation à jouer quand le nouveau dossier sera affiché (selon le mode d'animation).
    var pendingTransition: NavigationDirection?
    private var loadGeneration = 0
    private var loadError: String?
    var freeSpace: String?
    private var cutPaths: Set<String> = []
    private var renamingRow: Int?
    private var reloadDeferred = false
    /// Regroupement des vues en liste, et lignes de la table qui en découlent (voir Grouping.swift).
    var grouping: PanelGrouping = .none
    /// Vue à plat du dossier courant (voir FlatView.swift), quittée au changement de dossier.
    var isFlatView = false
    /// Dossiers dépliés dans la liste (voir Outline.swift), et la surveillance de leur contenu.
    var expandedPaths: Set<String> = []
    var outlineWatchers: [String: DirectoryWatcher] = [:]
    var groupRows: [GroupRow] = []
    var itemRows: [Int] = []
    var sortDescriptor = NSSortDescriptor(key: "name", ascending: true)

    // Tailles de dossiers calculées à la demande (par chemin), valables pour le dossier affiché.
    var folderSizes: [String: Int64] = [:]
    var computingFolders: Set<String> = []
    var folderSizeGeneration = 0

    // Git
    private let gitLabel = NSTextField(labelWithString: "")
    /// Précédent / suivant de l'onglet, en haut à droite du panneau (appui long : tout l'historique).
    private let navigationControl = NSSegmentedControl()
    /// Bascule fichiers / occupation du disque, à gauche des flèches.
    private let diskUsageToggle = ToolbarToggle()
    private lazy var backMenu = HistoryMenuProvider(kind: .back) { [weak self] in self }
    private lazy var forwardMenu = HistoryMenuProvider(kind: .forward) { [weak self] in self }
    private var gitStatus: GitRepositoryStatus?
    private var gitRelativeDirectory = ""
    private var gitSummaries: [String: GitSummary] = [:]
    private var gitGeneration = 0
    private var gitWatcher: RepositoryWatcher?

    var isActive = false { didSet { if oldValue != isActive { updateActiveAppearance() } } }
    /// Faux pour les panneaux masqués par la disposition : ni surveillance du dossier ni Git.
    var isShown = true {
        didSet {
            guard oldValue != isShown, isViewLoaded else { return }
            if isShown { showCurrentTab() } else { watcher.stop(); gitWatcher = nil; gitGeneration += 1 }
        }
    }
    /// Masque le liseré d'accent quand un seul panneau est visible.
    var showsActiveIndicator = true { didSet { updateActiveAppearance() } }

    var tab: TabState { tabs[selectedTabIndex] }
    var currentURL: URL { tab.url }
    var state: PanelState {
        // Les onglets SFTP ne sont pas restaurés (ils demanderaient une connexion au lancement).
        let local = tabs.filter { !$0.url.isRemote }
        return PanelState(tabs: local.map(\.url.path), selectedTab: local.firstIndex { $0 === tab } ?? 0,
                          viewMode: viewMode.rawValue, iconSize: Double(iconSize),
                          sortKey: sortDescriptor.key, sortAscending: sortDescriptor.ascending, listScale: Double(listScale),
                          tabColors: local.map { $0.color?.rawValue ?? -1 }, grouping: grouping.rawValue)
    }

    /// Indices sélectionnés, quel que soit le mode d'affichage.
    var selectionIndexes: IndexSet {
        switch viewMode {
        case .icons: IndexSet(collectionView.selectionIndexPaths.map(\.item))
        case .columns: browserSelection
        case .list, .details: isGrouped ? IndexSet(tableView.selectedRowIndexes.compactMap(itemIndex(forRow:))) : tableView.selectedRowIndexes
        }
    }

    /// La vue qui reçoit le clavier dans le mode courant.
    var focusView: NSView {
        if isShowingDiskUsage { return diskUsageView.focusView }
        return switch viewMode {
        case .icons: collectionView
        case .columns: browser
        case .list, .details: tableView
        }
    }

    var selectedItems: [FileItem] { selectionIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil } }
    var selectedURLs: [URL] { selectedItems.map(\.url) }

    init(index: Int, state: PanelState?) {
        self.index = index
        let colors = state?.tabColors ?? []
        let restored: [TabState] = (state?.tabs ?? []).enumerated().compactMap { index, path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard url.isExistingDirectory else { return nil }
            let tab = TabState(url: url)
            tab.color = colors.indices.contains(index) ? TabColor(rawValue: colors[index]) : nil
            return tab
        }
        tabs = restored.isEmpty ? [TabState(url: FileManager.default.homeDirectoryForCurrentUser)] : restored
        selectedTabIndex = min(max(0, state?.selectedTab ?? 0), tabs.count - 1)
        viewMode = state?.viewMode.flatMap(PanelViewMode.init(rawValue:)) ?? .details
        iconSize = CGFloat(state?.iconSize ?? 80)
        listScale = CGFloat(state?.listScale ?? 1)
        grouping = PanelGrouping(rawValue: state?.grouping ?? 0) ?? .none
        if let key = state?.sortKey { sortDescriptor = NSSortDescriptor(key: key, ascending: state?.sortAscending ?? true) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Vue

    override func loadView() {
        let root = NSView()

        accentLine.wantsLayer = true

        breadcrumb.onNavigate = { [weak self] url in self?.navigate(to: url) }
        let titles = NSStackView(views: [breadcrumb])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        titles.setHuggingPriority(.defaultLow, for: .horizontal)

        gitLabel.font = .systemFont(ofSize: 11, weight: .medium)
        gitLabel.lineBreakMode = .byTruncatingTail
        // Le fil d'Ariane se tronque avant l'indicateur Git.
        gitLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gitLabel.isHidden = true
        configureNavigationControl()
        let header = NSStackView(views: [titles, gitLabel, diskUsageToggle, navigationControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        configureTable()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        configureGrid()
        gridScrollView.documentView = collectionView
        gridScrollView.hasVerticalScroller = true
        gridScrollView.autohidesScrollers = true
        gridScrollView.borderType = .noBorder
        gridScrollView.drawsBackground = false

        let separator = NSBox()
        separator.boxType = .separator

        searchBar.isHidden = true
        configureBrowser()
        diskUsageView.isHidden = true
        statusBar.panel = self
        for view in [accentLine, tabBar, header, searchBar, separator, scrollView, gridScrollView, browser, diskUsageView, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        searchBarHeight = searchBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            accentLine.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            accentLine.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            accentLine.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            accentLine.heightAnchor.constraint(equalToConstant: 2.5),

            tabBar.topAnchor.constraint(equalTo: accentLine.bottomAnchor, constant: 2),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBarHeight,

            header.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            searchBar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            searchBarHeight,

            separator.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            gridScrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            gridScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            gridScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            gridScrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            browser.topAnchor.constraint(equalTo: separator.bottomAnchor),
            browser.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            browser.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            diskUsageView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            diskUsageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            diskUsageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            diskUsageView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        // Fonds du thème de couleurs : bande de barre d'outils, en-tête, liste.
        ThemeBackgroundView.install(.toolbar, in: root, bottom: root.safeAreaLayoutGuide.topAnchor)
        ThemeBackgroundView.install(.header, in: root, top: root.safeAreaLayoutGuide.topAnchor, bottom: separator.bottomAnchor)
        ThemeBackgroundView.install(.panel, in: root, top: separator.bottomAnchor)
        view = root
    }

    private func configureTable() {
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat, CGFloat)] = [
            (.name, L("Nom"), 260, 120), (.size, L("Taille"), 72, 50), (.date, L("Modifié le"), 128, 70), (.kind, L("Type"), 110, 50),
        ]
        for (identifier, title, width, minWidth) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = minWidth
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier.rawValue, ascending: true)
            if identifier == .size { column.headerCell.alignment = .right }
            tableView.addTableColumn(column)
        }
        addMetadataColumns()
        tableView.style = .inset
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 10, height: 0)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.sortDescriptors = [sortDescriptor]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.onFocus = { [weak self] in self?.activate(focusTable: false) }
        tableView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.onZoom = { [weak self] factor in self?.zoom(by: factor) }
        tableView.onHover = { [weak self] row, previous in self?.hoverEffect(row, previous) }
        tableView.onRowClick = { [weak self] row, point in self?.clickEffect(row, point) }
        tableView.contextMenuProvider = { [weak self] in self?.contextMenu() }
        tableView.onSlowClick = { [weak self] row in
            guard let self, renamingRow == nil, let index = itemIndex(forRow: row), selectionIndexes == [index] else { return }
            renameSelection(nil)
        }
    }

    private func configureGrid() {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView.collectionViewLayout = layout
        collectionView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: true)
        collectionView.onFocus = { [weak self] in
            self?.activate(focusTable: false)
            self?.collectionView.refreshSelectionStyle()
        }
        collectionView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        collectionView.onZoom = { [weak self] factor in self?.zoom(by: factor) }
        collectionView.contextMenuProvider = { [weak self] in self?.contextMenu() }
        collectionView.onDoubleClick = { [weak self] in self?.openSelection(nil) }
    }

    // MARK: Modes d'affichage

    /// Bascule entre icônes, liste et liste détaillée en conservant la sélection.
    func setViewMode(_ mode: PanelViewMode) {
        if mode == .columns, currentURL.isRemote { NSSound.beep(); return }
        let hadFocus = view.window?.firstResponder === focusView
        let selection = selectedURLs
        if isShowingDiskUsage {
            isShowingDiskUsage = false
            diskUsageView.stop()
        }
        viewMode = mode
        if mode == .columns, isFlatView { isFlatView = false; reload() }
        // Les dossiers dépliés n'existent qu'en liste : on recharge à plat (ou de nouveau déplié).
        if !expandedPaths.isEmpty { reload() }
        applyViewMode()
        if mode == .columns { syncBrowserToCurrentFolder() }
        if grouping != .none, !isShowingSearchResults, mode != .list, mode != .details { items = Self.sorted(items, by: sortDescriptor) }
        reloadViews()
        let paths = Set(selection.map(\.normalizedPath))
        setSelection(IndexSet(items.indices.filter { paths.contains(items[$0].url.normalizedPath) }), scroll: true)
        if hadFocus || isActive { view.window?.makeFirstResponder(focusView) }
        host?.panelDidChangeDirectory(self)
    }

    func applyViewMode() {
        scrollView.isHidden = isShowingDiskUsage || viewMode == .icons || viewMode == .columns
        gridScrollView.isHidden = isShowingDiskUsage || viewMode != .icons
        browser.isHidden = isShowingDiskUsage || viewMode != .columns
        diskUsageView.isHidden = !isShowingDiskUsage
        let compact = viewMode == .list
        let extra = MetadataColumn.visible
        for column in tableView.tableColumns where column.identifier != .name {
            column.isHidden = compact || MetadataColumn(identifier: column.identifier).map { !extra.contains($0) } ?? false
        }
        tableView.rowHeight = ((compact ? 22 : 24) * listScale).rounded()
        updateGridItemSize()
        postStatusChange()
    }

    private func updateGridItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = NSSize(width: iconSize + 40, height: iconSize + 50)
    }

    func setIconSize(_ size: CGFloat) {
        let newSize = min(max(size.rounded(), 32), 256)
        guard newSize != iconSize else { return }
        iconSize = newSize
        updateGridItemSize()
        postStatusChange()
        // Seules les vignettes visibles sont reconfigurées (la mise en page suit seule).
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems())
    }

    /// Zoom des listes : hauteur des lignes, taille du texte et des icônes.
    func setListScale(_ scale: CGFloat) {
        let newScale = min(max((scale * 20).rounded() / 20, 0.75), 2)
        guard newScale != listScale else { return }
        listScale = newScale
        let compact = viewMode == .list
        tableView.rowHeight = ((compact ? 22 : 24) * listScale).rounded()
        // Le rechargement ne doit pas perdre la sélection.
        let selection = tableView.selectedRowIndexes
        tableView.reloadData()
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        postStatusChange()
    }

    /// ⌘ + molette, pincement, ⌘+ / ⌘− : agrandit ou réduit selon le mode d'affichage.
    func zoom(by factor: CGFloat) {
        if viewMode == .icons { setIconSize(iconSize * factor) } else { setListScale(listScale * factor) }
    }

    @objc func resetZoom(_ sender: Any?) {
        if viewMode == .icons { setIconSize(80) } else { setListScale(1) }
    }

    /// La sélection des colonnes a changé de dossier : met à jour le panneau sans recharger les colonnes.
    func followBrowserFolder() {
        watcher.watch(currentURL)
        breadcrumb.show(currentURL)
        updateTabBar()
        RecentFolders.record(currentURL)
        folderSizeGeneration += 1
        folderSizes = [:]
        computingFolders = []
        freeSpace = Format.freeSpace(at: currentURL)
        host?.panelDidChangeDirectory(self)
    }

    @objc func showAsIcons(_ sender: Any?) { setViewMode(.icons) }
    @objc func showAsList(_ sender: Any?) { setViewMode(.list) }
    @objc func showAsDetails(_ sender: Any?) { setViewMode(.details) }
    @objc func increaseIconSize(_ sender: Any?) { zoom(by: viewMode == .icons ? 1.25 : 1.1) }
    @objc func decreaseIconSize(_ sender: Any?) { zoom(by: viewMode == .icons ? 1 / 1.25 : 1 / 1.1) }

    @objc func sortBy(_ sender: NSMenuItem) {
        let keys = ["name", "size", "date", "kind"]
        guard keys.indices.contains(sender.tag) else { return }
        let key = keys[sender.tag]
        let ascending = sortDescriptor.key == key ? !sortDescriptor.ascending : (key == "name" || key == "kind")
        tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        if viewMode == .icons { tableView(tableView, sortDescriptorsDidChange: []) }
    }

    func reloadViews() {
        rebuildGroups()
        tableView.reloadData()
        collectionView.reloadData()
        reloadBrowserColumn()
    }

    func setSelection(_ rows: IndexSet, scroll: Bool) {
        let valid = rows.filteredIndexSet { items.indices.contains($0) }
        tableView.selectRowIndexes(tableRows(forItems: valid), byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(valid.map { IndexPath(item: $0, section: 0) })
        selectInBrowser(valid)
        if let first = valid.first {
            tableView.scrollRowToVisible(tableRow(forItem: first))
            collectionView.scrollToItems(at: [IndexPath(item: first, section: 0)], scrollPosition: .nearestHorizontalEdge)
        } else if scroll, !items.isEmpty {
            tableView.scrollRowToVisible(0)
            collectionView.scroll(.zero)
        }
        selectionDidChange()
    }

    func selectionDidChange() {
        updateInfo()
        refreshQuickLook()
        host?.panelSelectionDidChange(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.onSelect = { [weak self] index in self?.selectTab(index); self?.activate() }
        tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabBar.onSetColor = { [weak self] index, color in self?.setTabColor(color, at: index) }
        tabBar.onAdd = { [weak self] in self?.newTab(nil) }
        searchBar.onChange = { [weak self] text, scope in self?.searchChanged(text, scope: scope) }
        searchBar.onClose = { [weak self] in self?.endSearch() }
        searchBar.onMoveDown = { [weak self] in
            guard let self else { return }
            view.window?.makeFirstResponder(focusView)
            if selectionIndexes.isEmpty, !items.isEmpty { setSelection([0], scroll: true) }
        }
        watcher.onChange = { [weak self] in self?.reload() }
        configureDiskUsage()

        let center = NotificationCenter.default
        center.addObserver(forName: Preferences.showHiddenChanged, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        center.addObserver(forName: IconTheme.changed, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        center.addObserver(forName: GitService.enabledChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshGit() }
        center.addObserver(forName: ColorTheme.changed, object: nil, queue: .main) { [weak self] _ in self?.themeDidChange() }
        center.addObserver(forName: FileClipboard.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            cutPaths = FileClipboard.cutPaths
            let selection = selectionIndexes
            reloadViews()
            setSelection(selection, scroll: false)
        }
        applyViewMode()
        updateActiveAppearance()
        showCurrentTab()
    }

    private func updateActiveAppearance() {
        guard isViewLoaded else { return }
        let visible = isActive && showsActiveIndicator
        accentLine.layer?.cornerRadius = 1.25
        let wasVisible = accentLine.layer?.backgroundColor.map { $0.alpha > 0 } ?? false
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            accentLine.layer?.backgroundColor = visible ? Theme.accent.cgColor : NSColor.clear.cgColor
        }
        if visible != wasVisible { Effects.accent(accentLine, visible: visible) }
        Effects.dim(view, active: isActive || !showsActiveIndicator)
        breadcrumb.isActive = isActive || !showsActiveIndicator
        updateTabBar()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Les colonnes suivent la largeur du panneau (pas de défilement horizontal).
        let width = scrollView.contentSize.width
        if width > 0, abs(tableView.frame.width - width) > 0.5 {
            tableView.frame.size.width = width
            tableView.sizeToFit()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateActiveAppearance()
    }

    // MARK: Activation

    func activate(focusTable: Bool = true) {
        host?.panelDidBecomeActive(self)
        if focusTable, view.window?.firstResponder !== focusView {
            view.window?.makeFirstResponder(focusView)
        }
    }

    // MARK: Chargement

    private func showCurrentTab() {
        isFlatView = false
        resetOutline()
        // Un filtre épinglé suit le panneau de dossier en dossier.
        if isSearching, !searchBar.isPinned { endSearch(reloadListing: false) }
        // Pas de vue en colonnes sur un serveur SFTP.
        if viewMode == .columns, currentURL.isRemote { viewMode = .details; applyViewMode() }
        if viewMode == .columns { syncBrowserToCurrentFolder() }
        if isShown, ArchiveBrowser.archive(containing: currentURL) == nil { RecentFolders.record(currentURL) }
        folderSizeGeneration += 1
        folderSizes = [:]
        computingFolders = []
        if currentURL.isRemote || !isShown { watcher.stop() } else { watcher.watch(currentURL) }
        breadcrumb.show(currentURL)
        updateTabBar()
        updateNavigationControl()
        reload(selecting: tab.selection, scrollToSelection: true)
        if isShowingDiskUsage { showDiskUsage() }
        host?.panelDidChangeDirectory(self)
    }

    private func configureNavigationControl() {
        navigationControl.segmentCount = 2
        navigationControl.trackingMode = .momentary
        navigationControl.segmentStyle = .separated
        navigationControl.controlSize = .small
        navigationControl.target = self
        navigationControl.action = #selector(navigationClicked(_:))
        for (segment, symbol, label, provider) in [(0, "chevron.left", L("Précédent (⌘[)"), backMenu), (1, "chevron.right", L("Suivant (⌘])"), forwardMenu)] {
            navigationControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: segment)
            navigationControl.setWidth(24, forSegment: segment)
            navigationControl.setToolTip(label + " — " + L("maintenir le clic pour tout l’historique de l’onglet"), forSegment: segment)
            let menu = NSMenu()
            menu.delegate = provider
            navigationControl.setMenu(menu, forSegment: segment)
            navigationControl.setShowsMenuIndicator(false, forSegment: segment)
        }
        navigationControl.setContentHuggingPriority(.required, for: .horizontal)
        navigationControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        diskUsageToggle.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: L("Occupation du disque"))
        diskUsageToggle.setButtonType(.pushOnPushOff)
        diskUsageToggle.bezelStyle = .accessoryBarAction
        diskUsageToggle.controlSize = .small
        diskUsageToggle.target = self
        diskUsageToggle.action = #selector(diskUsageToggleClicked(_:))
        diskUsageToggle.toolTip = L("Occupation du disque (⌘5) — cliquer de nouveau pour revenir aux fichiers")
        diskUsageToggle.setContentHuggingPriority(.required, for: .horizontal)
        diskUsageToggle.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @objc private func diskUsageToggleClicked(_ sender: NSButton) {
        activate(focusTable: false)
        toggleDiskUsage(sender)
    }

    @objc private func navigationClicked(_ sender: NSSegmentedControl) {
        activate(focusTable: true)
        if sender.selectedSegment == 0 { goBack(nil) } else { goForward(nil) }
    }

    func updateNavigationControl() {
        navigationControl.setEnabled(!tab.back.isEmpty, forSegment: 0)
        navigationControl.setEnabled(!tab.forward.isEmpty, forSegment: 1)
        diskUsageToggle.state = isShowingDiskUsage ? .on : .off
        diskUsageToggle.isEnabled = !currentURL.isRemote
    }

    func updateTabBar() {
        let multiple = tabs.count > 1
        tabBar.isHidden = !multiple
        tabBarHeight.constant = multiple ? 28 : 0
        if multiple {
            tabBar.update(tabs: tabs.map { (BreadcrumbView.displayName($0.url), $0.url.path, $0.color) },
                          selected: selectedTabIndex, active: isActive)
        }
    }

    /// Recharge le dossier courant en arrière-plan en conservant (ou imposant) la sélection.
    func reload(selecting urls: [URL]? = nil, scrollToSelection: Bool = false, fallbackRow: Int? = nil, completion: (() -> Void)? = nil) {
        if renamingRow != nil { reloadDeferred = true; return }
        // Les résultats d'une recherche restent affichés jusqu'à sa fermeture.
        if isShowingSearchResults { completion?(); return }
        let url = currentURL
        let showHidden = Preferences.showHiddenFiles
        let wanted = urls ?? selectedURLs
        let descriptor = sortDescriptor
        let flat = isFlatView && !url.isRemote
        let expanded = canExpandFolders ? expandedPaths : []
        loadGeneration += 1
        let generation = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            // Lecture et tri hors du fil principal.
            let result = Result {
                Self.expandTree(Self.sorted(flat ? FileItem.flatContents(of: url, showHidden: showHidden) : try FileItem.contents(at: url, showHidden: showHidden),
                                            by: descriptor),
                                expanded: expanded, showHidden: showHidden, by: descriptor)
            }
            let free = url.isRemote ? url.host.map { L("connecté à \($0)") } : Format.freeSpace(at: url)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == loadGeneration, url.isSameLocation(as: currentURL) else { return }
                apply(result, freeSpace: free, selecting: wanted, scroll: scrollToSelection, fallbackRow: fallbackRow)
                completion?()
            }
        }
    }

    private func apply(_ result: Result<[FileItem], Error>, freeSpace: String?, selecting wanted: [URL], scroll: Bool, fallbackRow: Int?) {
        switch result {
        case .success(let list):
            allItems = list
            for item in list where item.isNavigableDirectory { item.folderSize = folderSizes[item.url.normalizedPath] }
            let filter = isSearching && searchBar.scope == .folder ? Self.nameMatcher(for: searchBar.field.stringValue.trimmingCharacters(in: .whitespaces)) : nil
            items = filter.map { match in list.filter { item in match(item.name) { item.finderTags } } } ?? list
            updateFilterCount()
            loadError = nil
        case .failure(let error):
            if !currentURL.isRemote, !currentURL.isExistingDirectory {
                // Le dossier a disparu (suppression, éjection) : on remonte au parent existant.
                let parent = URL(fileURLWithPath: currentURL.ancestorPaths.first { URL(fileURLWithPath: $0).isExistingDirectory } ?? "/")
                tab.url = parent.standardizedFileURL
                showCurrentTab()
                return
            }
            items = []
            allItems = []
            loadError = (error as NSError).code == NSFileReadNoPermissionError
                ? L("Accès refusé") : error.localizedDescription
            if currentURL.isRemote {
                NotificationCenter.default.post(name: SFTPManager.sessionsChanged, object: nil)
            }
        }
        self.freeSpace = freeSpace
        cutPaths = FileClipboard.cutPaths
        reloadViews()
        watchExpandedFolders()
        if let direction = pendingTransition {
            pendingTransition = nil
            playNavigationAnimation(direction)
        }

        let paths = Set(wanted.map(\.normalizedPath))
        var rows = IndexSet(items.indices.filter { paths.contains(items[$0].url.normalizedPath) })
        if rows.isEmpty, let fallbackRow, !items.isEmpty { rows = [min(fallbackRow, items.count - 1)] }
        setSelection(rows, scroll: scroll)
        refreshGit()
    }

    static func sorted(_ list: [FileItem], by descriptor: NSSortDescriptor) -> [FileItem] {
        let key = descriptor.key ?? "name"
        let ascending = descriptor.ascending
        return list.sorted { a, b in
            if a.isNavigableDirectory != b.isNavigableDirectory { return a.isNavigableDirectory }
            var result: ComparisonResult
            switch key {
            case "size": result = Self.compare(a.effectiveSize ?? -1, b.effectiveSize ?? -1)
            case "date": result = Self.compare(a.modificationDate ?? .distantPast, b.modificationDate ?? .distantPast)
            case "kind": result = a.kind.localizedStandardCompare(b.kind)
            default: result = .orderedSame
            }
            if result == .orderedSame { result = a.name.localizedStandardCompare(b.name) }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    func updateInfo() {
        defer { postStatusChange() }
        if let loadError {
            infoText = "⚠︎ \(loadError)"
            return
        }
        let selection = selectedItems
        var text: String
        if isShowingSearchResults {
            text = items.count <= 1 ? L("\(items.count) résultat") : L("\(items.count) résultats")
            if searchResultsTruncated { text += " " + L("(limité à 2 000)") }
            if !selection.isEmpty { text += " — " + (selection.count > 1 ? L("\(selection.count) sélectionnés") : L("\(selection.count) sélectionné")) }
            infoText = text
            return
        }
        if isFlatView {
            text = items.count <= 1 ? L("Vue à plat : \(items.count) fichier") : L("Vue à plat : \(items.count) fichiers")
            if items.count >= FileItem.flatLimit { text += " " + L("(limité à 10 000)") }
            if !selection.isEmpty {
                let bytes = selection.compactMap(\.effectiveSize).reduce(0, +)
                let size = Format.size(bytes)
                text += " — " + (selection.count > 1 ? L("\(selection.count) sélectionnés (\(size))") : L("\(selection.count) sélectionné (\(size))"))
            }
            infoText = text
            return
        }
        if let (archive, _) = ArchiveBrowser.archive(containing: currentURL) {
            // Pas d'espace libre ici : on rappelle que le contenu n'est qu'une copie de l'archive.
            text = selection.isEmpty ? Format.itemCount(items.count)
                : selection.count > 1 ? L("\(selection.count) sur \(items.count) sélectionnés") : L("\(selection.count) sur \(items.count) sélectionné")
            infoText = text + " — " + L("dans « \(archive.lastPathComponent) », modifications non enregistrées dans l’archive")
            return
        }
        if selection.isEmpty {
            text = Format.itemCount(items.count)
        } else {
            let bytes = selection.compactMap(\.effectiveSize).reduce(0, +)
            let size = Format.size(bytes)
            text = selection.count > 1 ? L("\(selection.count) sur \(items.count) sélectionnés (\(size))") : L("\(selection.count) sur \(items.count) sélectionné (\(size))")
            if selection.count > 1 { text += " — " + Self.describeKinds(selection) }
        }
        if let freeSpace { text += ", \(freeSpace)" }
        infoText = text
    }

    // MARK: Thème de couleurs

    private func themeDidChange() {
        updateActiveAppearance()
        breadcrumb.show(currentURL)
        let selection = selectionIndexes
        reloadViews()
        setSelection(selection, scroll: false)
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
    }

    // MARK: Git

    /// Recalcule l'état Git du dossier courant et des dépôts qu'il contient (en arrière-plan).
    func refreshGit() {
        gitGeneration += 1
        let generation = gitGeneration
        guard GitService.isEnabled, !currentURL.isRemote, isShown else {
            if gitStatus != nil || !gitSummaries.isEmpty || gitWatcher != nil {
                gitStatus = nil
                gitSummaries = [:]
                gitWatcher = nil
                redrawGit()
            }
            return
        }
        let url = currentURL
        let folders = items.filter(\.isNavigableDirectory).map(\.url)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let service = GitService.shared
            guard service.isAvailable else { return }
            let root = service.repositoryRoot(for: url)
            let status = root.flatMap { service.status(ofRepository: $0) }
            let current = url.resolvingSymlinksInPath().standardizedFileURL.path
            let relative = root.map { current == $0.path ? "" : String(current.dropFirst($0.path.count + 1)) } ?? ""
            let repositories = folders.filter(GitService.isRepository)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == gitGeneration else { return }
                gitStatus = status
                gitRelativeDirectory = relative
                // Un seul flux FSEvents : la racine du dépôt, ou le dossier courant s'il contient des dépôts.
                let watched = root ?? (repositories.isEmpty ? nil : url)
                if gitWatcher?.root.path != watched?.path {
                    gitWatcher = watched.map { RepositoryWatcher(root: $0) { [weak self] paths in self?.gitPathsChanged(paths) } }
                }
                redrawGit()
                service.summaries(of: repositories) { [weak self] summaries in
                    guard let self, generation == gitGeneration else { return }
                    gitSummaries = summaries
                    redrawGit()
                }
            }
        }
    }

    /// Dans un dossier qui contient des dépôts, seuls les dépôts touchés sont recalculés.
    private func gitPathsChanged(_ paths: [String]) {
        guard gitStatus == nil, !gitSummaries.isEmpty else { refreshGit(); return }
        let repositories = items.filter(\.isNavigableDirectory).map(\.url).filter { url in
            gitSummaries[url.standardizedFileURL.path] != nil || GitService.isRepository(url)
        }
        let touched = repositories.filter { repository in
            let root = repository.resolvingSymlinksInPath().path + "/"
            return paths.contains { $0.hasPrefix(root) || $0 + "/" == root }
        }
        guard !touched.isEmpty else { return }
        let generation = gitGeneration
        GitService.shared.summaries(of: touched) { [weak self] summaries in
            guard let self, generation == gitGeneration else { return }
            gitSummaries.merge(summaries) { _, new in new }
            redrawGit()
        }
    }

    /// État Git d'un élément quelconque du dépôt courant (vue en colonnes : éléments d'autres dossiers).
    func gitState(at url: URL, isDirectory: Bool) -> GitFileState? {
        guard let gitStatus, url.lastPathComponent != ".git" else { return nil }
        let root = gitStatus.root.path, path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return gitStatus.state(forRelativePath: String(path.dropFirst(root.count + 1)), isDirectory: isDirectory)
    }

    private func gitState(for item: FileItem) -> GitFileState? {
        guard let gitStatus, item.name != ".git" else { return nil }
        // Élément d'un dossier déplié : son chemin ne part pas du dossier courant.
        if item.url.deletingLastPathComponent().standardizedFileURL.path != currentURL.standardizedFileURL.path {
            return gitState(at: item.url, isDirectory: item.isNavigableDirectory)
        }
        let path = gitRelativeDirectory.isEmpty ? item.name : gitRelativeDirectory + "/" + item.name
        return gitStatus.state(forRelativePath: path, isDirectory: item.isNavigableDirectory)
    }

    /// Indicateur d'un dossier dépôt : ● modifications, ↑ à pousser, ↓ à tirer (✓ s'il est à jour).
    private func repositoryBadge(for item: FileItem) -> NSAttributedString? {
        guard item.isNavigableDirectory, let summary = gitSummaries[item.url.standardizedFileURL.path] else { return nil }
        return Self.badge(for: summary, includeBranch: false)
    }

    static func badge(for summary: GitSummary, includeBranch: Bool) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let text = NSMutableAttributedString()
        func add(_ string: String, _ color: NSColor) {
            if text.length > 0 { text.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            text.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
        }
        if includeBranch, let branch = summary.branch { add("⎇ \(branch)", .secondaryLabelColor) }
        if summary.changes > 0 { add("● \(summary.changes)", GitFileState.modified.color) }
        if summary.ahead > 0 { add("↑\(summary.ahead)", .systemBlue) }
        if summary.behind > 0 { add("↓\(summary.behind)", .systemPurple) }
        if summary.isClean { add("✓", GitFileState.added.color) }
        if includeBranch, !summary.hasUpstream { add(L("sans branche distante"), .tertiaryLabelColor) }
        return text
    }

    private func redrawGit() {
        if let summary = gitStatus?.summary {
            gitLabel.attributedStringValue = Self.badge(for: summary, includeBranch: true)
            let root = gitStatus?.root.path ?? ""
            gitLabel.toolTip = L("Dépôt Git : \(root)\n● fichiers modifiés · ↑ commits à pousser · ↓ commits à tirer (depuis le dernier fetch)")
            gitLabel.isHidden = false
        } else {
            gitLabel.isHidden = true
        }
        let selection = selectionIndexes
        // Seules les lignes visibles sont redessinées ; les autres le seront en défilant.
        let visible = tableView.rows(in: tableView.visibleRect)
        if visible.length > 0 {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                                 columnIndexes: IndexSet(integer: max(0, tableView.column(withIdentifier: .name))))
        }
        if viewMode == .icons {
            collectionView.reloadData()
            collectionView.selectionIndexPaths = Set(selection.map { IndexPath(item: $0, section: 0) })
        }
        if viewMode == .columns { refreshBrowserDecorations() }
    }

    // MARK: Navigation

    func navigate(to url: URL, select: URL? = nil) {
        let url = url.isRemote ? url.standardized : url.standardizedFileURL
        if url.isSameLocation(as: currentURL) {
            if let select { reload(selecting: [select]) }
            return
        }
        tab.back.append(currentURL)
        if tab.back.count > 200 { tab.back.removeFirst() }
        tab.forward.removeAll()
        let old = currentURL
        tab.url = url
        tab.selection = select.map { [$0] } ?? []
        pendingTransition = .between(old, url)
        showCurrentTab()
        host?.panel(self, didMoveFrom: old, to: url)
    }

    @objc func goBack(_ sender: Any?) {
        guard let previous = tab.back.popLast() else { return }
        let old = currentURL
        tab.forward.append(currentURL)
        tab.selection = [currentURL]
        tab.url = previous
        pendingTransition = .backward
        showCurrentTab()
        host?.panel(self, didMoveFrom: old, to: previous)
    }

    @objc func goForward(_ sender: Any?) {
        guard let next = tab.forward.popLast() else { return }
        let old = currentURL
        tab.back.append(currentURL)
        tab.selection = []
        tab.url = next
        pendingTransition = .forward
        showCurrentTab()
        host?.panel(self, didMoveFrom: old, to: next)
    }

    @objc func goUp(_ sender: Any?) {
        guard currentURL.path != "/", !currentURL.path.isEmpty else { return }
        // Depuis la racine d'une archive, on revient au dossier qui la contient.
        if let (archive, root) = ArchiveBrowser.archive(containing: currentURL), root.isSameLocation(as: currentURL) {
            navigate(to: archive.deletingLastPathComponent(), select: archive)
            return
        }
        navigate(to: currentURL.deletingLastPathComponent(), select: currentURL)
    }

    @objc func goHome(_ sender: Any?) { navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
    @objc func goDesktop(_ sender: Any?) { go(to: .desktopDirectory) }
    @objc func goDocuments(_ sender: Any?) { go(to: .documentDirectory) }
    @objc func goDownloads(_ sender: Any?) { go(to: .downloadsDirectory) }
    @objc func goApplications(_ sender: Any?) { navigate(to: URL(fileURLWithPath: "/Applications")) }
    @objc func goComputer(_ sender: Any?) { navigate(to: URL(fileURLWithPath: "/Volumes")) }

    private func go(to directory: FileManager.SearchPathDirectory) {
        if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first { navigate(to: url) }
    }

    @objc func goToFolder(_ sender: Any?) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = L("Aller au dossier")
        alert.informativeText = L("Saisissez un chemin (« ~ » désigne votre dossier de départ).")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = currentURL.isRemote ? currentURL.path : (currentURL.path as NSString).abbreviatingWithTildeInPath
        alert.accessoryView = field
        alert.addButton(withTitle: L("Aller"))
        alert.addButton(withTitle: L("Annuler"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("sftp://"), let url = URL(string: text) {
                navigate(to: url)
                return
            }
            if currentURL.isRemote, !text.hasPrefix("~") {
                let base = currentURL.path.hasSuffix("/") ? currentURL.path : currentURL.path + "/"
                let path = text.hasPrefix("/") ? text : base + text
                navigate(to: SFTPEndpoint(url: currentURL)!.url(path: (path as NSString).standardizingPath))
                return
            }
            let path = (text as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path, relativeTo: currentURL.isRemote ? nil : currentURL).absoluteURL.standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue { navigate(to: url) } else { navigate(to: url.deletingLastPathComponent(), select: url) }
            } else {
                NSSound.beep()
            }
        }
    }

    @objc func refresh(_ sender: Any?) { reload() }

    @objc func syncOtherPanel(_ sender: Any?) {
        host?.targetPanels(for: self).first?.navigate(to: currentURL)
    }

    // MARK: Onglets

    @objc func newTab(_ sender: Any?) { openTab(currentURL) }

    func openTab(_ url: URL) {
        tab.selection = selectedURLs
        tabs.insert(TabState(url: url), at: selectedTabIndex + 1)
        selectedTabIndex += 1
        showCurrentTab()
        activate()
    }

    @objc func closeTab(_ sender: Any?) { closeTab(at: selectedTabIndex) }

    func closeTab(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        let wasCurrent = index == selectedTabIndex
        tabs.remove(at: index)
        if index < selectedTabIndex || selectedTabIndex >= tabs.count { selectedTabIndex -= 1 }
        if wasCurrent { showCurrentTab() } else { updateTabBar() }
    }

    func selectTab(_ index: Int) {
        guard index != selectedTabIndex, tabs.indices.contains(index) else { return }
        tab.selection = selectedURLs
        selectedTabIndex = index
        pendingTransition = .other
        showCurrentTab()
    }

    func setTabColor(_ color: TabColor?, at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].color = color
        updateTabBar()
    }

    @objc func nextTab(_ sender: Any?) { selectTab((selectedTabIndex + 1) % tabs.count) }
    @objc func previousTab(_ sender: Any?) { selectTab((selectedTabIndex + tabs.count - 1) % tabs.count) }

    // MARK: Ouverture

    @objc private func tableDoubleClicked(_ sender: Any?) {
        guard itemIndex(forRow: tableView.clickedRow) != nil else { return }
        openSelection(nil)
    }

    @objc func openSelection(_ sender: Any?) {
        let selection = selectedItems
        guard !selection.isEmpty else { return }
        if currentURL.isRemote {
            openRemote(selection)
            return
        }
        if let folder = selection.first(where: \.isNavigableDirectory), selection.count == 1 {
            navigate(to: folder.url)
            return
        }
        // Fichier chiffré (.aes256, .chacha20) : proposer de le déchiffrer.
        if !encryptedFiles.isEmpty, encryptedFiles.count == selection.count {
            decryptFiles(nil)
            return
        }
        // « nom.001 » : proposer de réassembler les morceaux.
        if joinCandidate != nil {
            joinFiles(nil)
            return
        }
        // Une archive seule s'ouvre comme un dossier (« Ouvrir avec » garde l'utilitaire d'archive).
        if selection.count == 1, ArchiveBrowser.canBrowse(selection[0].url) {
            let archive = selection[0].url
            ArchiveBrowser.open(archive) { [weak self] root in
                if let root { self?.navigate(to: root) }
            }
            return
        }
        let files = selection.filter { !$0.isNavigableDirectory }.map(\.url)
        for url in files { NSWorkspace.shared.open(url) }
        for folder in selection.filter(\.isNavigableDirectory) { openTab(folder.url) }
    }

    /// Dossiers : navigation ; liens symboliques : vérifiés sur le serveur ; fichiers : téléchargés puis ouverts.
    private func openRemote(_ selection: [FileItem]) {
        if selection.count == 1, selection[0].isDirectory {
            navigate(to: selection[0].url)
            return
        }
        let links = selection.filter(\.isSymlink)
        let files = selection.filter { !$0.isDirectory && !$0.isSymlink }.map(\.url)
        if !files.isEmpty { FileOperationCenter.shared.openRemote(files) }
        guard !links.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let resolved = links.map { link in
                (link.url, (try? SFTPManager.shared.session(for: link.url).isDirectory(link.url.path)) ?? false)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let folders = resolved.filter(\.1).map(\.0)
                let others = resolved.filter { !$0.1 }.map(\.0)
                if folders.count == 1, selection.count == 1 { navigate(to: folders[0]) } else { folders.forEach(openTab) }
                if !others.isEmpty { FileOperationCenter.shared.openRemote(others) }
            }
        }
    }

    @objc func openInNewTab(_ sender: Any?) {
        let folders = selectedItems.filter(\.isNavigableDirectory)
        if folders.isEmpty { newTab(nil) } else { folders.forEach { openTab($0.url) } }
    }

    @objc func showPackageContents(_ sender: Any?) {
        guard let item = selectedItems.first, item.isPackage else { return }
        navigate(to: item.url)
    }

    @objc func openWithApplication(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(selectedURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func revealInFinder(_ sender: Any?) {
        let urls = selectedURLs
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [currentURL] : urls)
    }

    @objc func openInTerminal(_ sender: Any?) {
        let folder = selectedItems.count == 1 && selectedItems[0].isNavigableDirectory ? selectedItems[0].url : currentURL
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func addToFavorites(_ sender: Any?) {
        let folders = selectedItems.filter(\.isNavigableDirectory).map(\.url)
        let additions = folders.isEmpty ? [currentURL] : folders
        Preferences.addFavorites(additions)
    }

    // MARK: Presse-papiers

    @objc func copy(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        FileClipboard.write(urls, cut: false)
    }

    @objc func cut(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        FileClipboard.write(urls, cut: true)
    }

    @objc func paste(_ sender: Any?) {
        let urls = FileClipboard.fileURLs()
        guard !urls.isEmpty else { return }
        let isCut = FileClipboard.isCut
        transfer(isCut ? .move : .copy, urls, to: currentURL)
        if isCut { FileClipboard.didPasteCut() }
    }

    /// ⌥⌘V : déplace ici les fichiers copiés (comme le Finder).
    @objc func pasteMove(_ sender: Any?) {
        let urls = FileClipboard.fileURLs()
        guard !urls.isEmpty else { return }
        transfer(.move, urls, to: currentURL)
        FileClipboard.didPasteCut()
    }

    @objc func copyPath(_ sender: Any?) {
        let urls = selectedURLs
        let targets = urls.isEmpty ? [currentURL] : urls
        if currentURL.isRemote {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(targets.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        } else {
            FileClipboard.writePaths(targets)
        }
    }

    @objc func duplicate(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        transfer(.copy, urls, to: currentURL)
    }

    func transfer(_ kind: TransferKind, _ urls: [URL], to destination: URL) {
        FileOperationCenter.shared.transfer(kind, sources: urls, to: destination, undoManager: undoManager) { [weak self] created in
            // En colonnes, la destination et les dossiers d'origine peuvent être affichés ailleurs que dans la colonne courante.
            self?.refreshBrowserFolders([destination] + urls.map { $0.deletingLastPathComponent() })
            guard let self else { return }
            // Destination dépliée dans la liste : on recharge pour montrer les éléments arrivés.
            if !destination.isSameLocation(as: currentURL), expandedPaths.contains(destination.normalizedPath) { reload(); return }
            guard destination.isSameLocation(as: currentURL), !created.isEmpty else { return }
            reload(selecting: created)
        }
    }

    // MARK: Vers un autre panneau (F5 / F6)

    @objc func copyToOtherPanel(_ sender: Any?) { transferToPanel(.copy, sender) }
    @objc func moveToOtherPanel(_ sender: Any?) { transferToPanel(.move, sender) }

    private func transferToPanel(_ kind: TransferKind, _ sender: Any?) {
        let explicit = (sender as? NSMenuItem)?.representedObject as? PanelViewController
        guard let target = explicit ?? host?.targetPanels(for: self).first else { return }
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let destination = target.currentURL
        flyEffect(to: target)
        FileOperationCenter.shared.transfer(kind, sources: urls, to: destination, undoManager: undoManager) { [weak target] created in
            guard let target, destination.isSameLocation(as: target.currentURL) else { return }
            target.reload(selecting: created)
        }
    }

    // MARK: Liens

    @objc func symlinkHere(_ sender: Any?) { makeLinks(hard: false, inOtherPanel: false) }
    @objc func symlinkInOtherPanel(_ sender: Any?) { makeLinks(hard: false, inOtherPanel: true) }
    @objc func hardLinkHere(_ sender: Any?) { makeLinks(hard: true, inOtherPanel: false) }
    @objc func hardLinkInOtherPanel(_ sender: Any?) { makeLinks(hard: true, inOtherPanel: true) }

    private func makeLinks(hard: Bool, inOtherPanel: Bool) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let target = inOtherPanel ? host?.targetPanels(for: self).first : self
        guard let target, target.currentURL.isFileURL else { NSSound.beep(); return }
        linkItems(urls, in: target.currentURL, hard: hard, reloading: target)
    }

    /// Dépôt avec ⌃ ou commandes « Créer un lien » : le panneau qui montre la destination sélectionne les liens.
    func linkItems(_ sources: [URL], in destination: URL, hard: Bool = false, reloading panel: PanelViewController? = nil) {
        let created = FileOperationCenter.shared.createLinks(to: sources, in: destination, hard: hard, undoManager: undoManager)
        let panel = panel ?? self
        if !created.isEmpty { panel.refreshBrowserFolders([destination]) }
        if !created.isEmpty, destination.isSameLocation(as: panel.currentURL) { panel.reload(selecting: created) }
    }

    // MARK: Création, renommage, corbeille

    @objc func newFolder(_ sender: Any?) {
        if currentURL.isRemote {
            FileOperationCenter.shared.createRemoteFolder(in: currentURL) { [weak self] result in
                switch result {
                case .success(let url): self?.reload(selecting: [url]) { self?.renameSelection(nil) }
                case .failure(let error): self?.presentErrorSheet(error)
                }
            }
            return
        }
        do {
            let url = try FileOperationCenter.shared.createFolder(in: currentURL, undoManager: undoManager)
            activate()
            reload(selecting: [url]) { [weak self] in self?.renameSelection(nil) }
        } catch {
            presentErrorSheet(error)
        }
    }

    /// Comme le Finder : un nouveau dossier qui reçoit les éléments sélectionnés, puis son nom à saisir.
    @objc func newFolderWithSelection(_ sender: Any?) {
        let urls = selectedURLs
        guard urls.count > 1, !currentURL.isRemote else { return }
        do {
            let folder = try FileOperationCenter.shared.createFolder(in: currentURL, undoManager: undoManager)
            activate()
            FileOperationCenter.shared.transfer(.move, sources: urls, to: folder, undoManager: undoManager) { [weak self] _ in
                self?.reload(selecting: [folder]) { self?.renameSelection(nil) }
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let firstRow = selectionIndexes.first ?? 0
        if currentURL.isRemote {
            guard let window = view.window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = urls.count == 1 ? L("Supprimer « \(urls[0].lastPathComponent) » du serveur ?") : L("Supprimer \(urls.count) éléments du serveur ?")
            alert.informativeText = L("Il n’y a pas de corbeille en SFTP : la suppression est définitive.")
            alert.addButton(withTitle: L("Supprimer")).hasDestructiveAction = true
            alert.addButton(withTitle: L("Annuler"))
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                FileOperationCenter.shared.deleteRemote(urls) { self?.reload(selecting: [], fallbackRow: firstRow) }
            }
            return
        }
        // Mode complet : les lignes s'effacent avant de partir à la corbeille.
        let rows: [NSView]
        switch viewMode {
        case .icons: rows = selectionIndexes.compactMap { collectionView.item(at: IndexPath(item: $0, section: 0))?.view }
        case .columns:
            let table = browserColumn(showing: currentURL).flatMap(browserTable(column:))
            rows = selectionIndexes.compactMap { table?.rowView(atRow: $0, makeIfNecessary: false) }
        case .list, .details: rows = tableView.selectedRowIndexes.compactMap { tableView.rowView(atRow: $0, makeIfNecessary: false) }
        }
        Effects.trash(rows) { [weak self] in
            guard let self else { return }
            FileOperationCenter.shared.trash(urls, undoManager: undoManager)
            reload(selecting: [], fallbackRow: firstRow)
        }
    }

    // MARK: Effets Whaouh+++

    private func nameCell(_ row: Int) -> NameCellView? {
        guard row >= 0, row < tableView.numberOfRows else { return nil }
        return tableView.view(atColumn: max(0, tableView.column(withIdentifier: .name)), row: row, makeIfNecessary: false) as? NameCellView
    }

    private func hoverEffect(_ row: Int, _ previous: Int) {
        let rowView = row >= 0 && row < tableView.numberOfRows ? tableView.rowView(atRow: row, makeIfNecessary: false) : nil
        let oldView = previous >= 0 && previous < tableView.numberOfRows ? tableView.rowView(atRow: previous, makeIfNecessary: false) : nil
        Effects.hover(rowView, icon: nameCell(row)?.imageView, previous: oldView, previousIcon: nameCell(previous)?.imageView)
    }

    private func clickEffect(_ row: Int, _ point: NSPoint) {
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
        Effects.ripple(in: rowView, at: rowView.convert(point, from: tableView))
        Effects.pop(nameCell(row)?.imageView)
    }

    /// Copie ou déplacement vers un autre panneau : les icônes s'envolent vers lui.
    private func flyEffect(to target: PanelViewController) {
        guard Effects.isOn(.flyingFiles), let window = view.window else { return }
        if viewMode == .columns {
            // Colonnes : les icônes des éléments, depuis la ligne de la colonne courante.
            guard let table = browserColumn(showing: currentURL).flatMap(browserTable(column:)), let first = selectionIndexes.first,
                  let rowView = table.rowView(atRow: first, makeIfNecessary: false) else { return }
            let images = selectionIndexes.prefix(6).map { items[$0].icon }
            let end = target.view.convert(NSPoint(x: target.view.bounds.midX, y: target.view.bounds.midY), to: nil)
            Effects.fly(images, from: rowView.convert(rowView.bounds, to: nil), to: end, in: window)
            return
        }
        let rows = tableView.selectedRowIndexes.prefix(6)
        let images = rows.compactMap { nameCell($0)?.imageView?.image }
        guard let first = rows.first, let rowView = tableView.rowView(atRow: first, makeIfNecessary: false) else { return }
        let start = rowView.convert(rowView.bounds, to: nil)
        let end = target.view.convert(NSPoint(x: target.view.bounds.midX, y: target.view.bounds.midY), to: nil)
        Effects.fly(images, from: start, to: end, in: window)
    }

    /// Le nom renommé s'écrit lettre par lettre (Whaouh+++).
    private func typewriterEffect(_ url: URL) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        Effects.typewriter(nameCell(tableRow(forItem: index))?.textField)
    }

    /// Recharge en sélectionnant les éléments créés, puis les met en valeur (Whaouh+++).
    func revealCreated(_ urls: [URL], symbol: String? = nil, color: NSColor = .systemPurple, accordion: Bool = false) {
        reload(selecting: urls) { [weak self] in
            guard let self else { return }
            for (offset, url) in urls.enumerated() {
                guard let index = items.firstIndex(where: { $0.url == url }) else { continue }
                let row = tableRow(forItem: index)
                let rowView = row >= 0 && row < tableView.numberOfRows ? tableView.rowView(atRow: row, makeIfNecessary: false) : nil
                if accordion { Effects.pop(nameCell(row)?.imageView, delay: Double(offset) * 0.05, from: 1.6, axis: "transform.scale.x") }
                else { Effects.pop(nameCell(row)?.imageView, delay: Double(offset) * 0.05) }
                if let symbol { Effects.stamp(symbol, color: color, on: rowView) }
            }
        }
    }

    /// Glissement ou fondu du contenu, puis cascade des éléments visibles en mode complet.
    private func playNavigationAnimation(_ direction: NavigationDirection) {
        let content: NSView = viewMode == .icons ? gridScrollView : (viewMode == .columns ? browser : scrollView)
        Effects.navigate(content, direction)
        if viewMode == .icons {
            Effects.cascade(collectionView.visibleItems().compactMap { $0.view }
                .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) })
        } else if viewMode != .columns {
            let visible = tableView.rows(in: tableView.visibleRect)
            Effects.cascade((visible.location..<NSMaxRange(visible)).compactMap { tableView.rowView(atRow: $0, makeIfNecessary: false) })
        }
        // Whaouh+++ : les icônes du nouveau dossier font « pop » en spirale depuis le centre.
        if Effects.isOn(.spiral), viewMode != .icons, viewMode != .columns {
            let visible = tableView.rows(in: tableView.visibleRect)
            let middle = visible.location + visible.length / 2
            for row in visible.location..<NSMaxRange(visible) {
                Effects.pop(nameCell(row)?.imageView, delay: Double(abs(row - middle)) * 0.025, from: 0.4, effect: .spiral)
            }
        }
    }

    @objc func renameSelection(_ sender: Any?) {
        if selectionIndexes.count > 1 { batchRename(sender); return }
        guard selectionIndexes.count == 1, let row = selectionIndexes.first else { return }
        if viewMode == .icons || viewMode == .columns { renameWithSheet(items[row]); return }
        let column = tableView.column(withIdentifier: .name)
        tableView.scrollRowToVisible(tableRow(forItem: row))
        guard column >= 0,
              let cell = tableView.view(atColumn: column, row: tableRow(forItem: row), makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingRow = row
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.delegate = self
        view.window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            let item = items[row]
            let ext = (item.name as NSString).pathExtension
            let base = item.isNavigableDirectory || ext.isEmpty ? item.name : (item.name as NSString).deletingPathExtension
            editor.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
    }

    private func finishRename(_ field: NSTextField, commit: Bool) {
        guard let row = renamingRow else { return }
        renamingRow = nil
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.delegate = nil
        guard items.indices.contains(row) else { return }
        let item = items[row]
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.stringValue = item.name
        view.window?.makeFirstResponder(focusView)
        if commit, !newName.isEmpty, newName != item.name, item.url.isRemote {
            FileOperationCenter.shared.renameRemote(item.url, to: newName) { [weak self] result in
                switch result {
                case .success(let url): self?.reload(selecting: [url])
                case .failure(let error): self?.presentErrorSheet(error); self?.reload()
                }
            }
            reloadDeferred = false
            return
        }
        if commit, !newName.isEmpty, newName != item.name {
            do {
                let renamed = try FileOperationCenter.shared.rename(item.url, to: newName, undoManager: undoManager)
                reload(selecting: [renamed]) { [weak self] in self?.typewriterEffect(renamed) }
                return
            } catch {
                presentErrorSheet(error)
            }
        }
        if reloadDeferred {
            reloadDeferred = false
            reload()
        }
    }

    private func renameWithSheet(_ item: FileItem) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = L("Renommer « \(item.name) »")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = item.name
        alert.accessoryView = field
        alert.addButton(withTitle: L("Renommer"))
        alert.addButton(withTitle: L("Annuler"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.url.isRemote {
                FileOperationCenter.shared.renameRemote(item.url, to: newName) { [weak self] result in
                    switch result {
                    case .success(let url): self?.reload(selecting: [url])
                    case .failure(let error): self?.presentErrorSheet(error)
                    }
                }
                return
            }
            do {
                let renamed = try FileOperationCenter.shared.rename(item.url, to: newName, undoManager: undoManager)
                reload(selecting: [renamed]) { [weak self] in self?.typewriterEffect(renamed) }
            } catch {
                presentErrorSheet(error)
            }
        }
    }

    private func presentErrorSheet(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: Archives

    @objc func extractHere(_ sender: Any?) { extract(into: self) }

    @objc func extractToOtherPanel(_ sender: Any?) {
        guard let target = host?.targetPanels(for: self).first else { return }
        extract(into: target)
    }

    private func extract(into panel: PanelViewController) {
        let archives = selectedURLs.filter(FileOperationCenter.isArchive)
        guard !archives.isEmpty, !currentURL.isRemote, !panel.currentURL.isRemote else { return }
        let destination = panel.currentURL
        for archive in archives {
            FileOperationCenter.shared.extract(archive, into: destination, undoManager: undoManager) { [weak panel] folder in
                guard let folder, let panel, destination.isSameLocation(as: panel.currentURL) else { return }
                panel.revealCreated([folder])
            }
        }
    }

    // MARK: Aperçu (Quick Look)

    @objc func quickLook(_ sender: Any?) {
        if currentURL.isRemote { NSSound.beep(); return }
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    private func refreshQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.isVisible, (panel.dataSource as AnyObject?) === self else { return }
        panel.reloadData()
    }

    // MARK: Clavier

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty: // Retour / Entrée
            openSelection(nil)
        case 51 where modifiers.isEmpty: // Effacement arrière
            goUp(nil)
        case 48 where modifiers.isEmpty || modifiers == .shift: // Tab
            host?.panel(self, focusNextBackwards: modifiers == .shift)
        case 53 where modifiers.isEmpty && isSearching: // Échap ferme la recherche
            endSearch()
        case 49 where modifiers == .option: // ⌥Espace : taille des dossiers sélectionnés
            computeSelectedFolderSizes(nil)
        case 49 where modifiers == [.option, .shift]: // ⇧⌥Espace : tous les dossiers
            computeAllFolderSizes(nil)
        case 49 where modifiers.isEmpty: // Espace
            quickLook(nil)
        case 123 where modifiers.isEmpty || modifiers == .command, 124 where modifiers.isEmpty || modifiers == .command: // ← / →
            return handleOutlineKey(expand: event.keyCode == 124)
        default:
            return Preferences.commanderKeys && handleCommanderKey(event, modifiers: modifiers)
        }
        return true
    }

    /// Touches de Total Commander (option du menu Édition). F2, F5 et F6 sont déjà des raccourcis de menu.
    private func handleCommanderKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        let keypad = event.modifierFlags.contains(.numericPad)
        switch event.keyCode {
        case 99 where modifiers.isEmpty: quickLook(nil) // F3 : voir
        case 118 where modifiers.isEmpty: editSelection(nil) // F4 : modifier
        case 97 where modifiers == .shift: renameSelection(nil) // ⇧F6 : renommer
        case 98 where modifiers.isEmpty: newFolder(nil) // F7
        case 100 where modifiers.isEmpty: moveToTrash(nil) // F8
        case 69 where keypad && modifiers.isEmpty: selectByPattern(nil) // + : sélectionner
        case 78 where keypad && modifiers.isEmpty: deselectByPattern(nil) // − : désélectionner
        case 67 where keypad && modifiers.isEmpty: invertSelection(nil) // * : inverser
        default: return false
        }
        return true
    }

    /// F4 : ouvre les fichiers sélectionnés dans l'éditeur de texte par défaut.
    @objc func editSelection(_ sender: Any?) {
        let files = selectedItems.filter { !$0.isNavigableDirectory }.map(\.url).filter(\.isFileURL)
        guard !files.isEmpty, let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else { NSSound.beep(); return }
        NSWorkspace.shared.open(files, withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Menu contextuel

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let selection = selectedItems
        let shown = { (entry: ContextMenuEntry) in entry.isShown }
        func item(_ title: String, _ action: Selector, _ symbol: String? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            return item
        }
        func tinted(_ title: String, _ action: Selector, _ symbol: String, _ tint: NSColor) -> NSMenuItem {
            let entry = item(title, action)
            entry.image = MenuTint.icon(symbol, tint)
            MenuTint.style(entry, tint)
            return entry
        }
        func separator() {
            if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
        }
        // Un groupe n'apparaît (avec son titre éventuel) que s'il lui reste des entrées : réglages, sélection, serveur.
        func group(_ title: String?, _ entries: [NSMenuItem]) {
            guard !entries.isEmpty else { return }
            separator()
            if let title { menu.addItem(.sectionHeader(title: title)) }
            entries.forEach(menu.addItem)
        }

        // Actions courantes en icônes, en tête du menu.
        var palette: [NSMenuItem] = []
        if shown(.quickActions) { palette.append(quickActionsPalette(for: selection)) }
        if shown(.tagDots), !selection.isEmpty, !currentURL.isRemote { palette.append(tagsPalette(for: selection)) }
        group(nil, palette)

        // Actions définies par les règles de type de fichier (Makefile, Typst, Markdown…).
        if shown(.fileTypeActions) { group(nil, fileActionMenuItems()) }

        // Groupes titrés, icônes colorées par famille : Ouvrir, Transformer, Organiser
        // (ordre inspiré du Finder, de l'Explorateur Windows et de Dolphin).
        let files = selection.filter { !$0.isNavigableDirectory }
        if !selection.isEmpty {
            var open: [NSMenuItem] = []
            if shown(.open), !files.isEmpty { open.append(tinted(L("Ouvrir"), #selector(openSelection(_:)), "arrow.up.forward.app", MenuTint.open)) }
            if shown(.openWith), let first = files.first, files.count == selection.count, !first.url.isRemote {
                let openWith = openWithMenu(for: first.url)
                openWith.image = MenuTint.icon("square.grid.2x2", MenuTint.open)
                MenuTint.style(openWith, MenuTint.open)
                open.append(openWith)
            }
            if shown(.openInNewTab), selection.contains(where: \.isNavigableDirectory) {
                open.append(tinted(L("Ouvrir dans un nouvel onglet"), #selector(openInNewTab(_:)), "plus.square.on.square", MenuTint.open))
            }
            if shown(.packageContents), selection.count == 1, selection[0].isPackage {
                open.append(tinted(L("Afficher le contenu du paquet"), #selector(showPackageContents(_:)), "shippingbox", MenuTint.open))
            }
            group(L("Ouvrir"), open)
            if !currentURL.isRemote { group(L("Transformer"), transformMenuItems(for: selection)) }
        }

        var organize: [NSMenuItem] = []
        if !selection.isEmpty {
            if shown(.newFolderWithSelection), selection.count > 1, !currentURL.isRemote {
                organize.append(item(L("Nouveau dossier avec la sélection (\(selection.count) éléments)"), #selector(newFolderWithSelection(_:)), "folder.badge.plus"))
            }
            let targets = host?.targetPanels(for: self) ?? []
            if shown(.copyMoveTo), !targets.isEmpty {
                organize.append(panelSubmenu(L("Copier vers"), #selector(copyToOtherPanel(_:)), targets, "arrow.right.doc.on.clipboard"))
                organize.append(panelSubmenu(L("Déplacer vers"), #selector(moveToOtherPanel(_:)), targets, "arrow.right.square"))
            }
            if shown(.links), !currentURL.isRemote {
                let links = NSMenuItem(title: L("Créer un lien"), action: nil, keyEquivalent: "")
                links.image = NSImage(systemSymbolName: "link.badge.plus", accessibilityDescription: nil)
                links.submenu = NSMenu()
                for (title, action) in [(L("Lien symbolique ici"), #selector(symlinkHere(_:))), (L("Lien symbolique dans l’autre panneau"), #selector(symlinkInOtherPanel(_:))),
                                        (L("Lien physique ici"), #selector(hardLinkHere(_:))), (L("Lien physique dans l’autre panneau"), #selector(hardLinkInOtherPanel(_:)))] {
                    links.submenu?.addItem(item(title, action))
                }
                organize.append(links)
            }
            if shown(.copyPath) { organize.append(item(L("Copier le chemin"), #selector(copyPath(_:)), "link")) }
            if !currentURL.isRemote {
                if shown(.tags) { organize.append(tagsMenuItem()) }
                if shown(.customActions), let actions = customActionsMenuItem() { organize.append(actions) }
                if shown(.share) { organize.append(shareMenuItem(for: selection.map(\.url))) }
            }
        }
        group(L("Organiser"), organize)

        var create: [NSMenuItem] = []
        if shown(.newFolder) { create.append(item(L("Nouveau dossier"), #selector(newFolder(_:)), "folder.badge.plus")) }
        if !currentURL.isRemote {
            if shown(.newDocument) { create.append(newDocumentMenuItem()) }
            if shown(.terminal) { create.append(item(L("Ouvrir dans le Terminal"), #selector(openInTerminal(_:)), "terminal")) }
            if shown(.diskUsage), selection.isEmpty { create.append(item(L("Occupation du disque"), #selector(toggleDiskUsage(_:)), "chart.pie")) }
        }
        group(nil, create)

        if shown(.trash), !selection.isEmpty {
            group(nil, [tinted(L("Placer dans la corbeille"), #selector(moveToTrash(_:)), "trash", MenuTint.danger)])
        }

        var view: [NSMenuItem] = []
        if shown(.flatView), selection.isEmpty, isFlatView || canShowFlatView { view.append(flatViewMenuItem()) }
        if shown(.grouping), selection.isEmpty, viewMode == .list || viewMode == .details { view.append(groupingMenuItem()) }
        group(nil, view)
        return menu
    }

    private func openWithMenu(for url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: L("Ouvrir avec"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if let defaultApp {
            apps.removeAll { $0.isSameLocation(as: defaultApp) }
            apps.insert(defaultApp, at: 0)
        }
        for (index, app) in apps.prefix(20).enumerated() {
            var title = FileManager.default.displayName(atPath: app.path)
            if index == 0, defaultApp != nil { title += " " + L("(par défaut)") }
            let entry = NSMenuItem(title: title, action: #selector(openWithApplication(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if index == 0, defaultApp != nil, apps.count > 1 { submenu.addItem(.separator()) }
        }
        item.submenu = submenu
        return item
    }

    private func panelSubmenu(_ title: String, _ action: Selector, _ targets: [PanelViewController], _ symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let submenu = NSMenu()
        for target in targets {
            let entry = NSMenuItem(title: L("Panneau \(target.index + 1) — \(BreadcrumbView.displayName(target.currentURL))"), action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = target
            entry.toolTip = target.currentURL.path
            let icon = target.currentURL.isRemote ? NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)! : NSWorkspace.shared.icon(forFile: target.currentURL.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }
}

// MARK: - Validation des menus

extension PanelViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasSelection = !selectionIndexes.isEmpty
        let localOnly: [Selector?] = [#selector(revealInFinder(_:)), #selector(openInTerminal(_:)), #selector(addToFavorites(_:)),
                                      #selector(runCustomAction(_:)),
                                      #selector(compressSelection(_:)), #selector(compressQuick(_:)), #selector(compressCustom(_:)),
                                      #selector(extractHere(_:)), #selector(extractToOtherPanel(_:)),
                                      #selector(quickLook(_:)), #selector(showPackageContents(_:)), #selector(newDocument(_:)),
                                      #selector(shareSelection(_:)), #selector(showChecksums(_:)), #selector(splitFile(_:)), #selector(joinFiles(_:)),
                                      #selector(compressWithPassword(_:)), #selector(encryptFiles(_:)), #selector(decryptFiles(_:))]
        if currentURL.isRemote, localOnly.contains(menuItem.action) { return false }
        switch menuItem.action {
        case #selector(encryptFiles(_:)):
            return !encryptableFiles.isEmpty
        case #selector(decryptFiles(_:)):
            return !encryptedFiles.isEmpty
        case #selector(splitFile(_:)):
            return splitCandidate != nil
        case #selector(joinFiles(_:)):
            return joinCandidate != nil
        case #selector(showChecksums(_:)):
            return selectedItems.contains { !$0.isNavigableDirectory }
        case #selector(symlinkHere(_:)), #selector(symlinkInOtherPanel(_:)):
            return hasSelection && currentURL.isFileURL
        case #selector(hardLinkHere(_:)), #selector(hardLinkInOtherPanel(_:)):
            return hasSelection && currentURL.isFileURL && !selectedItems.contains(where: \.isNavigableDirectory)
        case #selector(copy(_:)), #selector(cut(_:)), #selector(duplicate(_:)), #selector(moveToTrash(_:)),
             #selector(openSelection(_:)), #selector(quickLook(_:)), #selector(shareSelection(_:)), #selector(selectSameType(_:)):
            return hasSelection
        case #selector(compressSelection(_:)), #selector(compressWithPassword(_:)), #selector(compressQuick(_:)), #selector(compressCustom(_:)):
            return hasSelection
        case #selector(extractHere(_:)):
            return selectedURLs.contains(where: FileOperationCenter.isArchive)
        case #selector(extractToOtherPanel(_:)):
            return selectedURLs.contains(where: FileOperationCenter.isArchive) && !(host?.targetPanels(for: self).isEmpty ?? true)
        case #selector(copyToOtherPanel(_:)), #selector(moveToOtherPanel(_:)):
            return hasSelection && !(host?.targetPanels(for: self).isEmpty ?? true)
        case #selector(syncOtherPanel(_:)), #selector(compareWithOtherPanel(_:)):
            return !(host?.targetPanels(for: self).isEmpty ?? true)
        case #selector(renameSelection(_:)):
            return !selectionIndexes.isEmpty
        case #selector(batchRename(_:)):
            return !selectionIndexes.isEmpty
        case #selector(showAsIcons(_:)), #selector(showAsList(_:)), #selector(showAsDetails(_:)), #selector(showAsColumns(_:)):
            let mode: PanelViewMode = menuItem.action == #selector(showAsIcons(_:)) ? .icons
                : menuItem.action == #selector(showAsList(_:)) ? .list
                : menuItem.action == #selector(showAsColumns(_:)) ? .columns : .details
            if mode == .columns, currentURL.isRemote { return false }
            menuItem.state = mode == viewMode && !isShowingDiskUsage ? .on : .off
            return true
        case #selector(toggleDiskUsage(_:)):
            menuItem.state = isShowingDiskUsage ? .on : .off
            return !currentURL.isRemote
        case #selector(analyzeDiskUsage(_:)):
            return !currentURL.isRemote
        case #selector(increaseIconSize(_:)), #selector(decreaseIconSize(_:)), #selector(resetZoom(_:)):
            return true
        case #selector(toggleStatusBar(_:)):
            menuItem.title = PanelStatusBar.isVisible ? L("Masquer la barre d’état") : L("Afficher la barre d’état")
            return true
        case #selector(toggleFlatView(_:)):
            menuItem.state = isFlatView ? .on : .off
            return isFlatView || canShowFlatView
        case #selector(groupBy(_:)):
            menuItem.state = menuItem.tag == grouping.rawValue ? .on : .off
            return viewMode == .list || viewMode == .details
        case #selector(sortBy(_:)):
            let keys = ["name", "size", "date", "kind"]
            menuItem.state = keys.indices.contains(menuItem.tag) && keys[menuItem.tag] == sortDescriptor.key ? .on : .off
            return true
        case #selector(paste(_:)), #selector(pasteMove(_:)):
            return FileClipboard.hasFiles
        case #selector(goBack(_:)): return !tab.back.isEmpty
        case #selector(goForward(_:)): return !tab.forward.isEmpty
        case #selector(goUp(_:)): return currentURL.path != "/"
        case #selector(closeTab(_:)), #selector(nextTab(_:)), #selector(previousTab(_:)): return tabs.count > 1
        default: return true
        }
    }
}

// MARK: - Table

extension PanelViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { isGrouped ? groupRows.count : items.count }

    /// Colonne Taille ou Date redimensionnée : les textes visibles sont recalculés pour la nouvelle largeur.
    func tableViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              column.identifier == .size || column.identifier == .date,
              let index = tableView.tableColumns.firstIndex(of: column) else { return }
        let rows = tableView.rows(in: tableView.visibleRect)
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: rows.location..<rows.location + rows.length), columnIndexes: [index])
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { isGroupHeader(row) ? nil : ThemedRowView() }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { isGroupHeader(row) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !isGroupHeader(row) }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        isGrouped ? proposed.filteredIndexSet { !isGroupHeader($0) } : proposed
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row tableRow: Int) -> NSView? {
        if isGrouped, groupRows.indices.contains(tableRow), case .header(let title, let count) = groupRows[tableRow] {
            return groupHeaderView(title, count: count)
        }
        guard let identifier = tableColumn?.identifier, let row = itemIndex(forRow: tableRow) else { return nil }
        let item = items[row]
        let dimmed = item.isHidden || cutPaths.contains(item.url.normalizedPath)

        if identifier == .name {
            let cell = tableView.makeView(withIdentifier: .nameCell, owner: self) as? NameCellView ?? makeNameCell()
            cell.apply(scale: listScale)
            cell.textField?.stringValue = item.name
            cell.imageView?.image = item.icon
            let outline = canExpandFolders
            cell.indent.constant = 2 + (outline ? CGFloat(item.depth) * (16 * listScale).rounded() : 0)
            cell.disclosureWidth.constant = outline ? 14 : 0
            cell.disclosure.isHidden = !(outline && item.isNavigableDirectory)
            cell.disclosure.state = isExpanded(item) ? .on : .off
            cell.alphaValue = dimmed ? 0.5 : 1
            let state = gitState(for: item)
            if renamingRow != row {
                cell.normalTextColor = state?.color ?? Theme.text
                cell.applyTextColor()
            }
            cell.tagDots.attributedStringValue = item.url.isFileURL ? FinderTags.dots(for: item.finderTags) : NSAttributedString()
            if let badge = repositoryBadge(for: item) {
                cell.badge.attributedStringValue = badge
            } else if let state, !state.letter.isEmpty {
                // Fichier : son état ; dossier : l'état le plus important de son contenu.
                cell.badge.attributedStringValue = NSAttributedString(string: state.letter, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: state.color,
                ])
            } else {
                cell.badge.stringValue = ""
            }
            return cell
        }

        let cell = tableView.makeView(withIdentifier: .textCell, owner: self) as? ThemedCellView ?? makeTextCell()
        let field = cell.textField!
        let textSize = (12 * listScale).rounded()
        if field.font?.pointSize != textSize { field.font = .monospacedDigitSystemFont(ofSize: textSize, weight: .regular) }
        if let column = MetadataColumn(identifier: identifier) {
            field.stringValue = metadataText(column, for: item)
            field.alignment = column == .duration || column == .pages ? .right : .left
            field.toolTip = field.stringValue.isEmpty ? nil : field.stringValue
            cell.alphaValue = dimmed ? 0.5 : 1
            return cell
        }
        // Taille et date se raccourcissent quand la colonne est étroite.
        let available = (tableColumn?.width ?? 200) - 8
        switch identifier {
        case .size:
            let bytes = item.isNavigableDirectory ? item.folderSize : item.size
            let full = item.isNavigableDirectory ? folderSizeText(for: item) : (item.size.map(Format.size) ?? "—")
            field.stringValue = bytes.map { Format.fitting([full, Format.compactSize($0)], width: available, font: field.font!) } ?? full
            field.alignment = .right
        case .date:
            field.stringValue = item.modificationDate.map { Format.fitting(Format.dateVariants($0), width: available, font: field.font!) } ?? ""
            field.alignment = .left
        default:
            // Dans les résultats de recherche, la colonne indique le dossier de chaque élément.
            field.stringValue = isShowingSearchResults || isFlatView ? searchLocation(of: item) : (item.isNavigableDirectory ? L("Dossier") : item.kind)
            field.alignment = .left
        }
        field.toolTip = isShowingSearchResults || isFlatView ? item.url.deletingLastPathComponent().path : nil
        cell.alphaValue = dimmed ? 0.5 : 1
        return cell
    }

    private func makeNameCell() -> NameCellView {
        let cell = NameCellView()
        cell.identifier = .nameCell
        let image = NSImageView()
        cell.iconWidth = image.widthAnchor.constraint(equalToConstant: 18)
        cell.iconHeight = image.heightAnchor.constraint(equalToConstant: 18)
        image.imageScaling = .scaleProportionallyUpOrDown
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.isScrollable = false
        let badge = cell.badge
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let dots = cell.tagDots
        dots.setContentHuggingPriority(.required, for: .horizontal)
        dots.setContentCompressionResistancePriority(.required, for: .horizontal)
        let disclosure = cell.disclosure
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.title = ""
        disclosure.controlSize = .small
        disclosure.target = self
        disclosure.action = #selector(toggleDisclosure(_:))
        disclosure.toolTip = L("Déplier / replier (→ / ←)")
        cell.indent = disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2)
        cell.disclosureWidth = disclosure.widthAnchor.constraint(equalToConstant: 0)
        for view in [disclosure, image, field, dots, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            cell.indent,
            cell.disclosureWidth,
            disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            cell.iconWidth,
            cell.iconHeight,
            field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 7),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dots.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 4),
            dots.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: dots.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.imageView = image
        cell.textField = field
        return cell
    }

    private func makeTextCell() -> ThemedCellView {
        let cell = ThemedCellView()
        cell.normalTextColor = Theme.secondaryText
        cell.identifier = .textCell
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.textColor = Theme.secondaryText
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.textField = field
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        sortDescriptor = descriptor
        // Avec des dossiers dépliés, chaque niveau est retrié par le rechargement.
        if canExpandFolders, !expandedPaths.isEmpty { reload(); return }
        let selection = selectedURLs
        if isShowingSearchResults {
            items = Self.sorted(items, by: sortDescriptor)
        } else {
            allItems = Self.sorted(allItems, by: sortDescriptor)
            let filter = isSearching && searchBar.scope == .folder ? Self.nameMatcher(for: searchBar.field.stringValue.trimmingCharacters(in: .whitespaces)) : nil
            items = filter.map { match in allItems.filter { item in match(item.name) { item.finderTags } } } ?? allItems
        }
        reloadViews()
        let paths = Set(selection.map(\.normalizedPath))
        setSelection(IndexSet(items.indices.filter { paths.contains(items[$0].url.normalizedPath) }), scroll: false)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard viewMode != .icons else { return }
        selectionDidChange()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard tableColumn?.identifier == .name, let index = itemIndex(forRow: row) else { return nil }
        return items[index].name
    }

    // Glisser-déposer

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        itemIndex(forRow: row).map { items[$0].url as NSURL }
    }

    fileprivate func dropDestination(row tableRow: Int, operation: NSTableView.DropOperation, sources: [URL]) -> URL {
        guard let row = itemIndex(forRow: tableRow) else { return currentURL }
        let item = items[row]
        if operation == .on, item.isNavigableDirectory, !sources.contains(where: { $0.isSameLocation(as: item.url) }) {
            return item.url
        }
        // Dans un dossier déplié, un dépôt sur un fichier ou entre deux lignes vise le dossier qui les contient.
        return item.depth > 0 ? item.url.deletingLastPathComponent() : currentURL
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let sources = FileClipboard.fileURLs(from: info.draggingPasteboard)
        guard !sources.isEmpty else { return [] }
        let destination = dropDestination(row: row, operation: dropOperation, sources: sources)
        if destination.isSameLocation(as: currentURL) {
            tableView.setDropRow(-1, dropOperation: .on)
        } else if let folder = items.firstIndex(where: { $0.url.isSameLocation(as: destination) }) {
            // Le dossier déplié visé est mis en évidence, pas la ligne survolée.
            tableView.setDropRow(tableRow(forItem: folder), dropOperation: .on)
        }
        return validatedOperation(info, sources: sources, destination: destination)
    }

    func validatedOperation(_ info: NSDraggingInfo, sources: [URL], destination: URL) -> NSDragOperation {
        if sources.contains(where: { destination.isInside($0) }) { return [] }
        let operation = FileOperationCenter.dropOperation(for: info, sources: sources, destination: destination)
        if operation == .move, sources.allSatisfy({ $0.deletingLastPathComponent().isSameLocation(as: destination) }) { return [] }
        if operation == .link, currentURL.isRemote { return [] }
        return operation
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        performDrop(info, row: row, operation: dropOperation)
    }

    fileprivate func performDrop(_ info: NSDraggingInfo, row: Int, operation dropOperation: NSTableView.DropOperation) -> Bool {
        let sources = FileClipboard.fileURLs(from: info.draggingPasteboard)
        guard !sources.isEmpty else { return false }
        let destination = dropDestination(row: row, operation: dropOperation, sources: sources)
        let operation = FileOperationCenter.dropOperation(for: info, sources: sources, destination: destination)
        guard !operation.isEmpty else { return false }
        activate()
        // Whaouh+++ : gerbe de particules au point de dépôt, couleur selon l'opération.
        let point = tableView.convert(info.draggingLocation, from: nil)
        let color: NSColor = operation == .link ? .systemPurple : operation == .copy ? .systemGreen : .systemBlue
        if Effects.isOn(.dropParticles) { Effects.celebrate(in: tableView, at: point, colors: [color, color.blended(withFraction: 0.5, of: .white) ?? color], amount: 40) }
        if operation == .link { linkItems(sources, in: destination); return true }
        transfer(operation == .copy ? .copy : .move, sources, to: destination)
        return true
    }
}

// MARK: - Renommage sur place

extension PanelViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField else { return false }
        finishRename(field, commit: false)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        finishRename(field, commit: true)
    }
}

// MARK: - Quick Look

extension PanelViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = selectedURLs
        return urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        focusView.keyDown(with: event)
        return true
    }
}

// MARK: - Grille d'icônes

extension PanelViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
        if let thumbnail = cell as? ThumbnailItem, items.indices.contains(indexPath.item) {
            let item = items[indexPath.item]
            thumbnail.configure(with: item, size: iconSize, dimmed: item.isHidden || cutPaths.contains(item.url.normalizedPath),
                                gitColor: gitState(for: item)?.color, badge: repositoryBadge(for: item))
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if viewMode == .icons { selectionDidChange() }
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if viewMode == .icons { selectionDidChange() }
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items.indices.contains(indexPath.item) ? items[indexPath.item].url as NSURL : nil
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let sources = FileClipboard.fileURLs(from: draggingInfo.draggingPasteboard)
        guard !sources.isEmpty else { return [] }
        let row = (proposedDropIndexPath.pointee as IndexPath).item
        let operation: NSTableView.DropOperation = proposedDropOperation.pointee == .on ? .on : .above
        let destination = dropDestination(row: row, operation: operation, sources: sources)
        if destination.isSameLocation(as: currentURL), proposedDropOperation.pointee == .on {
            proposedDropOperation.pointee = .before
        }
        return validatedOperation(draggingInfo, sources: sources, destination: destination)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let operation: NSTableView.DropOperation = dropOperation == .on ? .on : .above
        return performDrop(draggingInfo, row: indexPath.item, operation: operation)
    }
}

/// Cellule « Nom » : icône, nom et indicateur Git à droite.
final class NameCellView: ThemedCellView {
    let badge = NSTextField(labelWithString: "")
    /// Pastilles des tags du Finder.
    let tagDots = NSTextField(labelWithString: "")
    /// Triangle des dossiers dépliables, et retrait selon la profondeur.
    let disclosure = NSButton()
    var indent: NSLayoutConstraint!
    var disclosureWidth: NSLayoutConstraint!
    var iconWidth: NSLayoutConstraint!
    var iconHeight: NSLayoutConstraint!
    private var scale: CGFloat = 1

    /// Taille du texte et de l'icône selon le zoom de la liste.
    func apply(scale newScale: CGFloat) {
        guard newScale != scale else { return }
        scale = newScale
        iconWidth.constant = (18 * scale).rounded()
        iconHeight.constant = (18 * scale).rounded()
        textField?.font = .systemFont(ofSize: (13 * scale).rounded())
    }
}

/// Cellule dont le texte prend la couleur du thème, et repasse en clair sur une sélection pleine.
class ThemedCellView: NSTableCellView {
    var normalTextColor: NSColor = Theme.text

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyTextColor() }
    }

    func applyTextColor() {
        textField?.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : normalTextColor
    }
}
