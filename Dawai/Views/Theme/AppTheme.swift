//
//  AppTheme.swift
//  Dawai
//

import SwiftUI

extension Color {
    /// Primary Dawai brand color: #007B78 (RGB: 0, 123, 120)
    public static let dawaiPrimary = Color(red: 0.0 / 255.0, green: 123.0 / 255.0, blue: 120.0 / 255.0)
    
    /// Secondary accent color for badges and highlights
    public static let dawaiSecondary = Color(red: 0.0 / 255.0, green: 150.0 / 255.0, blue: 146.0 / 255.0)
    
    /// Background color matching design: subtle clean slate
    public static let dawaiBackground = Color(red: 245.0 / 255.0, green: 246.0 / 255.0, blue: 250.0 / 255.0)

    /// Pre-resolved primary border color (avoids compiler ambiguity with .opacity inside Shape.stroke)
    public static let dawaiPrimaryBorder = Color(red: 0.0 / 255.0, green: 123.0 / 255.0, blue: 120.0 / 255.0).opacity(0.4)
    
    /// Pre-resolved glass white border
    public static let dawaiGlassBorder = Color.white.opacity(0.8)
}
