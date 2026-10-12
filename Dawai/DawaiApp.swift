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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .tint(Color.dawaiPrimary)
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
