//
//  AppTheme.swift
//  Dawai
//

import SwiftUI
import Combine
import UIKit

// MARK: - Application Appearance & Theme Service (Backend Engine)
public enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var titleArabic: String {
        switch self {
        case .system: return "تلقائي"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

@MainActor
public final class ThemeService: ObservableObject {
    public static let shared = ThemeService()

    private let storageKey = "dawai_app_appearance"

    @Published public var appearanceRaw: String {
        didSet {
            UserDefaults.standard.set(appearanceRaw, forKey: storageKey)
            applyThemeToApp()
        }
    }

    public init() {
        self.appearanceRaw = UserDefaults.standard.string(forKey: "dawai_app_appearance") ?? "system"
        applyThemeToApp()
    }

    public var currentAppearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set {
            appearanceRaw = newValue.rawValue
            applyThemeToApp()
        }
    }

    public var colorScheme: ColorScheme? {
        currentAppearance.colorScheme
    }

    /// Enforces the selected dark/light/system theme across the entire application and all UIWindows
    public func applyThemeToApp() {
        let appearance = currentAppearance
        let style: UIUserInterfaceStyle
        switch appearance {
        case .light:
            style = .light
        case .dark:
            style = .dark
        case .system:
            style = .unspecified
        }

        func updateWindows() {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }

        updateWindows()
        DispatchQueue.main.async {
            updateWindows()
        }
    }
}

extension Color {
    /// Primary Dawai brand color: #007B78 (RGB: 0, 123, 120)
    public static let dawaiPrimary = Color(red: 0.0 / 255.0, green: 123.0 / 255.0, blue: 120.0 / 255.0)
    
    /// Secondary accent color for badges and highlights
    public static let dawaiSecondary = Color(red: 0.0 / 255.0, green: 150.0 / 255.0, blue: 146.0 / 255.0)
    
    /// Background color: Clean slate gray in light mode (#EAECF2), true deep dark in dark mode
    public static let dawaiBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground
            : UIColor(red: 234.0 / 255.0, green: 236.0 / 255.0, blue: 242.0 / 255.0, alpha: 1.0)
    })

    /// Pre-resolved primary border color
    public static let dawaiPrimaryBorder = Color(red: 0.0 / 255.0, green: 123.0 / 255.0, blue: 120.0 / 255.0).opacity(0.4)
    
    /// Adaptive glass border: subtle in dark mode, crisp in light mode
    public static let dawaiGlassBorder = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.8)
    })

    // MARK: - Refined Warning / Alert Palette (Soft warm amber / terracotta)
    /// Sophisticated, high-contrast warm amber-terracotta (#DC5F1E)
    public static let dawaiWarning = Color(red: 220.0 / 255.0, green: 95.0 / 255.0, blue: 30.0 / 255.0)

    /// Subtle warm ivory-amber tint in light mode, dark warm tint in dark mode
    public static let dawaiWarningBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 220.0 / 255.0, green: 95.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.16)
            : UIColor(red: 255.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0, alpha: 1.0)
    })

    /// Subtle pill badge background for warning tags
    public static let dawaiWarningBadgeBackground = Color(red: 220.0 / 255.0, green: 95.0 / 255.0, blue: 30.0 / 255.0).opacity(0.14)

    /// Subtle border stroke for alert cards and rows
    public static let dawaiWarningBorder = Color(red: 220.0 / 255.0, green: 95.0 / 255.0, blue: 30.0 / 255.0).opacity(0.25)

    // MARK: - Refined Taken / Done Palette (Calm Sage / Emerald)
    /// Calm emerald-sage tone (#128A64) for completed states
    public static let dawaiTaken = Color(red: 18.0 / 255.0, green: 138.0 / 255.0, blue: 100.0 / 255.0)

    /// Adaptive tint for completed medication states
    public static let dawaiTakenBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 18.0 / 255.0, green: 138.0 / 255.0, blue: 100.0 / 255.0, alpha: 0.16)
            : UIColor(red: 240.0 / 255.0, green: 248.0 / 255.0, blue: 245.0 / 255.0, alpha: 1.0)
    })

    /// Soft pill badge background for taken status tags
    public static let dawaiTakenBadgeBackground = Color(red: 18.0 / 255.0, green: 138.0 / 255.0, blue: 100.0 / 255.0).opacity(0.14)

    /// Subtle border stroke for completed cards and badges
    public static let dawaiTakenBorder = Color(red: 18.0 / 255.0, green: 138.0 / 255.0, blue: 100.0 / 255.0).opacity(0.3)
}

// MARK: - App Numerals & Localization (Strict Western 0123456789)
extension Locale {
    /// Arabic Locale using Western Numerals (0123456789)
    public static let dawaiArabic = Locale(identifier: "ar@numbers=latn")
}

extension String {
    /// Converts any Eastern Arabic digits (٠١٢٣٤٥٦٧٨٩) to standard Western digits (0123456789)
    public var westernNumerals: String {
        var result = self
        let map = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"
        ]
        for (eastern, western) in map {
            result = result.replacingOccurrences(of: eastern, with: western)
        }
        return result
    }
}

