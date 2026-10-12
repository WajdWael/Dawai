//
//  IdentitySetupViewModel.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Setup Flow State Machine & Validation Coordinator
//

import Foundation
import SwiftUI
import Combine

/// The explicit steps in the UC-1 Setup Flow navigation stack.
public enum SetupStep: Hashable {
    case nameEntry
}

/// ViewModel coordinating the entire Use-Case 1 onboarding lifecycle.
@MainActor
public final class IdentitySetupViewModel: ObservableObject {
    
    // MARK: - Navigation Path
    @Published public var navigationPath: [SetupStep] = []

    // MARK: - User Input State
    @Published public var selectedRole: UserRole? = nil {
        didSet {
            if selectedRole != nil {
                roleErrorMessage = nil
            }
        }
    }
    
    @Published public var firstName: String = "" {
        didSet {
            if !firstName.isEmpty && nameErrorMessage != nil {
                // Clear immediate error once user starts typing
                nameErrorMessage = nil
            }
        }
    }
    
    @Published public private(set) var sanitizedFirstName: String = ""

    // MARK: - Error States (Covering Alternate Courses 1, 2, 3, 4)
    /// Alternate Course 1 Error: User does not select a role.
    @Published public var roleErrorMessage: String? = nil

    /// Alternate Courses 2 & 3 Error: User leaves first-name empty or enters invalid first name.
    @Published public var nameErrorMessage: String? = nil

    /// Alternate Course 4 Error: Identity setup fails.
    @Published public var setupErrorMessage: String? = nil
    
    // MARK: - Progress & Provisioning State
    @Published public var isProcessingSetup: Bool = false
    @Published public var currentProgressStageText: String = "جاري إعداد الهوية..."
    
    /// Developer / Test switch: allows demonstrating and verifying Alternate Course 4 (Retry loop).
    @Published public var simulateBackendFailure: Bool = false

    private let identityService: IdentityService

    public init() {
        self.identityService = IdentityService.shared
    }

    public init(identityService: IdentityService) {
        self.identityService = identityService
    }

    // MARK: - Step 2: Role Selection -> Name Entry (with Alternate Course 1)
    public func selectRoleAndProceed(_ role: UserRole) {
        self.selectedRole = role
        self.roleErrorMessage = nil
        self.navigationPath.append(.nameEntry)
    }

    @discardableResult
    public func proceedFromRoleSelection() -> Bool {
        guard let _ = selectedRole else {
            // Alternate Course 1: User does not select a role.
            roleErrorMessage = IdentitySetupError.roleNotSelected.errorDescription
            return false
        }
        roleErrorMessage = nil
        navigationPath.append(.nameEntry)
        return true
    }

    // MARK: - Step 3 to 7: Submit Name, Generate Credentials, and Go to Home Page
    public func submitNameAndCompleteSetup(appState: AppState) async {
        // Validate name (Alternate Courses 2 & 3)
        switch NameValidator.validate(firstName) {
        case .invalid(let error):
            nameErrorMessage = error.errorDescription
            return
        case .valid(let sanitized):
            nameErrorMessage = nil
            sanitizedFirstName = sanitized
        }

        guard let role = selectedRole else {
            setupErrorMessage = IdentitySetupError.roleNotSelected.errorDescription
            return
        }

        isProcessingSetup = true
        setupErrorMessage = nil
        currentProgressStageText = "جاري تهيئة الهوية..."

        do {
            let identity = try await identityService.setupIdentity(
                role: role,
                displayName: sanitizedFirstName,
                simulateFailure: simulateBackendFailure,
                progressHandler: { [weak self] stage in
                    Task { @MainActor in
                        self?.currentProgressStageText = stage.rawValue
                    }
                }
            )
            
            isProcessingSetup = false
            // Step 7: Redirects the user directly to the Home Page
            appState.completeSetup(identity: identity)
            
        } catch {
            isProcessingSetup = false
            // Alternate Course 4: Identity setup fails.
            setupErrorMessage = error.localizedDescription
        }
    }

    /// Retries the setup process (Alternate Course 4).
    public func retrySetup(appState: AppState) async {
        await submitNameAndCompleteSetup(appState: appState)
    }
}
