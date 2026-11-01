import AppKit

/// Icône de l'app dans le Dock : celle du paquet ou l'une des palettes « double panneau » (Resources/AppIcons).
/// Seul le Dock change : modifier l'icône du paquet invaliderait sa signature et la mise à jour automatique.
enum AppIconChoice: String, CaseIterable {
    case original
    case glacier = "bleu-glacier"
    case citron = "encre-citron"
    case sauge
    case corail = "cobalt-corail"
    case aubergine
    case sable = "graphite-sable"

    private static let key = "appIcon"

    static var chosen: AppIconChoice {
        get { UserDefaults.standard.string(forKey: key).flatMap(AppIconChoice.init(rawValue:)) ?? .original }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    var title: String {
        switch self {
        case .original: L("Icône d’origine")
        case .glacier: L("Bleu glacier")
        case .citron: L("Encre et citron")
        case .sauge: L("Sauge")
        case .corail: L("Cobalt et corail")
        case .aubergine: L("Aubergine")
        case .sable: L("Graphite et sable")
        }
    }

    var image: NSImage? {
        if self == .original { return NSImage(named: NSImage.applicationIconName) }
        return Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "AppIcons").flatMap(NSImage.init(contentsOf:))
    }

    /// Au lancement et à chaque changement ; `nil` rend au Dock l'icône du paquet.
    static func apply() {
        NSApp.applicationIconImage = chosen == .original ? nil : chosen.image
    }
}
