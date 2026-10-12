//
//  IdentitySetupError.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Set Up User Identity Errors
//

import Foundation

/// Specific domain errors conforming to UC-1 Alternate Courses of Action.
public enum IdentitySetupError: LocalizedError, Equatable {
    /// Alternate Course 1: User does not select a role.
    case roleNotSelected
    
    /// Alternate Course 2: User leaves the first-name field empty.
    case emptyFirstName
    
    /// Alternate Course 3: User enters an invalid first name.
    case invalidFirstName(String)
    
    /// Alternate Course 4: Identity setup fails (cryptographic generation or backend identity creation).
    case identitySetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .roleNotSelected:
            return "يرجى اختيار دورك: مستفيد أو مقدم الرعاية للمتابعة."
        case .emptyFirstName:
            return "يرجى إدخال اسمك الأول."
        case .invalidFirstName(let reason):
            return reason
        case .identitySetupFailed(let details):
            return "فشل إعداد الهوية: \(details). يرجى المحاولة مرة أخرى."
        }
    }
}
