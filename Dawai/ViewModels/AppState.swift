//
//  AppState.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Application Root State
//

import Foundation
import SwiftUI
import Combine

/// Global application state managing identity readiness and routing between onboarding and Home.
public final class AppState: ObservableObject {
    /// True when anonymous application identity setup is complete and credentials exist.
    @Published public var isIdentified: Bool = false
    
    /// The currently active anonymous user identity.
    @Published public var currentIdentity: UserIdentity?

    /// Pending invitation token received via deep link (UC-2 S#4)
    @Published public var pendingInviteToken: String? = nil
    
    private let identityService: IdentityService

    public init() {
        self.identityService = IdentityService.shared
        loadExistingIdentity()
    }

    public init(identityService: IdentityService) {
        self.identityService = identityService
        loadExistingIdentity()
    }

    /// Loads persisted identity if available.
    public func loadExistingIdentity() {
        if let identity = identityService.fetchCurrentIdentity() {
            self.currentIdentity = identity
            self.isIdentified = true
        } else {
            self.currentIdentity = nil
            self.isIdentified = false
        }
    }

    /// Called upon successful completion of UC-1 (S#7: Redirects the user to the Home Page).
    public func completeSetup(identity: UserIdentity) {
        withAnimation(.easeInOut(duration: 0.35)) {
            self.currentIdentity = identity
            self.isIdentified = true
        }
    }

    /// Resets the application identity to test first launch UC-1 experience again.
    public func resetIdentityForTesting() {
        identityService.resetIdentity()
        withAnimation(.easeInOut(duration: 0.35)) {
            self.currentIdentity = nil
            self.isIdentified = false
        }
    }
}
