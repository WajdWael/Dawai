//
//  UserIdentity.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Set Up User Identity
//

import Foundation

/// Represents the securely established anonymous application identity.
/// The application does not require email, password, username, or traditional account credentials.
/// The first name is used strictly as a display name and is not used for authentication, authorization, or user lookup.
public struct UserIdentity: Codable, Equatable, Identifiable {
    /// Anonymous application identity string (e.g., dawai_anon_XXXXXXXXXXXX)
    public let id: String
    
    /// The user's selected role (Patient or Caregiver)
    public let role: UserRole
    
    /// First name used strictly as a local display name
    public let displayName: String
    
    /// Timestamp when this identity was established
    public let createdAt: Date
    
    /// Hex-encoded SHA-256 fingerprint of the user's public key
    public let keyFingerprint: String

    public init(
        id: String = "dawai_anon_" + UUID().uuidString.prefix(12).lowercased(),
        role: UserRole,
        displayName: String,
        createdAt: Date = Date(),
        keyFingerprint: String
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.createdAt = createdAt
        self.keyFingerprint = keyFingerprint
    }
}
