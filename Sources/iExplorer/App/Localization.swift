import Foundation

/// Langue de l'interface : celle du système par défaut, ou imposée dans les Réglages (prise en compte au prochain lancement).
enum AppLanguage: String, CaseIterable {
    case system, fr, en

    private static let key = "appLanguage"

    static var chosen: AppLanguage {
        get { UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Nom affiché dans le menu, chaque langue dans sa propre langue.
    var title: String {
        switch self {
        case .system: L("Langue du système")
        case .fr: "Français"
        case .en: "English"
        }
    }

    /// À appeler avant tout texte affiché : impose la langue choisie à Bundle.main.
    static func applyAtLaunch() {
        switch chosen {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .fr, .en: UserDefaults.standard.set([chosen.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Langue effectivement utilisée par l'interface (« fr » ou « en »).
    static var current: String { Bundle.main.preferredLocalizations.first ?? "fr" }

    /// Locale des dates et nombres affichés, accordée à la langue de l'interface (pas à la région du système).
    static var locale: Locale { Locale(identifier: current == "fr" ? "fr_FR" : "en_US") }

    /// Traductions inversées (texte affiché → texte français du code), pour les réglages rangés par libellé.
    private static let sourceTexts: [String: String] = {
        guard current != "fr", let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings"),
              let table = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        var inverse: [String: String] = [:]
        for (french, translated) in table where !french.contains("%") { inverse[translated] = inverse[translated] ?? french }
        return inverse
    }()

    /// Texte français d'un libellé affiché : les réglages enregistrés par libellé restent valables d'une langue à l'autre.
    static func sourceText(_ displayed: String) -> String { sourceTexts[displayed] ?? displayed }
}

/// Texte d'interface écrit en français dans le code, traduit d'après `<langue>.lproj/Localizable.strings`.
/// Chaque interpolation devient « %@ » dans la clé (« \(n) éléments » → « %@ éléments ») ; la traduction
/// peut réordonner les valeurs avec « %1$@ », « %2$@ »…
struct LocalizedText: ExpressibleByStringInterpolation {
    var key = ""
    var arguments: [String] = []

    init(stringLiteral value: String) {
        key = value.replacingOccurrences(of: "%", with: "%%")
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            arguments.append("\(value)")
        }
    }
}

/// Texte traduit dans la langue de l'interface (voir `LocalizedText`).
func L(_ text: LocalizedText) -> String {
    let template = Bundle.main.localizedString(forKey: text.key, value: text.key, table: nil)
    var result = ""
    var index = 0
    var characters = template[...]
    while let percent = characters.firstIndex(of: "%") {
        result += characters[..<percent]
        let rest = characters[characters.index(after: percent)...]
        if rest.hasPrefix("%") {
            result += "%"
            characters = rest.dropFirst()
        } else if rest.hasPrefix("@") {
            result += index < text.arguments.count ? text.arguments[index] : ""
            index += 1
            characters = rest.dropFirst()
        } else if let dollar = rest.firstIndex(of: "$"), let position = Int(rest[..<dollar]),
                  rest[rest.index(after: dollar)...].hasPrefix("@") {
            result += position - 1 < text.arguments.count && position > 0 ? text.arguments[position - 1] : ""
            characters = rest[rest.index(dollar, offsetBy: 2)...]
        } else {
            result += "%"
            characters = rest
        }
    }
    return result + characters
}
