import AppKit
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// Éditeur à côté du panneau quand un seul panneau est affiché : le fichier texte sélectionné s'ouvre
/// dans un onglet, se modifie et s'enregistre (⌘S) ; s'il est suivi par Git, « Enregistrer, commit et push ».
/// Markdown, CSV et JSON ont un aperçu, mis à jour à la frappe (le Markdown s'ouvre en aperçu seul ;
/// sélecteur Aperçu / Mixte / Source, double-clic dans l'aperçu pour modifier à cet endroit) ; LaTeX et Typst sont compilés
/// à l'enregistrement, PDF à côté. La marge signale les lignes modifiées depuis le dernier commit.
/// ⌘-clic synchronise le texte et l'aperçu dans les deux sens (SyncTeX pour LaTeX) ; l'aperçu Markdown suit le défilement.
/// Les autres fichiers (images, PDF, vidéos…) s'affichent en Coup d'œil.
enum EditorMode: Int {
    /// Rendu seul, texte seul, ou les deux côte à côte.
    case preview, mixed, source
}

final class EditorViewController: NSViewController, NSTextViewDelegate {
    static let enabledChanged = Notification.Name("EditorEnabledChanged")

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "editorInSingleLayout") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "editorInSingleLayout")
            NotificationCenter.default.post(name: enabledChanged, object: nil)
        }
    }

    /// Éditeurs ouverts, pour prévenir avant de quitter avec des modifications.
    private static var instances = NSHashTable<EditorViewController>.weakObjects()
    static var hasUnsavedChanges: Bool { instances.allObjects.contains { $0.documents.contains(where: \.isModified) } }

    private final class Document {
        let url: URL
        var text: String
        var encoding: String.Encoding
        var isModified = false
        /// `nil` tant que la question n'a pas été posée à Git ; puis la racine du dépôt si le fichier est suivi.
        var gitRoot: URL??
        /// Lignes du fichier au dernier commit, pour les marques de la marge.
        var committedLines: [String]?
        var selection = NSRange(location: 0, length: 0)
        /// Mode choisi pour ce document ; `nil` : celui de son type (voir `mode(for:)`).
        var mode: EditorMode?
        var previewKind: EditorPreviewKind? { EditorPreviewKind(url: url) }

        init(url: URL, text: String, encoding: String.Encoding) {
            self.url = url
            self.text = text
            self.encoding = encoding
        }
    }

    private var documents: [Document] = []
    private var current: Document?
    /// Dernier document affiché : reste l'onglet d'aperçu réutilisable pendant qu'un PDF ou un Coup d'œil s'affiche.
    private weak var lastShown: Document?
    /// Fichier à l'écran (texte, PDF ou Coup d'œil), pour proposer ses fichiers liés.
    private var displayedURL: URL?

    private let tabs = NSStackView()
    private let saveButton = NSButton(title: L("Enregistrer"), target: nil, action: nil)
    private let commitButton = NSButton(title: L("Enregistrer, commit et push"), target: nil, action: nil)
    private let findButton = NSButton(title: L("Rechercher"), target: nil, action: nil)
    private let modeControl = NSSegmentedControl()
    private let wrapButton = NSButton(title: L("Retour à la ligne"), target: nil, action: nil)
    private let split = NSSplitView()
    private let preview = EditorPreviewView()
    private let textScroll = NSScrollView()
    private var ruler: LineNumberRuler?
    private let textView = SourceTextView()
    /// Pas de suivi du défilement juste après un saut demandé depuis l'aperçu.
    private var followScrollPaused = false
    private var quickLook: QLPreviewView?
    /// PDF hors éditeur de texte : vue PDF plutôt que Coup d'œil, pour recharger sans perdre la position.
    private var pdfViewer: PDFView?
    /// Fichier affiché (texte ou Coup d'œil), rechargé quand il change sur le disque.
    private let fileWatcher = FileChangeWatcher()
    private let placeholder = NSTextField(labelWithString: L("Sélectionnez un fichier texte dans le panneau pour le modifier ici."))
    private let statusLeft = NSTextField(labelWithString: "")
    private let statusRight = NSTextField(labelWithString: "")
    private var highlightWork: DispatchWorkItem?
    private var isLoading = false

    override func loadView() {
        Self.instances.add(self)
        let root = NSView()

        tabs.orientation = .horizontal
        tabs.spacing = 2
        let tabScroll = NSScrollView()
        tabScroll.documentView = tabs
        tabScroll.drawsBackground = false
        tabScroll.hasHorizontalScroller = false
        tabs.translatesAutoresizingMaskIntoConstraints = false

        // Barre d'icônes : le nom de chaque bouton reste dans son infobulle et pour l'accessibilité.
        let symbols: [(NSButton, String, NSColor?)] = [
            (wrapButton, "arrow.turn.down.left", nil),
            (findButton, "magnifyingglass", nil),
            (saveButton, "square.and.arrow.down", .controlAccentColor),
            (commitButton, "arrow.trianglehead.branch", .systemOrange),
        ]
        for (button, symbol, tint) in symbols {
            button.bezelStyle = .accessoryBarAction
            button.target = self
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            button.setAccessibilityLabel(button.title)
            button.title = ""
            button.imagePosition = .imageOnly
            button.contentTintColor = tint
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        }
        let modes = [("eye", L("Aperçu seul"), L("Aperçu seul (⌃⌘1)\nDouble-clic dans l’aperçu Markdown : modifier à cet endroit")),
                     ("rectangle.split.2x1", L("Texte et aperçu"), L("Texte et aperçu côte à côte (⌃⌘2)\n⌘-clic dans le texte ou l’aperçu : aller au même endroit de l’autre côté (Markdown, LaTeX)")),
                     ("chevron.left.forwardslash.chevron.right", L("Texte seul"), L("Texte seul (⌃⌘3)"))]
        modeControl.segmentCount = modes.count
        for (index, (symbol, label, tip)) in modes.enumerated() {
            modeControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium)), forSegment: index)
            modeControl.setToolTip(tip, forSegment: index)
            modeControl.setWidth(28, forSegment: index)
        }
        modeControl.trackingMode = .selectOne
        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(chooseMode(_:))
        modeControl.setAccessibilityLabel(L("Affichage"))
        wrapButton.image = Self.wrapIcon()
        wrapButton.action = #selector(toggleWrap(_:))
        wrapButton.setButtonType(.pushOnPushOff)
        wrapButton.toolTip = L("Retour à la ligne : couper les lignes longues à la largeur de l’éditeur")
        findButton.action = #selector(showSearch(_:))
        findButton.toolTip = L("Rechercher et remplacer dans le fichier (⌘F)")
        saveButton.action = #selector(saveDocument(_:))
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        saveButton.toolTip = L("Enregistrer (⌘S)")
        commitButton.action = #selector(saveCommitAndPush(_:))
        commitButton.keyEquivalent = "s"
        commitButton.keyEquivalentModifierMask = [.command, .option]
        commitButton.toolTip = L("Enregistrer, puis git add, commit et push de ce fichier (⌥⌘S)")
        commitButton.isHidden = true
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Fermer l’onglet"))!,
                             target: self, action: #selector(closeCurrent))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = L("Fermer l’onglet")
        let header = NSStackView(views: [tabScroll, modeControl, wrapButton, findButton, saveButton, commitButton, close])
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        tabScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureTextView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(textScroll)
        split.addArrangedSubview(preview)
        split.setHoldingPriority(.defaultLow + 1, forSubviewAt: 0)
        preview.isHidden = true
        preview.onOpenFile = { [weak self] url in self?.open(url) }
        preview.onJumpToLine = { [weak self] line in self?.goToLine(line) }
        preview.onMarkdownClick = { [weak self] line in self?.jumpFromPreview(to: line) }
        preview.onMarkdownDoubleClick = { [weak self] line in self?.jumpFromPreview(to: line) }
        preview.onPDFClick = { [weak self] page, point in self?.inverseSync(page: page, point: point) }
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.lineBreakMode = .byWordWrapping

        for label in [statusLeft, statusRight] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        statusLeft.lineBreakMode = .byTruncatingTail
        statusLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [statusLeft, NSView(), statusRight])
        status.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        let topLine = NSBox(), bottomLine = NSBox()
        topLine.boxType = .separator
        bottomLine.boxType = .separator
        for view in [header, topLine, split, placeholder, bottomLine, status] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 36),
            tabScroll.heightAnchor.constraint(equalTo: header.heightAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabScroll.contentView.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            topLine.topAnchor.constraint(equalTo: header.bottomAnchor),
            topLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: topLine.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bottomLine.topAnchor),
            placeholder.centerXAnchor.constraint(equalTo: split.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: split.centerYAnchor),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: split.widthAnchor, constant: -40),
            bottomLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 24),
        ])
        ThemeBackgroundView.install(.toolbar, in: root, bottom: root.safeAreaLayoutGuide.topAnchor)
        ThemeBackgroundView.install(.header, in: root, top: root.safeAreaLayoutGuide.topAnchor, bottom: topLine.bottomAnchor)
        ThemeBackgroundView.install(.panel, in: root, top: topLine.bottomAnchor)
        view = root
        showDocument(nil)
    }

    private func configureTextView() {
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = true
        textScroll.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = self
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width, .height]
        textView.onCommandClick = { [weak self] index in self?.forwardSync(at: index, flash: true) ?? false }
        applyWrap()
        textScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(textDidScroll), name: NSView.boundsDidChangeNotification, object: textScroll.contentView)
        let ruler = LineNumberRuler(textView: textView)
        ruler.onRevert = { [weak self] change in self?.revert(change) }
        self.ruler = ruler
        textScroll.verticalRulerView = ruler
        textScroll.hasVerticalRuler = true
        textScroll.rulersVisible = true
    }

    private static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    // MARK: Retour à la ligne

    private static var wordWrap: Bool {
        get { UserDefaults.standard.bool(forKey: "editorWordWrap") }
        set { UserDefaults.standard.set(newValue, forKey: "editorWordWrap") }
    }

    @objc private func toggleWrap(_ sender: Any?) {
        Self.wordWrap.toggle()
        applyWrap()
    }

    /// Lignes longues coupées à la largeur de l'éditeur, ou défilement horizontal (code).
    private func applyWrap() {
        let wrap = Self.wordWrap
        wrapButton.state = wrap ? .on : .off
        textScroll.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        textView.textContainer?.widthTracksTextView = wrap
        if wrap {
            textView.frame.size.width = textScroll.contentSize.width
            textView.textContainer?.containerSize = NSSize(width: textScroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.scrollRangeToVisible(textView.selectedRange())
        ruler?.needsDisplay = true
    }

    // MARK: Suivre la sélection du panneau

    /// Un seul fichier sélectionné : il s'ouvre (le dernier onglet non modifié est réutilisé, comme un aperçu).
    func follow(_ items: [FileItem]) {
        guard isViewLoaded, items.count == 1, let item = items.first, !item.isNavigableDirectory, item.url.isFileURL else { return }
        open(item.url)
    }

    func open(_ url: URL) {
        if let existing = documents.first(where: { $0.url == url }) {
            if !existing.isModified, let fresh = Self.load(url) { existing.text = fresh.text; existing.encoding = fresh.encoding }
            showDocument(existing)
            loadCommittedLines(existing)
            return
        }
        guard let loaded = Self.load(url) else {
            showQuickLook(url)
            return
        }
        let document = Document(url: url, text: loaded.text, encoding: loaded.encoding)
        if let reusable = current ?? lastShown, !reusable.isModified, let index = documents.firstIndex(where: { $0 === reusable }) {
            documents[index] = document
        } else {
            documents.append(document)
            if documents.count > 10, let index = documents.firstIndex(where: { !$0.isModified && $0 !== current }) { documents.remove(at: index) }
        }
        showDocument(document)
        lookUpGit(document)
    }

    /// Texte du fichier (UTF-8, sinon Latin-1), ou `nil` pour un fichier binaire ou trop gros.
    private static func load(_ url: URL) -> (text: String, encoding: String.Encoding)? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size < 5_000_000, let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        let looksText = type?.conforms(to: .text) == true || SyntaxHighlighter.language(for: url) != nil || type == nil
        guard looksText, !data.prefix(8000).contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        if let text = String(data: data, encoding: .isoLatin1) { return (text, .isoLatin1) }
        return nil
    }

    private func showQuickLook(_ url: URL) {
        storeSelection()
        current = nil
        displayedURL = url
        func place(_ preview: NSView) {
            preview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: split.topAnchor),
                preview.leadingAnchor.constraint(equalTo: split.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: split.trailingAnchor),
                preview.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            ])
        }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true, let document = PDFDocument(url: url) {
            if pdfViewer == nil {
                let viewer = PDFView()
                viewer.autoScales = true
                viewer.displayMode = .singlePageContinuous
                viewer.backgroundColor = .clear
                place(viewer)
                pdfViewer = viewer
            }
            pdfViewer?.document = document
            pdfViewer?.isHidden = false
            quickLook?.isHidden = true
            quickLook?.previewItem = nil
            fileWatcher.onChange = { [weak self] in
                if let fresh = PDFDocument(url: url) { self?.pdfViewer?.replaceDocument(fresh) }
            }
        } else {
            if quickLook == nil, let preview = QLPreviewView(frame: .zero, style: .normal) {
                place(preview)
                quickLook = preview
            }
            quickLook?.previewItem = url as NSURL
            quickLook?.isHidden = false
            pdfViewer?.isHidden = true
            pdfViewer?.document = nil
            fileWatcher.onChange = { [weak self] in self?.quickLook?.refreshPreviewItem() }
        }
        fileWatcher.watch(url)
        split.isHidden = true
        placeholder.isHidden = true
        modeControl.isHidden = true
        saveButton.isHidden = true
        commitButton.isHidden = true
        findButton.isHidden = true
        statusLeft.stringValue = L("Aperçu · \(url.lastPathComponent)")
        statusRight.stringValue = ""
        rebuildTabs()
    }

    private func showDocument(_ document: Document?) {
        storeSelection()
        current = document
        displayedURL = document?.url
        if let document { lastShown = document }
        quickLook?.isHidden = true
        quickLook?.previewItem = nil
        pdfViewer?.isHidden = true
        pdfViewer?.document = nil
        fileWatcher.onChange = { [weak self] in
            if let document, document === self?.current { self?.reloadFromDisk(document) }
        }
        fileWatcher.watch(document?.url)
        split.isHidden = document == nil
        placeholder.isHidden = document != nil
        modeControl.isHidden = document?.previewKind == nil
        saveButton.isHidden = document == nil
        findButton.isHidden = document == nil
        if let document {
            isLoading = true
            textView.string = document.text
            textView.undoManager?.removeAllActions()
            applyHighlight()
            isLoading = false
            textView.setSelectedRange(NSRange(location: min(document.selection.location, (document.text as NSString).length), length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
        updateGutter()
        updatePreview(compileIfMissing: true)
        updateState()
        rebuildTabs()
    }

    /// Le fichier a changé sur le disque (git, autre éditeur, script) : relu au même endroit, sauf modifications en cours.
    private func reloadFromDisk(_ document: Document) {
        guard let fresh = Self.load(document.url), fresh.text != document.text else { return }
        if document.isModified {
            statusRight.stringValue = L("Modifié sur le disque · vos modifications sont conservées")
            return
        }
        let selection = textView.selectedRange()
        let origin = textScroll.contentView.bounds.origin
        document.text = fresh.text
        document.encoding = fresh.encoding
        isLoading = true
        textView.string = fresh.text
        applyHighlight()
        isLoading = false
        let length = (fresh.text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.scroll(origin)
        updateGutter()
        updatePreview()
        updateState()
    }

    private func storeSelection() {
        current?.selection = textView.selectedRange()
    }

    // MARK: Onglets

    private func rebuildTabs() {
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for document in documents {
            let title = document.url.lastPathComponent + (document.isModified ? " ●" : "")
            let button = NSButton(title: title, target: self, action: #selector(selectTab(_:)))
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
            button.setButtonType(.pushOnPushOff)
            button.state = document === current ? .on : .off
            button.toolTip = document.url.path
            button.tag = documents.firstIndex { $0 === document } ?? 0
            tabs.addArrangedSubview(button)
        }
        for url in Self.relatedFiles(of: displayedURL) {
            let button = NSButton(title: url.lastPathComponent, target: self, action: #selector(openRelated(_:)))
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
            button.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = L("Ouvrir \(url.lastPathComponent)")
            button.identifier = NSUserInterfaceItemIdentifier(url.path)
            tabs.addArrangedSubview(button)
        }
    }

    /// Icône du retour à la ligne : lignes contre une marge, la deuxième revient à gauche (pas de symbole système adapté).
    private static func wrapIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            func stroke(_ path: NSBezierPath, width: CGFloat = 1.6) {
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            let margin = NSBezierPath()
            margin.move(to: NSPoint(x: 14.5, y: 1.5))
            margin.line(to: NSPoint(x: 14.5, y: 14.5))
            margin.setLineDash([1.5, 1.5], count: 2, phase: 0)
            margin.lineWidth = 1.2
            margin.stroke()
            let first = NSBezierPath()
            first.move(to: NSPoint(x: 1.5, y: 3))
            first.line(to: NSPoint(x: 12, y: 3))
            stroke(first)
            let hook = NSBezierPath()
            hook.move(to: NSPoint(x: 1.5, y: 7.5))
            hook.line(to: NSPoint(x: 10, y: 7.5))
            hook.appendArc(withCenter: NSPoint(x: 10, y: 9.75), radius: 2.25, startAngle: -90, endAngle: 90, clockwise: false)
            hook.line(to: NSPoint(x: 6.5, y: 12))
            stroke(hook)
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 8.5, y: 10))
            head.line(to: NSPoint(x: 6.2, y: 12))
            head.line(to: NSPoint(x: 8.5, y: 14))
            stroke(head)
            let last = NSBezierPath()
            last.move(to: NSPoint(x: 1.5, y: 12))
            last.line(to: NSPoint(x: 3.5, y: 12))
            stroke(last)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("Retour à la ligne")
        return image
    }

    /// Documents et leurs sources : un PDF propose le .tex, le .docx… du même nom, et inversement.
    private static let documentExtensions: Set<String> = [
        "pdf", "tex", "typ", "md", "markdown", "rmd", "qmd", "ipynb", "doc", "docx", "odt", "rtf", "pages",
        "ppt", "pptx", "odp", "key", "xls", "xlsx", "ods", "numbers", "html", "htm", "svg", "dot", "drawio",
    ]

    /// Fichiers du même dossier et du même nom de base, limités aux documents et à leurs sources (pas de .log, .aux…).
    private static func relatedFiles(of url: URL?) -> [URL] {
        guard let url, url.isFileURL, documentExtensions.contains(url.pathExtension.lowercased()) else { return [] }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.sorted().compactMap { name in
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            guard candidate.lastPathComponent != url.lastPathComponent,
                  candidate.deletingPathExtension().lastPathComponent.lowercased() == base,
                  documentExtensions.contains(candidate.pathExtension.lowercased()) else { return nil }
            return candidate
        }
    }

    @objc private func openRelated(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        open(URL(fileURLWithPath: path))
    }

    @objc private func selectTab(_ sender: NSButton) {
        guard documents.indices.contains(sender.tag) else { return }
        showDocument(documents[sender.tag])
    }

    @objc private func closeCurrent() {
        guard let document = current else {
            showDocument(documents.last)
            return
        }
        if document.isModified {
            let alert = NSAlert()
            alert.messageText = L("Enregistrer les modifications de « \(document.url.lastPathComponent) » ?")
            alert.addButton(withTitle: L("Enregistrer"))
            alert.addButton(withTitle: L("Annuler"))
            alert.addButton(withTitle: L("Ne pas enregistrer"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: guard save(document) else { return }
            case .alertSecondButtonReturn: return
            default: break
            }
        }
        documents.removeAll { $0 === document }
        current = nil
        showDocument(documents.last)
    }

    // MARK: Édition

    func textDidChange(_ notification: Notification) {
        guard !isLoading, let document = current else { return }
        document.text = textView.string
        if !document.isModified {
            document.isModified = true
            rebuildTabs()
        }
        updateState()
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyHighlight()
            self?.updateGutter()
            if self?.current?.previewKind?.isCompiled == false { self?.updatePreview() }
        }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatus()
    }

    /// Couleurs de la coloration syntaxique appliquées sans toucher au texte (l'annulation reste intacte).
    private func applyHighlight() {
        guard let document = current, let storage = textView.textStorage else { return }
        let text = textView.string
        let length = (text as NSString).length
        storage.beginEditing()
        storage.setAttributes([.font: Self.font, .foregroundColor: NSColor.textColor], range: NSRange(location: 0, length: length))
        if length < 400_000, let language = SyntaxHighlighter.language(for: document.url) {
            let dark = Theme.isDark(view.effectiveAppearance)
            let colored = SyntaxHighlighter.highlight(text, language: language, dark: dark)
            colored.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: min(length, colored.length))) { value, range, _ in
                if let color = value as? NSColor, color != NSColor.textColor { storage.addAttribute(.foregroundColor, value: color, range: range) }
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.textColor]
    }

    private func updateState() {
        saveButton.isEnabled = current?.isModified == true
        let root = current?.gitRoot ?? nil
        commitButton.isHidden = current == nil || root == nil
        updateStatus()
    }

    private func updateStatus() {
        guard let document = current else {
            if quickLook?.isHidden != false, pdfViewer?.isHidden != false { statusLeft.stringValue = ""; statusRight.stringValue = "" }
            return
        }
        let text = textView.string as NSString
        let location = min(textView.selectedRange().location, text.length)
        let before = text.substring(to: location)
        let line = before.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let lastNewline = (before as NSString).range(of: "\n", options: .backwards).location
        let column = lastNewline == NSNotFound ? location + 1 : location - lastNewline
        let language = SyntaxHighlighter.language(for: document.url)?.title ?? L("Texte")
        let endings = document.text.contains("\r\n") ? "CRLF" : "LF"
        let encoding = document.encoding == .utf8 ? "UTF-8" : "ISO Latin-1"
        statusLeft.stringValue = switch mode(for: document) {
        case .preview where document.previewKind == .markdown: L("Aperçu · \(document.url.lastPathComponent) · double-clic pour modifier à cet endroit")
        case .preview: L("Aperçu · \(document.url.lastPathComponent)")
        default: L("\(language) · \(encoding) · \(endings) · Ligne \(line), colonne \(column)")
        }
        let root = document.gitRoot ?? nil
        statusRight.stringValue = root.map { document.isModified ? L("Git : \($0.lastPathComponent) · non enregistré") : L("Git : \($0.lastPathComponent)") } ?? (document.isModified ? L("Non enregistré") : "")
    }

    // MARK: Enregistrer

    @objc func saveDocument(_ sender: Any?) {
        guard let document = current else { return }
        _ = save(document)
    }

    @discardableResult
    private func save(_ document: Document) -> Bool {
        if document === current { document.text = textView.string }
        do {
            guard let data = document.text.data(using: document.encoding) else {
                throw NSError(domain: "iExplorer", code: 3, userInfo: [NSLocalizedDescriptionKey: L("Le texte contient des caractères impossibles à écrire dans l’encodage du fichier.")])
            }
            try data.write(to: document.url, options: .atomic)
            document.isModified = false
            // Sa propre écriture n'est pas un changement extérieur.
            if document === current { fileWatcher.watch(document.url) }
            rebuildTabs()
            updateState()
            if document === current, document.previewKind?.isCompiled == true { compile(document) }
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Le fichier est-il suivi par Git ? (question posée en arrière-plan, une fois par document)
    private func lookUpGit(_ document: Document) {
        guard document.gitRoot == nil else { return }
        guard GitService.shared.isAvailable, let root = GitService.shared.repositoryRoot(for: document.url) else {
            document.gitRoot = .some(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let path = document.url.resolvingSymlinksInPath().path
            let tracked = GitCommand.run(["ls-files", "--error-unmatch", "--", path], in: root).succeeded
            DispatchQueue.main.async {
                document.gitRoot = .some(tracked ? root : nil)
                if document === self?.current { self?.updateState() }
                self?.loadCommittedLines(document)
            }
        }
    }

    @objc func saveCommitAndPush(_ sender: Any?) {
        guard let document = current, let root = document.gitRoot ?? nil else { return }
        if document.isModified { guard save(document) else { return } }
        let alert = NSAlert()
        alert.messageText = L("Commit et push de « \(document.url.lastPathComponent) »")
        alert.informativeText = L("Seul ce fichier est ajouté au commit, puis poussé vers la branche distante.")
        let field = NSTextField(string: L("Mise à jour de \(document.url.lastPathComponent)"))
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Commit et push"))
        alert.addButton(withTitle: L("Annuler"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { NSSound.beep(); return }
        let path = document.url.resolvingSymlinksInPath().path
        commitButton.isEnabled = false
        statusRight.stringValue = L("Commit et push en cours…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure: String?
            let add = GitCommand.run(["add", "--", path], in: root)
            if !add.succeeded { failure = add.error }
            if failure == nil {
                let commit = GitCommand.run(["commit", "-m", message, "--", path], in: root)
                if !commit.succeeded { failure = commit.error.isEmpty ? commit.output : commit.error }
            }
            var pushed = false
            if failure == nil {
                let push = GitCommand.run(["push"], in: root)
                pushed = push.succeeded
                if !push.succeeded { failure = L("Le commit est fait, mais le push a échoué :\n") + push.error }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.commitButton.isEnabled = true
                self.updateStatus()
                if let failure {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Git"
                    alert.informativeText = failure.trimmingCharacters(in: .whitespacesAndNewlines)
                    alert.runModal()
                } else if pushed {
                    self.statusRight.stringValue = L("Commit et push effectués")
                }
                self.loadCommittedLines(document)
            }
        }
    }

    // MARK: Aperçu à côté

    private static var previewVisible: Bool {
        get { UserDefaults.standard.object(forKey: "editorPreviewVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "editorPreviewVisible") }
    }

    /// Mode d'affichage du document : celui choisi pour lui, sinon aperçu seul pour le Markdown,
    /// et le dernier choix (texte seul ou côte à côte) pour les autres types.
    private func mode(for document: Document?) -> EditorMode {
        guard let document, let kind = document.previewKind else { return .source }
        if let mode = document.mode { return mode }
        if kind == .markdown { return .preview }
        return Self.previewVisible ? .mixed : .source
    }

    /// Le document affiché a un aperçu : le sélecteur Aperçu / Mixte / Source s'applique.
    var canChooseMode: Bool { current?.previewKind != nil && !split.isHidden }
    var currentMode: EditorMode { mode(for: current) }

    func setMode(_ mode: EditorMode) {
        guard let document = current, let kind = document.previewKind else { return }
        document.mode = mode
        if kind != .markdown { Self.previewVisible = mode != .source }
        updatePreview(compileIfMissing: true)
        updateStatus()
        if mode != .preview { view.window?.makeFirstResponder(textView) }
    }

    @objc private func chooseMode(_ sender: NSSegmentedControl) {
        setMode(EditorMode(rawValue: sender.selectedSegment) ?? .mixed)
    }

    /// Montre ou cache l'aperçu selon le fichier, puis le met à jour (sauf PDF compilé : seulement s'il manque).
    private func updatePreview(compileIfMissing: Bool = false) {
        guard isViewLoaded else { return }
        let kind = current?.previewKind
        let mode = mode(for: current)
        let visible = mode != .source
        modeControl.selectedSegment = mode.rawValue
        let textHidden = mode == .preview
        if preview.isHidden == visible || textScroll.isHidden != textHidden {
            if textHidden, view.window?.firstResponder === textView { view.window?.makeFirstResponder(nil) }
            preview.isHidden = !visible
            textScroll.isHidden = textHidden
            split.adjustSubviews()
            // Juste après l'installation de l'éditeur, la vue partagée n'a pas encore sa largeur.
            DispatchQueue.main.async { [split] in
                if mode == .mixed { split.setPosition(split.bounds.width / 2, ofDividerAt: 0) } else { split.adjustSubviews() }
            }
        }
        wrapButton.isEnabled = !textHidden
        findButton.isEnabled = !textHidden
        guard visible, let document = current, let kind else { return }
        let text = textView.string
        switch kind {
        case .markdown: preview.showMarkdown(text, base: document.url)
        case .csv: preview.showCSV(text)
        case .json: preview.showJSON(text)
        case .latex, .typst:
            let root = DocumentCompiler.root(for: document.url, text: text)
            let pdf = DocumentCompiler.pdf(for: root)
            let pdfDate = (try? pdf.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let pdfDate {
                preview.showPDF(pdf)
                let sourceDate = (try? root.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if compileIfMissing, sourceDate > pdfDate { compile(document) }
            } else {
                preview.showMessage(L("Enregistrez (⌘S) pour compiler et voir le PDF ici."))
                if compileIfMissing, (kind == .latex ? ExternalTool.latex : .typst).isInstalled { compile(document) }
            }
        }
    }

    private var compiling = false

    private func compile(_ document: Document) {
        guard let kind = document.previewKind, kind.isCompiled, mode(for: document) != .source, !compiling else { return }
        let root = DocumentCompiler.root(for: document.url, text: document.text)
        compiling = true
        let start = Date()
        statusRight.stringValue = L("Compilation de \(root.lastPathComponent)…")
        DocumentCompiler.compile(root, kind: kind) { [weak self] result in
            guard let self else { return }
            self.compiling = false
            self.updateStatus()
            guard document === self.current else { return }
            switch result {
            case .success(let pdf):
                self.preview.showPDF(pdf)
                let seconds = Date().timeIntervalSince(start).formatted(.number.precision(.fractionLength(1)))
                self.preview.showBanner(L("Compilé en \(seconds) s"), error: false)
            case .failure(let failure):
                self.preview.showBanner(failure.summary, error: true, log: failure.log.isEmpty ? nil : failure.log, line: failure.line)
            }
        }
    }

    // MARK: Synchronisation texte ↔ aperçu

    /// Ligne (1 = première) du caractère `index`.
    private func lineNumber(at index: Int) -> Int {
        let text = textView.string as NSString
        var line = 1
        var location = 0
        let end = min(index, text.length)
        while location < end {
            let found = text.range(of: "\n", options: .literal, range: NSRange(location: location, length: end - location))
            guard found.location != NSNotFound else { break }
            line += 1
            location = NSMaxRange(found)
        }
        return line
    }

    /// Montre dans l'aperçu l'endroit produit par le caractère `index` ; `false` si l'aperçu ne sait pas faire.
    @discardableResult
    private func forwardSync(at index: Int, flash: Bool) -> Bool {
        guard let document = current, let kind = document.previewKind, mode(for: document) == .mixed else { return false }
        let line = lineNumber(at: index)
        switch kind {
        case .markdown:
            preview.scrollMarkdown(toLine: line, flash: flash)
            return true
        case .latex:
            let root = DocumentCompiler.root(for: document.url, text: textView.string)
            let pdf = DocumentCompiler.pdf(for: root)
            guard SyncTeX.isAvailable(for: pdf) else {
                preview.showBanner(L("Pas de données SyncTeX : enregistrez (⌘S) pour recompiler"), error: true)
                return true
            }
            SyncTeX.forward(line: line, source: document.url, pdf: pdf) { [weak self] boxes in
                if boxes.isEmpty { self?.preview.showBanner(L("Ligne \(line) introuvable dans le PDF"), error: true) } else { self?.preview.showSyncTeX(boxes) }
            }
            return true
        default:
            return false
        }
    }

    /// ⌘-clic dans le PDF : ouvre le fichier source concerné et va à la ligne.
    private func inverseSync(page: Int, point: CGPoint) {
        guard let document = current, document.previewKind == .latex else { return }
        let pdf = DocumentCompiler.pdf(for: DocumentCompiler.root(for: document.url, text: textView.string))
        SyncTeX.inverse(page: page, point: point, pdf: pdf) { [weak self] found in
            guard let self, let found else { NSSound.beep(); return }
            if found.url != self.current?.url.standardizedFileURL {
                guard FileManager.default.fileExists(atPath: found.url.path) else { NSSound.beep(); return }
                // Le PDF reste celui du fichier principal : l'aperçu ne doit pas changer pour le fichier inclus.
                self.open(found.url)
            }
            self.goToLine(found.line)
        }
    }

    private func jumpFromPreview(to line: Int) {
        followScrollPaused = true
        goToLine(line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.followScrollPaused = false }
    }

    /// L'aperçu Markdown suit le défilement du texte.
    @objc private func textDidScroll() {
        guard !followScrollPaused, !isLoading, current?.previewKind == .markdown, mode(for: current) == .mixed,
              let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let visible = textView.visibleRect
        if visible.maxY >= textView.bounds.maxY - 2, visible.minY > 0 {
            preview.scrollMarkdown(toLine: 0, atEnd: true)
            return
        }
        let point = NSPoint(x: 0, y: max(0, visible.minY - textView.textContainerInset.height))
        let glyph = layout.glyphIndex(for: point, in: container)
        preview.scrollMarkdown(toLine: lineNumber(at: layout.characterIndexForGlyph(at: glyph)))
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at index: Int) -> NSMenu? {
        guard let kind = current?.previewKind, kind == .markdown || kind == .latex, mode(for: current) == .mixed else { return menu }
        let item = NSMenuItem(title: kind == .latex ? L("Afficher dans le PDF") : L("Afficher dans l’aperçu"), action: #selector(showInPreview(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = index
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func showInPreview(_ sender: NSMenuItem) {
        forwardSync(at: sender.representedObject as? Int ?? textView.selectedRange().location, flash: true)
    }

    private func goToLine(_ line: Int) {
        if mode(for: current) == .preview { setMode(.mixed) }
        let text = textView.string as NSString
        var location = 0
        for _ in 1..<max(1, line) {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            guard NSMaxRange(range) < text.length else { break }
            location = NSMaxRange(range)
        }
        let range = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: Marques Git dans la marge

    /// Version du dernier commit (git show HEAD:chemin), lue en arrière-plan.
    private func loadCommittedLines(_ document: Document) {
        guard let root = document.gitRoot ?? nil else {
            document.committedLines = nil
            if document === current { updateGutter() }
            return
        }
        let file = document.url.resolvingSymlinksInPath().path
        let base = root.resolvingSymlinksInPath().path
        guard file.hasPrefix(base + "/") else { return }
        let relative = String(file.dropFirst(base.count + 1))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let show = GitCommand.run(["show", "HEAD:" + relative], in: root)
            DispatchQueue.main.async {
                document.committedLines = show.succeeded ? Self.lines(show.output) : nil
                if document === self?.current { self?.updateGutter() }
            }
        }
    }

    private static func lines(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private func updateGutter() {
        guard let ruler else { return }
        guard let document = current, let committed = document.committedLines else {
            ruler.changes = [:]
            return
        }
        let lines = Self.lines(textView.string)
        guard lines.count + committed.count < 40_000 else {
            ruler.changes = [:]
            return
        }
        ruler.changes = GitLineChange.compute(old: committed, new: lines)
    }

    /// Rétablit les lignes du dernier commit à la place des lignes modifiées (annulable par ⌘Z).
    private func revert(_ change: GitLineChange) {
        let text = textView.string as NSString
        var location = 0
        var line = 0
        while line < change.line, location < text.length {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
            line += 1
        }
        var end = location
        for _ in 0..<change.count where end < text.length {
            end = NSMaxRange(text.lineRange(for: NSRange(location: end, length: 0)))
        }
        var replacement = change.oldLines.map { $0 + "\n" }.joined()
        if end == text.length, !text.hasSuffix("\n"), change.count > 0 { replacement = String(replacement.dropLast()) }
        if location == text.length, location > 0, !text.hasSuffix("\n") { replacement = "\n" + String(replacement.dropLast()) }
        let range = NSRange(location: location, length: end - location)
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        applyHighlight()
        updateGutter()
    }

    /// ⌘F dans l'éditeur : barre de recherche du texte (et non la recherche du panneau).
    @objc func showSearch(_ sender: Any?) {
        guard current != nil else { return }
        if mode(for: current) == .preview { setMode(.mixed) }
        view.window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        textView.performTextFinderAction(item)
    }
}

/// Lignes changées depuis le dernier commit : ajoutées, modifiées, ou supprimées (marque entre deux lignes).
struct GitLineChange {
    enum Kind { case added, modified, deleted }
    let kind: Kind
    /// Première ligne concernée (0 = première ligne du texte actuel).
    let line: Int
    /// Nombre de lignes actuelles concernées (0 pour une suppression).
    let count: Int
    let oldLines: [String]

    var color: NSColor {
        switch kind {
        case .added: .systemGreen
        case .modified: .systemBlue
        case .deleted: .systemRed
        }
    }

    /// Changements indexés par ligne actuelle (chaque ligne d'un bloc pointe vers le même changement).
    static func compute(old: [String], new: [String]) -> [Int: GitLineChange] {
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Int: GitLineChange] = [:]
        var i = 0, j = 0
        while i < old.count || j < new.count {
            let startOld = i, startNew = j
            while i < old.count, removed.contains(i) { i += 1 }
            while j < new.count, inserted.contains(j) { j += 1 }
            if i == startOld, j == startNew {
                i += 1
                j += 1
                continue
            }
            let oldLines = Array(old[startOld..<i])
            let count = j - startNew
            let kind: Kind = count == 0 ? .deleted : (oldLines.isEmpty ? .added : .modified)
            let change = GitLineChange(kind: kind, line: startNew, count: count, oldLines: oldLines)
            if count == 0 {
                // Une suppression se dessine en haut de la ligne qui suit (ou en bas de la dernière).
                if result[startNew] == nil { result[startNew] = change }
            } else {
                for line in startNew..<j { result[line] = change }
            }
        }
        return result
    }
}

/// Numéros de ligne dans la marge de l'éditeur, avec les marques Git (clic : voir et rétablir l'ancienne version).
private final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    var changes: [Int: GitLineChange] = [:] { didSet { needsDisplay = true } }
    var onRevert: ((GitLineChange) -> Void)?
    private var popover: NSPopover?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                                                         .foregroundColor: NSColor.tertiaryLabelColor]
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = text.substring(to: characters.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var index = characters.location
        let inset = textView.textContainerInset.height
        var lastRect = NSRect.zero
        while index <= NSMaxRange(characters) && index <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
            let glyph = layout.glyphIndexForCharacter(at: min(index, max(0, text.length - 1)))
            // Ligne vide après le dernier retour à la ligne : fragment « supplémentaire » du gestionnaire de mise en page.
            let atEnd = index == text.length && text.length > 0
            var rectLine = text.length == 0 ? layout.extraLineFragmentRect
                : atEnd ? layout.extraLineFragmentRect : layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            rectLine.origin.y += inset - visible.minY
            lastRect = rectLine
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: rectLine.minY + (rectLine.height - size.height) / 2), withAttributes: attributes)
            // Ligne coupée (retour à la ligne) : la marque Git couvre tous ses fragments.
            var marked = rectLine
            if !atEnd, text.length > 0 {
                let glyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
                marked.size.height = max(rectLine.height, layout.boundingRect(forGlyphRange: glyphs, in: container).height)
            }
            drawMarker(for: line - 1, in: marked)
            if text.length == 0 || NSMaxRange(lineRange) <= index { break }
            index = NSMaxRange(lineRange)
            line += 1
            if index == text.length, !text.hasSuffix("\n") { break }
        }
        // Lignes supprimées à la toute fin du fichier.
        if let change = changes[line], change.kind == .deleted, index >= text.length {
            drawDeletion(change, at: lastRect.maxY)
        }
    }

    private func drawMarker(for line: Int, in rect: NSRect) {
        guard let change = changes[line] else { return }
        if change.kind == .deleted {
            drawDeletion(change, at: rect.minY)
        } else {
            change.color.setFill()
            NSBezierPath(rect: NSRect(x: ruleThickness - 5, y: rect.minY, width: 3, height: rect.height)).fill()
        }
    }

    private func drawDeletion(_ change: GitLineChange, at y: CGFloat) {
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: ruleThickness - 7, y: y - 4))
        triangle.line(to: NSPoint(x: ruleThickness - 1, y: y))
        triangle.line(to: NSPoint(x: ruleThickness - 7, y: y + 4))
        triangle.close()
        change.color.setFill()
        triangle.fill()
    }

    /// Ligne (0 = première) sous le point cliqué.
    private func line(at point: NSPoint) -> Int? {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        let text = textView.string as NSString
        guard text.length > 0 else { return 0 }
        let y = point.y + textView.visibleRect.minY - textView.textContainerInset.height
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let character = min(layout.characterIndexForGlyph(at: glyph), text.length)
        let lineCount = text.substring(to: character).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return y > fragment.maxY ? lineCount + 1 : lineCount
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x > ruleThickness - 12, let line = line(at: point),
              let change = changes[line] ?? changes[line + 1].flatMap({ $0.kind == .deleted ? $0 : nil }) else {
            super.mouseDown(with: event)
            return
        }
        showPopover(for: change, at: point)
    }

    private func showPopover(for change: GitLineChange, at point: NSPoint) {
        let title: String
        switch change.kind {
        case .added: title = change.count > 1 ? L("\(change.count) lignes ajoutées depuis le dernier commit") : L("Ligne ajoutée depuis le dernier commit")
        case .modified: title = L("Version du dernier commit")
        case .deleted: title = change.oldLines.count > 1 ? L("\(change.oldLines.count) lignes supprimées") : L("Ligne supprimée")
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        var views: [NSView] = [label]
        if !change.oldLines.isEmpty {
            let scroll = NSTextView.scrollableTextView()
            scroll.hasHorizontalScroller = true
            if let text = scroll.documentView as? NSTextView {
                text.string = change.oldLines.joined(separator: "\n")
                text.isEditable = false
                text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                text.textColor = change.kind == .deleted ? .systemRed : .labelColor
                text.backgroundColor = change.color.withAlphaComponent(0.08)
            }
            let height = min(220, CGFloat(change.oldLines.count) * 15 + 12)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.widthAnchor.constraint(equalToConstant: 460).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
            views.append(scroll)
        }
        let button = NSButton(title: change.kind == .added ? L("Supprimer ces lignes") : L("Rétablir la version du commit"), target: self, action: #selector(revertFromPopover(_:)))
        button.controlSize = .small
        views.append(button)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let controller = NSViewController()
        controller.view = stack
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        pendingChange = change
        self.popover = popover
        popover.show(relativeTo: NSRect(x: ruleThickness - 4, y: point.y - 2, width: 4, height: 4), of: self, preferredEdge: .maxX)
    }

    private var pendingChange: GitLineChange?

    @objc private func revertFromPopover(_ sender: Any?) {
        popover?.close()
        if let change = pendingChange { onRevert?(change) }
        pendingChange = nil
    }
}

/// Texte de l'éditeur : ⌘-clic place le curseur et demande la synchronisation avec l'aperçu.
private final class SourceTextView: NSTextView {
    /// Renvoie `false` pour garder le comportement habituel du ⌘-clic (sélection multiple).
    var onCommandClick: ((Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), let onCommandClick else { return super.mouseDown(with: event) }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard onCommandClick(index) else { return super.mouseDown(with: event) }
        setSelectedRange(NSRange(location: index, length: 0))
    }
}
