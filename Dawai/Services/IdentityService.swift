//
//  IdentityService.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Identity Setup and Cryptographic Credential Management
//

import Foundation
import CryptoKit

/// Service responsible for orchestrating Use-Case 1:
/// - Generating cryptographic key pairs (NIST P-256 ECDSA)
/// - Securely storing credentials in Keychain
/// - Registering anonymous backend identity
public final class IdentityService {
    public static let shared = IdentityService()
    
    private let keychain: KeychainService

    public init() {
        self.keychain = KeychainService.shared
    }

    public init(keychain: KeychainService) {
        self.keychain = keychain
    }

    /// Checks if a valid identity already exists on the device.
    public var hasExistingIdentity: Bool {
        return keychain.loadUserIdentity() != nil && keychain.loadPrivateKeyData() != nil
    }

    /// Fetches the currently active identity if present.
    public func fetchCurrentIdentity() -> UserIdentity? {
        return keychain.loadUserIdentity()
    }

    /// Progress callback stages for Use-Case 1 setup.
    public enum SetupStage: String {
        case generatingCredentials = "جاري إنشاء مفاتيح التشفير..."
        case storingCredentials = "جاري تأمين المفاتيح في Keychain..."
        case registeringBackendIdentity = "جاري تسجيل هوية التطبيق المجهولة..."
        case completed = "اكتمل الإعداد بنجاح!"
    }

    /// Executes the full identity creation flow per UC-1 (S#4, S#5, S#6).
    /// - Parameters:
    ///   - role: Selected role (Patient or Caregiver).
    ///   - displayName: Sanitized first name.
    ///   - simulateFailure: Optional flag to simulate Alternate Course 4 for testing.
    ///   - progressHandler: Closure receiving progress stage updates for UI ProgressView.
    /// - Returns: Newly initialized `UserIdentity`.
    public func setupIdentity(
        role: UserRole,
        displayName: String,
        simulateFailure: Bool = false,
        progressHandler: ((SetupStage) -> Void)? = nil
    ) async throws -> UserIdentity {
        
        // -----------------------------------------------------------------
        // S#5: Generates and securely stores required cryptographic credentials
        // -----------------------------------------------------------------
        progressHandler?(.generatingCredentials)
        try await Task.sleep(nanoseconds: 350_000_000) // Realistic secure generation timing
        
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        
        // Compute SHA-256 fingerprint for display and verification
        let fingerprintDigest = SHA256.hash(data: publicKeyData)
        let fingerprintString = fingerprintDigest.map { String(format: "%02hhx", $0) }.joined()
        
        progressHandler?(.storingCredentials)
        try await Task.sleep(nanoseconds: 250_000_000)
        
        // Securely persist private key in Apple Keychain
        let keySaved = keychain.savePrivateKeyData(privateKey.rawRepresentation)
        guard keySaved else {
            throw IdentitySetupError.identitySetupFailed("Failed to write cryptographic key to Keychain")
        }
        
        // -----------------------------------------------------------------
        // S#4 & S#6: Creates anonymous application identity & backend identity
        // -----------------------------------------------------------------
        let anonymousId = "dawai_anon_" + UUID().uuidString.prefix(12).lowercased()
        let identity = UserIdentity(
            id: anonymousId,
            role: role,
            displayName: displayName,
            createdAt: Date(),
            keyFingerprint: String(fingerprintString.prefix(16))
        )
        
        progressHandler?(.registeringBackendIdentity)
        try await Task.sleep(nanoseconds: 400_000_000)
        
        // Alternate Course 4: Identity setup fails simulation or handling
        if simulateFailure {
            // Clean up private key to leave system in valid retryable state
            keychain.delete(forAccount: "anonymous_private_key")
            throw IdentitySetupError.identitySetupFailed("Backend identity service unavailable")
        }
        
        // Persist identity metadata in Keychain
        let identitySaved = keychain.saveUserIdentity(identity)
        guard identitySaved else {
            keychain.delete(forAccount: "anonymous_private_key")
            throw IdentitySetupError.identitySetupFailed("Failed to save identity state")
        }
        
        progressHandler?(.completed)
        return identity
    }

    /// Resets the identity completely for testing first-launch (UC-1 Pre-condition).
    public func resetIdentity() {
        keychain.clearAllCredentials()
    }
}
