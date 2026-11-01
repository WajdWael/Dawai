//
//  DawaiApp.swift
//  Dawai
//
//  Created by Wajd Wael on 11/10/2026.
//

import SwiftUI

@main
struct DawaiApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var themeService = ThemeService.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(themeService)
                .preferredColorScheme(themeService.colorScheme)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale.dawaiArabic)
                .tint(Color.dawaiPrimary)
                .onAppear {
                    NotificationDelegate.shared.configure(with: appState)
                }
                .onOpenURL { url in
                    // UC-2 S#4: Handle deep link invitations (dawai://invite?token=XYZ)
                    if url.scheme == "dawai",
                       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                        appState.pendingInviteToken = token
                    }
                }
        }
    }
}
