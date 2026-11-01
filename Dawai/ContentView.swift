//
//  ContentView.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Main Content Router
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var themeService = ThemeService.shared

    var body: some View {
        Group {
            if appState.isIdentified, let identity = appState.currentIdentity {
                HomeView(identity: identity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                IdentitySetupCoordinatorView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(themeService.colorScheme)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
        .animation(.easeInOut(duration: 0.35), value: appState.isIdentified)
        .onAppear {
            themeService.applyThemeToApp()
        }
    }
}

#Preview("First Launch - Onboarding") {
    let appState = AppState()
    ContentView()
        .environmentObject(appState)
        .environment(\.layoutDirection, .rightToLeft)
        .tint(Color.dawaiPrimary)
}

#Preview("Identified - Home Page") {
    let appState = AppState()
    let mockIdentity = UserIdentity(
        role: .patient,
        displayName: "سارة",
        keyFingerprint: "e28fa4891b0c9f1a"
    )
    appState.currentIdentity = mockIdentity
    appState.isIdentified = true

    return ContentView()
        .environmentObject(appState)
        .environment(\.layoutDirection, .rightToLeft)
        .tint(Color.dawaiPrimary)
}
