//
//  DawaiApp.swift
//  Dawai
//
//  Created by Wajd Wael on 11/10/2026.
//

import SwiftUI
import UIKit

final class DawaiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await CloudKitSyncManager.shared.handleRemoteNotification(userInfo)
            completionHandler(result)
        }
    }
}

@main
struct DawaiApp: App {
    @UIApplicationDelegateAdaptor(DawaiAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @ObservedObject private var themeService = ThemeService.shared

    init() {
        UserDefaults.standard.set(["ar"], forKey: "AppleLanguages")
        LocalDataStore.prepareOnLaunch()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            rootContentView
        }
    }

    @ViewBuilder
    private var rootContentView: some View {
        ContentView()
            .environmentObject(appState)
            .environmentObject(themeService)
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.dawaiFontScale, themeService.fontScale)
            .environment(\.dynamicTypeSize, themeService.dynamicTypeSize)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .tint(Color.dawaiPrimary)
            .onAppear(perform: handleOnAppear)
            .onChange(of: scenePhase, perform: handleScenePhaseChange)
            .onOpenURL(perform: handleIncomingURL)
    }

    private func handleOnAppear() {
        NotificationDelegate.shared.configure(with: appState)
        if appState.isIdentified {
            CloudKitSyncManager.shared.startPeriodicSync()
            DoseLiveActivityManager.shared.sync(using: MedicationService.shared)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if appState.isIdentified {
                CloudKitSyncManager.shared.startPeriodicSync()
                DoseLiveActivityManager.shared.sync(using: MedicationService.shared)
            }
        case .background, .inactive:
            CloudKitSyncManager.shared.stopPeriodicSync()
        @unknown default:
            break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "dawai",
           url.host?.lowercased() == "confirm-dose",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idStr = components.queryItems?.first(where: { $0.name == "medicationId" })?.value,
           let medId = UUID(uuidString: idStr) {
            let slotMinutes = components.queryItems?
                .first(where: { $0.name == "slotMinutes" })?
                .value
                .flatMap(Int.init)
            appState.openDoseConfirmation(for: medId, slotMinutes: slotMinutes)
            return
        }

        let token = RelationshipService.shared.handleIncomingURL(url)
        if RelationshipService.shared.isInviteLink(url) {
            appState.pendingInviteToken = url.absoluteString
        } else if let token, !token.isEmpty {
            appState.pendingInviteToken = token
        }
    }
}
