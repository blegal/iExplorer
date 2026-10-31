import AppKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

/// Fichiers que l'éditeur sait montrer à côté du texte.
enum EditorPreviewKind: Equatable {
    case markdown, latex, typst, csv, json

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": self = .markdown
        case "tex", "ltx": self = .latex
        case "typ": self = .typst
        case "csv", "tsv", "tab": self = .csv
        case "json", "geojson": self = .json
        default: return nil
        }
    }

    /// Aperçu produit par un compilateur à l'enregistrement (et non mis à jour à la frappe).
    var isCompiled: Bool { self == .latex || self == .typst }
}

/// Volet d'aperçu de l'éditeur : rendu Markdown, PDF compilé (LaTeX, Typst), tableau CSV, arbre JSON.
final class EditorPreviewView: NSView, WKNavigationDelegate, WKScriptMessageHandler, NSTableViewDataSource, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Lien vers un fichier local cliqué dans l'aperçu Markdown.
    var onOpenFile: ((URL) -> Void)?
    /// Clic sur « Aller à la ligne » dans le journal d'erreur.
    var onJumpToLine: ((Int) -> Void)?
    /// ⌘-clic dans l'aperçu Markdown : ligne (1 = première) du bloc cliqué.
    var onMarkdownClick: ((Int) -> Void)?
    /// ⌘-clic dans le PDF : page (0 = première) et point, origine en haut à gauche.
    var onPDFClick: ((Int, CGPoint) -> Void)?

    private var webView: WKWebView?
    private var webReady = false
    private var pendingHTML: String?
    private var pdfView: SyncPDFView?
    private var syncMarks: [(PDFPage, PDFAnnotation)] = []
    private var shownPDF: URL?
    private var tableScroll: NSScrollView?
    private var tableView: NSTableView?
    private var rows: [[String]] = []
    private var outlineScroll: NSScrollView?
    private var outlineView: NSOutlineView?
    private var jsonRoot: JSONNode?
    private let message = NSTextField(wrappingLabelWithString: "")
    private let banner = NSButton(title: "", target: nil, action: nil)
    private var bannerLog: String?
    private var bannerLine: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.isHidden = true
        banner.isBordered = false
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 6
        banner.contentTintColor = .white
        banner.font = .systemFont(ofSize: 11.5, weight: .medium)
        banner.lineBreakMode = .byTruncatingTail
        banner.target = self
        banner.action = #selector(showLog)
        banner.isHidden = true
        for view in [message, banner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            banner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            banner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            banner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            banner.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func activate(_ shown: NSView?) {
        for view in [webView, pdfView, tableScroll, outlineScroll, message] as [NSView?] {
            view?.isHidden = view !== shown
        }
        addSubview(banner, positioned: .above, relativeTo: nil)
    }

    private func embed(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: message)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func showMessage(_ text: String) {
        message.stringValue = text
        activate(message)
    }

    // MARK: Bandeau d'erreur

    /// Bandeau rouge (erreur) ou vert (réussite) en bas de l'aperçu ; un clic montre le journal.
    func showBanner(_ text: String, error: Bool, log: String? = nil, line: Int? = nil) {
        banner.title = text
        banner.layer?.backgroundColor = (error ? NSColor.systemRed : NSColor.systemGreen).withAlphaComponent(0.88).cgColor
        banner.toolTip = log == nil ? nil : "Afficher le journal"
        bannerLog = log
        bannerLine = line
        banner.isHidden = false
        addSubview(banner, positioned: .above, relativeTo: nil)
        if !error {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if self?.banner.title == text { self?.hideBanner() }
            }
        }
    }

    func hideBanner() {
        banner.isHidden = true
        bannerLog = nil
        bannerLine = nil
    }

    @objc private func showLog() {
        guard let log = bannerLog else { return }
        let alert = NSAlert()
        alert.messageText = banner.title
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 560, height: 280)
        if let text = scroll.documentView as? NSTextView {
            text.string = log
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.scrollToEndOfDocument(nil)
        }
        alert.accessoryView = scroll
        if let line = bannerLine { alert.addButton(withTitle: "Aller à la ligne \(line)") }
        alert.addButton(withTitle: "Fermer")
        if alert.runModal() == .alertFirstButtonReturn, let line = bannerLine { onJumpToLine?(line) }
    }

    // MARK: Markdown

    func showMarkdown(_ text: String, base: URL) {
        hideBanner()
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
            // Le contenu du fichier ne peut pas exécuter de scripts ; seule l'app met la page à jour.
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            // Script de l'app, dans un monde à part : ⌘-clic sur un bloc → sa ligne dans le source.
            let click = """
            document.addEventListener('click', function (event) {
                if (!event.metaKey) return;
                var block = event.target.closest && event.target.closest('[data-line]');
                if (!block) return;
                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.sync.postMessage(Number(block.dataset.line));
            }, true);
            """
            configuration.userContentController.addUserScript(WKUserScript(source: click, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
            configuration.userContentController.add(WeakScriptHandler(self), contentWorld: .defaultClient, name: "sync")
            let web = WKWebView(frame: bounds, configuration: configuration)
            web.navigationDelegate = self
            web.setValue(false, forKey: "drawsBackground")
            embed(web)
            webView = web
            web.loadHTMLString(MarkdownHTML.page, baseURL: nil)
        }
        let html = MarkdownHTML.render(text, base: base.deletingLastPathComponent())
        activate(webView)
        if webReady { inject(html) } else { pendingHTML = html }
    }

    /// Remplace le contenu sans recharger la page : la position de lecture est conservée.
    private func inject(_ html: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [html]), let literal = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("document.getElementById('content').innerHTML = \(literal)[0];")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let line = (message.body as? NSNumber)?.intValue { onMarkdownClick?(line) }
    }

    /// Fait défiler l'aperçu Markdown pour que la ligne `line` du source soit en haut (interpolée entre les blocs).
    /// `flash` surligne brièvement le bloc ; `atEnd` colle au bas de la page quand le texte est en fin de fichier.
    func scrollMarkdown(toLine line: Int, flash: Bool = false, atEnd: Bool = false) {
        guard webReady, webView?.isHidden == false else { return }
        webView?.evaluateJavaScript("""
        (function (line, flash, atEnd) {
            var root = document.scrollingElement;
            if (atEnd) { root.scrollTop = root.scrollHeight; return; }
            var blocks = document.querySelectorAll('[data-line]'), before = null, after = null;
            for (var i = 0; i < blocks.length; i++) {
                if (Number(blocks[i].dataset.line) <= line) before = blocks[i]; else { after = blocks[i]; break; }
            }
            if (!before) { root.scrollTop = 0; return; }
            var top = function (element) { return element.getBoundingClientRect().top + root.scrollTop; };
            var y = top(before), from = Number(before.dataset.line);
            if (after) y += (top(after) - y) * (line - from) / (Number(after.dataset.line) - from);
            if (flash) {
                root.scrollTop = Math.max(0, y - root.clientHeight / 3);
                before.classList.remove('sync-flash');
                void before.offsetWidth;
                before.classList.add('sync-flash');
            } else {
                root.scrollTop = Math.max(0, y - 18);
            }
        })(\(line), \(flash), \(atEnd));
        """)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webReady = true
        if let html = pendingHTML {
            pendingHTML = nil
            inject(html)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.scheme == LocalFileSchemeHandler.scheme {
            onOpenFile?(URL(fileURLWithPath: url.path))
        } else if url.scheme != "about" {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: PDF compilé

    /// Montre le PDF en gardant la page, le point et le zoom quand il remplace la version précédente.
    func showPDF(_ url: URL) {
        if pdfView == nil {
            let view = SyncPDFView()
            view.onCommandClick = { [weak self] page, point in self?.onPDFClick?(page, point) }
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.backgroundColor = .clear
            embed(view)
            pdfView = view
        }
        guard let pdfView, let document = PDFDocument(url: url) else {
            showMessage("Le PDF « \(url.lastPathComponent) » est illisible.")
            return
        }
        if shownPDF == url { pdfView.replaceDocument(document) } else { pdfView.document = document }
        syncMarks = []
        shownPDF = url
        // PDF recompilé hors de l'app (terminal, latexmk -pvc…) : rechargé au même endroit.
        pdfWatcher.onChange = { [weak self] in
            guard let self, self.shownPDF == url, self.pdfView?.isHidden == false else { return }
            self.showPDF(url)
        }
        pdfWatcher.watch(url)
        activate(pdfView)
    }

    private let pdfWatcher = FileChangeWatcher()

    /// Montre et surligne un instant les boîtes trouvées par SyncTeX (coordonnées origine en haut à gauche).
    func showSyncTeX(_ boxes: [SyncTeX.Box]) {
        guard let pdfView, let document = pdfView.document, let first = boxes.first, let page = document.page(at: first.page) else { return }
        clearSyncMarks()
        let media = page.bounds(for: .mediaBox)
        let rects = boxes.map { CGRect(x: media.minX + $0.rect.minX, y: media.maxY - $0.rect.maxY, width: $0.rect.width, height: $0.rect.height) }
        for rect in rects {
            let mark = PDFAnnotation(bounds: rect.insetBy(dx: -2, dy: -2), forType: .highlight, withProperties: nil)
            mark.color = NSColor.systemYellow.withAlphaComponent(0.55)
            page.addAnnotation(mark)
            syncMarks.append((page, mark))
        }
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        // Le bloc est placé vers le tiers supérieur de la vue.
        let visible = pdfView.convert(pdfView.bounds, to: page)
        let top = min(media.maxY, union.maxY + visible.height / 3)
        pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: visible.minX, y: top)))
        let marks = syncMarks.map(\.1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.syncMarks.map(\.1) == marks else { return }
            self.clearSyncMarks()
        }
    }

    private func clearSyncMarks() {
        for (page, mark) in syncMarks { page.removeAnnotation(mark) }
        syncMarks = []
    }

    // MARK: CSV

    func showCSV(_ text: String) {
        hideBanner()
        if tableView == nil {
            let table = NSTableView()
            table.usesAlternatingRowBackgroundColors = true
            table.style = .plain
            table.columnAutoresizingStyle = .noColumnAutoresizing
            table.gridStyleMask = [.solidVerticalGridLineMask]
            table.dataSource = self
            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.drawsBackground = false
            embed(scroll)
            tableView = table
            tableScroll = scroll
        }
        guard let tableView else { return }
        var parsed = CSVParser.parse(text)
        let header = parsed.isEmpty ? [] : parsed.removeFirst()
        let count = min(200, max(header.count, parsed.map(\.count).max() ?? 0))
        if tableView.tableColumns.count != count || tableView.tableColumns.enumerated().contains(where: { $1.title != (header.indices.contains($0) ? header[$0] : "") }) {
            tableView.tableColumns.forEach(tableView.removeTableColumn)
            for index in 0..<count {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
                column.title = header.indices.contains(index) ? header[index] : ""
                column.width = 120
                column.minWidth = 40
                tableView.addTableColumn(column)
            }
        }
        rows = parsed
        tableView.reloadData()
        activate(tableScroll)
        showBanner("\(parsed.count) ligne\(parsed.count > 1 ? "s" : "") · \(count) colonne\(count > 1 ? "s" : "")", error: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        guard let column, let index = Int(column.identifier.rawValue), rows.indices.contains(row), rows[row].indices.contains(index) else { return nil }
        return rows[row][index]
    }

    // MARK: JSON

    func showJSON(_ text: String) {
        if outlineView == nil {
            let outline = NSOutlineView()
            outline.style = .plain
            outline.usesAlternatingRowBackgroundColors = true
            for (identifier, title, width) in [("key", "Clé", 180.0), ("value", "Valeur", 260.0), ("type", "Type", 80.0)] {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                column.title = title
                column.width = width
                outline.addTableColumn(column)
                if identifier == "key" { outline.outlineTableColumn = column }
            }
            outline.dataSource = self
            outline.delegate = self
            let scroll = NSScrollView()
            scroll.documentView = outline
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            embed(scroll)
            outlineView = outline
            outlineScroll = scroll
        }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            jsonRoot = JSONNode(key: "racine", value: object)
            outlineView?.reloadData()
            outlineView?.expandItem(jsonRoot)
            hideBanner()
        } catch {
            // Le dernier arbre valide reste affiché sous le bandeau.
            let detail = ((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription
            showBanner("JSON invalide : \(detail)", error: true)
            if jsonRoot == nil {
                showMessage("JSON invalide.")
                return
            }
        }
        activate(outlineScroll)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? JSONNode else { return jsonRoot == nil ? 0 : 1 }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? JSONNode else { return jsonRoot! }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? JSONNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? JSONNode, let column else { return nil }
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        switch column.identifier.rawValue {
        case "key":
            field.stringValue = node.key
            field.font = .systemFont(ofSize: 12, weight: .medium)
        case "value":
            field.stringValue = node.summary
            field.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            field.textColor = node.color
        default:
            field.stringValue = node.type
            field.textColor = .secondaryLabelColor
        }
        return field
    }
}

/// Nœud de l'arbre JSON (enfants calculés à la demande).
private final class JSONNode {
    let key: String
    let value: Any

    init(key: String, value: Any) {
        self.key = key
        self.value = value
    }

    lazy var children: [JSONNode] = {
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().map { JSONNode(key: $0, value: dictionary[$0]!) }
        }
        if let array = value as? [Any] {
            return array.enumerated().map { JSONNode(key: "[\($0.offset)]", value: $0.element) }
        }
        return []
    }()

    var type: String {
        switch value {
        case is [String: Any]: "objet"
        case is [Any]: "tableau"
        case is String: "texte"
        case is NSNull: "null"
        case let number as NSNumber: CFGetTypeID(number) == CFBooleanGetTypeID() ? "booléen" : "nombre"
        default: ""
        }
    }

    var summary: String {
        switch value {
        case let dictionary as [String: Any]: "{ \(dictionary.count) clé\(dictionary.count > 1 ? "s" : "") }"
        case let array as [Any]: "[ \(array.count) élément\(array.count > 1 ? "s" : "") ]"
        case let string as String: "\"\(string)\""
        case is NSNull: "null"
        case let number as NSNumber: CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        default: "\(value)"
        }
    }

    var color: NSColor {
        switch value {
        case is String: .systemGreen
        case is NSNull: .secondaryLabelColor
        case let number as NSNumber: CFGetTypeID(number) == CFBooleanGetTypeID() ? .systemPurple : .systemBlue
        default: .secondaryLabelColor
        }
    }
}

