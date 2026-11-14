//
//  AppEnvironment.swift
//  Dawai
//
//  Detects which kind of build is running (Debug / TestFlight / App Store) and
//  gates developer-only features (demo data, simulator tools) accordingly.
//
//  | Build        | Demo data | "Test mode" simulator tools |
//  |--------------|-----------|-----------------------------|
//  | Xcode Debug  | opt-in    | visible                     |
//  | TestFlight   | never     | visible                     |
//  | App Store    | never     | hidden                      |
//

import Foundation
import Combine

public enum AppEnvironment {

    /// True only for builds compiled with the DEBUG flag (Run from Xcode).
    public static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// True when the app was installed through TestFlight.
    /// TestFlight builds carry a receipt named `sandboxReceipt`; App Store builds carry `receipt`.
    public static var isTestFlight: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }

    /// Simulator / "وضع تجريبي" tools are available in Debug and TestFlight only.
    public static var showsSimulatorTools: Bool {
        isDebugBuild || isTestFlight
    }

    /// Demo data may only ever be loaded in Debug builds.
    public static var supportsDemoData: Bool {
        isDebugBuild
    }
}

/// Opt-in demo data, available in Debug builds only.
/// In TestFlight and App Store builds `isActive` is always `false` and nothing here has any effect.
public final class DemoModeService: ObservableObject {
    public static let shared = DemoModeService()

    private let storageKey = "dawai_demo_mode_enabled"

    @Published public private(set) var isActive: Bool

    private init() {
        #if DEBUG
        isActive = UserDefaults.standard.bool(forKey: storageKey)
        #else
        isActive = false
        #endif
    }

    /// Demo beneficiaries shown to a caregiver while demo mode is on.
    public var beneficiaries: [BeneficiarySummary] {
        #if DEBUG
        guard isActive else { return [] }
        return HomeMockData.beneficiaries.filter { !$0.isInvitation }
        #else
        return []
        #endif
    }

    /// True if `idOrName` belongs to a demo beneficiary and demo mode is on.
    public func isDemoPatient(_ idOrName: String) -> Bool {
        #if DEBUG
        guard isActive else { return false }
        return HomeMockData.beneficiaries.contains { $0.id.uuidString == idOrName || $0.name == idOrName }
        #else
        return false
        #endif
    }

    /// Forgets the demo flag (used when all local data is wiped).
    public func clearFlag() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        isActive = false
    }

    #if DEBUG
    /// Loads sample medications and dose history, and turns demo mode on.
    @MainActor
    public func enable() {
        MedicationService.shared.loadDemoData()
        AdherenceService.shared.loadDemoHistory()
        UserDefaults.standard.set(true, forKey: storageKey)
        isActive = true
    }

    /// Removes sample data (and any medications entered while demo mode was on) and turns demo mode off.
    @MainActor
    public func disable() {
        MedicationService.shared.resetAllData()
        AdherenceService.shared.resetAllData()
        UserDefaults.standard.set(false, forKey: storageKey)
        isActive = false
    }
    #endif
}

