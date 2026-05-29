import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case spanish = "es"
    case arabic = "ar"
    case french = "fr"
    case bengali = "bn"
    case portuguese = "pt"
    case russian = "ru"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .hindi: return "Hindi"
        case .spanish: return "Spanish"
        case .arabic: return "Arabic"
        case .french: return "French"
        case .bengali: return "Bengali"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        }
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .hindi: return "हिन्दी"
        case .spanish: return "Español"
        case .arabic: return "العربية"
        case .french: return "Français"
        case .bengali: return "বাংলা"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        }
    }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    static func preferred() -> AppLanguage {
        let preferredCodes = Locale.preferredLanguages.map { $0.lowercased() }
        for code in preferredCodes {
            if code.hasPrefix("zh") { return .chineseSimplified }
            if code.hasPrefix("hi") { return .hindi }
            if code.hasPrefix("es") { return .spanish }
            if code.hasPrefix("ar") { return .arabic }
            if code.hasPrefix("fr") { return .french }
            if code.hasPrefix("bn") { return .bengali }
            if code.hasPrefix("pt") { return .portuguese }
            if code.hasPrefix("ru") { return .russian }
            if code.hasPrefix("ja") { return .japanese }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }
}