/// Lecture CSV (guillemets doublés, retours à la ligne entre guillemets) ; séparateur deviné : virgule, point-virgule ou tabulation.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" }
        let separator: Character = [",", ";", "\t"].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(character) }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

/// Images et liens locaux de l'aperçu Markdown, servis par l'app (la page n'a pas accès au disque).
private final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "iexfile"

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let data = try? Data(contentsOf: URL(fileURLWithPath: url.path)) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// Conversion Markdown → HTML (CommonMark courant + tableaux, cases à cocher et barré de GitHub).
enum MarkdownHTML {
    static let page = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    :root { color-scheme: light dark; }
    body { font: 14px/1.6 -apple-system, sans-serif; margin: 0; padding: 18px 26px 48px; color: CanvasText; background: transparent; }
    #content { max-width: 820px; margin: 0 auto; }
    h1, h2 { border-bottom: 1px solid color-mix(in srgb, CanvasText 15%, transparent); padding-bottom: .25em; }
    h1, h2, h3, h4 { line-height: 1.25; margin: 1.3em 0 .5em; }
    code { font: 12.5px ui-monospace, Menlo, monospace; background: color-mix(in srgb, CanvasText 8%, transparent); padding: .1em .35em; border-radius: 4px; }
    pre { background: color-mix(in srgb, CanvasText 6%, transparent); padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0; padding: 0 1em; color: color-mix(in srgb, CanvasText 65%, transparent); border-left: 4px solid color-mix(in srgb, CanvasText 20%, transparent); }
    table { border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 5px 12px; }
    th { background: color-mix(in srgb, CanvasText 6%, transparent); }
    img { max-width: 100%; }
    a { color: LinkText; }
    hr { border: none; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); margin: 1.6em 0; }
    li.task { list-style: none; margin-left: -1.3em; }
    .sync-flash { animation: sync-flash 1.6s ease-out; border-radius: 4px; }
    @keyframes sync-flash { from { background: color-mix(in srgb, #ffd60a 45%, transparent); } to { background: transparent; } }
    </style></head><body><div id="content"></div></body></html>
    """

    static func render(_ text: String, base: URL) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return blocks(lines[...], base: base, annotate: true)
    }

    /// `annotate` : les blocs de premier niveau portent leur ligne dans le source (data-line, 1 = première), pour la synchronisation.
    private static func blocks(_ lines: ArraySlice<String>, base: URL, annotate: Bool = false) -> String {
        var html = ""
        var index = lines.startIndex
        var paragraph: [String] = []
        var paragraphStart = index

        func at(_ line: Int) -> String { annotate ? " data-line=\"\(line + 1)\"" : "" }

        func flush() {
            guard !paragraph.isEmpty else { return }
            html += "<p\(at(paragraphStart))>" + inline(paragraph.joined(separator: "\n"), base: base) + "</p>\n"
            paragraph = []
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }
            // Bloc de code délimité.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let start = index
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.endIndex, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                let attribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
                html += "<pre\(at(start))><code\(attribute)>" + escape(code.joined(separator: "\n")) + "</code></pre>\n"
                continue
            }
            // Titre.
            if let match = trimmed.firstMatch(of: #/^(#{1,6})\s+(.*?)\s*#*$/#) {
                flush()
                let level = match.1.count
                html += "<h\(level)\(at(index))>" + inline(String(match.2), base: base) + "</h\(level)>\n"
                index += 1
                continue
            }
            // Ligne horizontale.
            if trimmed.wholeMatch(of: #/([-*_])(\s*\1){2,}/#) != nil, paragraph.isEmpty || !trimmed.hasPrefix("-") {
                flush()
                html += "<hr\(at(index))>\n"
                index += 1
                continue
            }
            // Titre souligné (=== ou --- sous un paragraphe).
            if !paragraph.isEmpty, trimmed.wholeMatch(of: #/=+|-+/#) != nil {
                let level = trimmed.hasPrefix("=") ? 1 : 2
                html += "<h\(level)\(at(paragraphStart))>" + inline(paragraph.joined(separator: " "), base: base) + "</h\(level)>\n"
                paragraph = []
                index += 1
                continue
            }
            // Citation.
            if trimmed.hasPrefix(">") {
                flush()
                let start = index
                var quote: [String] = []
                while index < lines.endIndex {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    var content = current.dropFirst()
                    if content.hasPrefix(" ") { content = content.dropFirst() }
                    quote.append(String(content))
                    index += 1
                }
                html += "<blockquote\(at(start))>" + blocks(quote[...], base: base) + "</blockquote>\n"
                continue
            }
            // Tableau : ligne d'en-tête suivie de |---|---|.
            if trimmed.contains("|"), index + 1 < lines.endIndex,
               lines[index + 1].trimmingCharacters(in: .whitespaces).wholeMatch(of: #/\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/#) != nil {
                flush()
                let alignments = cells(lines[index + 1]).map { cell -> String in
                    let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
                    return left && right ? " style=\"text-align:center\"" : right ? " style=\"text-align:right\"" : ""
                }
                html += "<table\(at(index))><thead><tr>"
                for (column, cell) in cells(line).enumerated() {
                    html += "<th\(alignments.indices.contains(column) ? alignments[column] : "")>" + inline(cell, base: base) + "</th>"
                }
                html += "</tr></thead><tbody>\n"
                index += 2
                while index < lines.endIndex, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    html += "<tr\(at(index))>"
                    for (column, cell) in cells(lines[index]).enumerated() {
                        html += "<td\(alignments.indices.contains(column) ? alignments[column] : "")>" + inline(cell, base: base) + "</td>"
                    }
                    html += "</tr>\n"
                    index += 1
                }
                html += "</tbody></table>\n"
                continue
            }
            // Liste à puces ou numérotée.
            if let marker = listMarker(line) {
                flush()
                let ordered = marker.ordered
                let indent = marker.indent
                html += (ordered ? "<ol" : "<ul") + at(index) + ">\n"
                while index < lines.endIndex, let item = listMarker(lines[index]), item.indent == indent, item.ordered == ordered {
                    let start = index
                    var content = [String(lines[index].dropFirst(item.width))]
                    index += 1
                    // Lignes suivantes plus indentées (suite de l'élément ou sous-liste).
                    while index < lines.endIndex {
                        let next = lines[index]
                        let nextIndent = next.prefix { $0 == " " || $0 == "\t" }.count
                        if next.trimmingCharacters(in: .whitespaces).isEmpty {
                            if index + 1 < lines.endIndex, lines[index + 1].prefix(while: { $0 == " " }).count > indent { content.append(""); index += 1; continue }
                            break
                        }
                        if nextIndent > indent { content.append(String(next.dropFirst(min(nextIndent, item.width)))) }
                        else if listMarker(next) == nil, content.last?.isEmpty == false { content.append(next) }
                        else { break }
                        index += 1
                    }
                    var body = content
                    var task = ""
                    if let first = body.first, let check = first.firstMatch(of: #/^\[([ xX])\]\s+/#) {
                        task = "<input type=\"checkbox\" disabled\(check.1 == " " ? "" : " checked")> "
                        body[0] = String(first[check.range.upperBound...])
                    }
                    let rendered = body.count == 1 ? inline(body[0], base: base) : blocks(body[...], base: base)
                    // Liste serrée : le premier paragraphe de l'élément n'est pas entouré de <p>.
                    var simple = rendered
                    if simple.hasPrefix("<p>"), let end = simple.range(of: "</p>\n") {
                        simple = String(simple[simple.index(simple.startIndex, offsetBy: 3)..<end.lowerBound]) + "\n" + simple[end.upperBound...]
                    }
                    html += "<li\(at(start))\(task.isEmpty ? "" : " class=\"task\"")>" + task + simple + "</li>\n"
                    while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                          index + 1 < lines.endIndex, let next = listMarker(lines[index + 1]), next.indent == indent { index += 1 }
                }
                html += ordered ? "</ol>\n" : "</ul>\n"
                continue
            }
            // Bloc HTML brut (alignement, images dimensionnées des README).
            if paragraph.isEmpty, trimmed.firstMatch(of: #/^<\/?[a-zA-Z][a-zA-Z0-9-]*[\s>\/]/#) != nil {
                while index < lines.endIndex, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    html += rawHTML(lines[index], base: base) + "\n"
                    index += 1
                }
                continue
            }
            // Code indenté de quatre espaces.
            if paragraph.isEmpty, line.hasPrefix("    ") || line.hasPrefix("\t") {
                let start = index
                var code: [String] = []
                while index < lines.endIndex, lines[index].hasPrefix("    ") || lines[index].hasPrefix("\t") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    code.append(lines[index].hasPrefix("\t") ? String(lines[index].dropFirst()) : String(lines[index].dropFirst(min(4, lines[index].count))))
                    index += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                html += "<pre\(at(start))><code>" + escape(code.joined(separator: "\n")) + "</code></pre>\n"
                continue
            }
            if paragraph.isEmpty { paragraphStart = index }
            paragraph.append(line)
            index += 1
        }
        flush()
        return html
    }

    private static func listMarker(_ line: String) -> (ordered: Bool, indent: Int, width: Int)? {
        guard let match = line.firstMatch(of: #/^([ \t]*)([-*+]|\d{1,9}[.)])(\s+|$)/#) else { return nil }
        return (match.2.first?.isNumber == true, match.1.count, match.0.count)
    }

    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Adresse d'une image ou d'un lien : les chemins relatifs pointent vers le dossier du fichier.
    private static func resolve(_ address: String, base: URL) -> String {
        if address.hasPrefix("#") || address.contains("://") || address.hasPrefix("mailto:") || address.hasPrefix("data:") { return address }
        let path = address.removingPercentEncoding ?? address
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        let encoded = url.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        return LocalFileSchemeHandler.scheme + "://" + encoded
    }

    private static func rawHTML(_ line: String, base: URL) -> String {
        line.replacing(#/(src|href)="([^"]*)"/#) { match in "\(match.1)=\"\(resolve(String(match.2), base: base))\"" }
    }

    /// Remplacement avec NSRegularExpression (les expressions de Swift ne savent pas regarder en arrière).
    private static func substitute(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func inline(_ text: String, base: URL) -> String {
        var codes: [String] = []
        // Le code en ligne est mis de côté pour ne pas être interprété.
        var result = text.replacing(#/(`+)(.+?)\1/#) { match in
            codes.append("<code>" + escape(String(match.2).trimmingCharacters(in: .whitespaces)) + "</code>")
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        result = escape(result)
        result = result.replacing(#/!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^)]*&quot;)?\)/#) { match in
            "<img src=\"\(resolve(String(match.2), base: base))\" alt=\"\(match.1)\">"
        }
        result = result.replacing(#/\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;[^)]*&quot;)?\)/#) { match in
            "<a href=\"\(resolve(String(match.2), base: base))\">\(match.1)</a>"
        }
        result = result.replacing(#/&lt;(https?:\/\/[^\s&]+)&gt;/#) { "<a href=\"\($0.1)\">\($0.1)</a>" }
        result = substitute(result, #"(?<!["=>/])\bhttps?://[^\s<]+[^\s<.,;:!?)]"#, "<a href=\"$0\">$0</a>")
        result = result.replacing(#/\*\*(.+?)\*\*|__(.+?)__/#) { "<strong>\($0.1 ?? $0.2 ?? "")</strong>" }
        result = substitute(result, #"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])"#, "<em>$1</em>")
        result = substitute(result, #"(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])"#, "<em>$1</em>")
        result = result.replacing(#/~~(.+?)~~/#) { "<del>\($0.1)</del>" }
        result = result.replacing(#/( {2,}|\\)\n/#) { _ in "<br>\n" }
        for (index, code) in codes.enumerated() { result = result.replacingOccurrences(of: "\u{1}\(index)\u{1}", with: code) }
        return result
    }
}

/// Compilation LaTeX (latexmk, sinon pdflatex) ou Typst ; le PDF est écrit à côté du fichier principal.
enum DocumentCompiler {
    struct Failure: Error {
        let summary: String
        let log: String
        let line: Int?
    }

    /// Fichier principal : commentaire « % !TEX root = main.tex » (LaTeX) ou « // !TYPST root = main.typ » (Typst).
    static func root(for url: URL, text: String) -> URL {
        let head = text.prefix(2000)
        if let match = head.firstMatch(of: #/(?im)^\s*(?:%|\/\/)\s*!\s*(?:TEX|TYPST)\s+root\s*=\s*(.+?)\s*$/#) {
            let candidate = url.deletingLastPathComponent().appendingPathComponent(String(match.1)).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    static func pdf(for source: URL) -> URL { source.deletingPathExtension().appendingPathExtension("pdf") }

    static func compile(_ source: URL, kind: EditorPreviewKind, completion: @escaping (Result<URL, Failure>) -> Void) {
        let tool: ExternalTool = kind == .latex ? .latex : .typst
        guard let executable = tool.path else {
            completion(.failure(Failure(summary: "\(tool.title) n’est pas installé (Réglages › Outils externes)", log: "", line: nil)))
            return
        }
        let arguments: [String]
        switch executable.lastPathComponent {
        case "latexmk": arguments = ["-pdf", "-interaction=nonstopmode", "-halt-on-error", "-file-line-error", "-synctex=1", source.lastPathComponent]
        case "pdflatex": arguments = ["-interaction=nonstopmode", "-halt-on-error", "-file-line-error", "-synctex=1", source.lastPathComponent]
        default: arguments = ["compile", "--diagnostic-format", "human", source.lastPathComponent]
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = source.deletingLastPathComponent()
            var environment = ProcessInfo.processInfo.environment
            // latexmk appelle pdflatex, bibtex… : ils doivent être trouvés depuis une app lancée hors terminal.
            environment["PATH"] = ["/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            process.standardInput = FileHandle.nullDevice
            var log = ""
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                log = String(decoding: data, as: UTF8.self)
            } catch {
                log = error.localizedDescription
            }
            let pdf = pdf(for: source)
            let result: Result<URL, Failure>
            if process.terminationStatus == 0, FileManager.default.fileExists(atPath: pdf.path) {
                result = .success(pdf)
            } else {
                result = .failure(failure(from: log, source: source))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Première erreur lisible du journal : « fichier:ligne: message » (LaTeX) ou « error: … ┌─ fichier:ligne:col » (Typst).
    private static func failure(from log: String, source: URL) -> Failure {
        if let match = log.firstMatch(of: #/(?m)^[^\s:]*\.tex:(\d+):\s*(.+)$/#) {
            return Failure(summary: "Ligne \(match.1) : \(match.2)", log: log, line: Int(match.1))
        }
        if let error = log.firstMatch(of: #/(?m)^error:\s*(.+)$/#) {
            let line = log.firstMatch(of: #/─\s*\S+\.typ:(\d+):\d+/#).flatMap { Int($0.1) }
            return Failure(summary: (line.map { "Ligne \($0) : " } ?? "") + String(error.1), log: log, line: line)
        }
        if let error = log.firstMatch(of: #/(?m)^!\s*(.+)$/#) {
            return Failure(summary: String(error.1), log: log, line: nil)
        }
        return Failure(summary: "La compilation a échoué", log: log, line: nil)
    }
}

/// Correspondance source ↔ PDF de LaTeX (outil synctex, fichier .synctex.gz écrit par la compilation).
/// Coordonnées en points PDF, origine en haut à gauche de la page, pages numérotées à partir de 0.
enum SyncTeX {
    struct Box {
        let page: Int
        let rect: CGRect
    }

    private static var executable: URL? {
        let directories: [String?] = [ExternalTool.latex.path?.deletingLastPathComponent().path, "/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin"]
        return directories.compactMap { $0 }.map { URL(fileURLWithPath: $0 + "/synctex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func isAvailable(for pdf: URL) -> Bool {
        let synctex = pdf.deletingPathExtension().appendingPathExtension("synctex.gz")
        return executable != nil && FileManager.default.fileExists(atPath: synctex.path)
    }

    /// Boîtes du PDF produites par la ligne `line` (1 = première) de `source`.
    static func forward(line: Int, source: URL, pdf: URL, completion: @escaping ([Box]) -> Void) {
        let directory = pdf.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = source.standardizedFileURL.path
        // synctex retrouve le fichier sous le nom donné à la compilation, relatif au dossier du PDF.
        let input = path.hasPrefix(directory) ? String(path.dropFirst(directory.count)) : path
        run(["view", "-i", "\(line):0:\(input)", "-o", pdf.lastPathComponent], in: pdf) { output in
            var boxes: [Box] = []
            var page: Int?
            var values: [String: Double] = [:]
            func flush() {
                if let page, let h = values["h"], let v = values["v"], let width = values["W"], let height = values["H"] {
                    boxes.append(Box(page: page - 1, rect: CGRect(x: h, y: v - max(height, 8), width: max(width, 8), height: max(height, 8))))
                }
                values = [:]
            }
            for line in output.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[..<colon]), value = String(line[line.index(after: colon)...])
                if key == "Page" { flush(); page = Int(value) } else if let number = Double(value) { values[key] = number }
            }
            flush()
            // Seulement la première page trouvée : une ligne n'en produit en général qu'une.
            completion(boxes.filter { $0.page == boxes.first?.page })
        }
    }

    /// Fichier source et ligne (1 = première) qui ont produit le point `point` de la page `page`.
    static func inverse(page: Int, point: CGPoint, pdf: URL, completion: @escaping ((url: URL, line: Int)?) -> Void) {
        run(["edit", "-o", "\(page + 1):\(point.x):\(point.y):\(pdf.lastPathComponent)"], in: pdf) { output in
            let input = output.firstMatch(of: #/(?m)^Input:(.+)$/#).map { String($0.1) }
            let line = output.firstMatch(of: #/(?m)^Line:(\d+)/#).flatMap { Int($0.1) }
            guard let input, let line else { return completion(nil) }
            let url = input.hasPrefix("/") ? URL(fileURLWithPath: input) : pdf.deletingLastPathComponent().appendingPathComponent(input)
            completion((url.standardizedFileURL, max(1, line)))
        }
    }

    private static func run(_ arguments: [String], in pdf: URL, completion: @escaping (String) -> Void) {
        guard let executable else { return completion("") }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = pdf.deletingLastPathComponent()
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            var text = ""
            if (try? process.run()) != nil {
                text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}

/// PDF de l'aperçu : ⌘-clic renvoie la page et le point cliqués (origine en haut à gauche).
private final class SyncPDFView: PDFView {
    var onCommandClick: ((Int, CGPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let onCommandClick, let document else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true) else { return }
        let onPage = convert(point, to: page)
        let box = page.bounds(for: .mediaBox)
        onCommandClick(document.index(for: page), CGPoint(x: onPage.x - box.minX, y: box.maxY - onPage.y))
    }
}

/// Relais des messages de la page Markdown (le contrôleur de contenu retient fortement son destinataire).
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

extension PDFView {
    /// Remplace le document (nouvelle version du même fichier) en gardant la page, le point et le zoom.
    func replaceDocument(_ document: PDFDocument) {
        var restore: (page: Int, point: NSPoint, scale: CGFloat, auto: Bool)?
        if let old = self.document, let destination = currentDestination, let page = destination.page {
            restore = (old.index(for: page), destination.point, scaleFactor, autoScales)
        }
        self.document = document
        guard let restore, document.pageCount > 0, let page = document.page(at: min(restore.page, document.pageCount - 1)) else { return }
        if !restore.auto { scaleFactor = restore.scale }
        go(to: PDFDestination(page: page, at: restore.point))
    }
}
