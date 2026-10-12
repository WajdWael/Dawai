//
//  NameValidator.swift
//  Dawai
//
//  Use-Case 1 (UC-1): First Name Validation (Arabic Primary)
//

import Foundation

/// Validates first name according to UC-1 rules and constraints.
/// First name is strictly used for display and not for authentication or lookup.
public struct NameValidator {
    
    /// Result of validating a name.
    public enum ValidationResult: Equatable {
        case valid(sanitized: String)
        case invalid(IdentitySetupError)
    }

    /// Validates the provided raw first name string.
    /// - Parameter rawName: The input text entered by the user.
    /// - Returns: `.valid(sanitized)` or `.invalid(IdentitySetupError)`.
    public static func validate(_ rawName: String) -> ValidationResult {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Alternate Course 2: User leaves first-name field empty.
        if trimmed.isEmpty {
            return .invalid(.emptyFirstName)
        }
        
        // Alternate Course 3: Minimum length constraint
        if trimmed.count < 2 {
            return .invalid(.invalidFirstName("يرجى إدخال اسم أول صالح (حرفان على الأقل)."))
        }
        
        // Alternate Course 3: Maximum length constraint
        if trimmed.count > 40 {
            return .invalid(.invalidFirstName("يرجى إدخال اسم أول صالح (40 حرفاً كحد أقصى)."))
        }
        
        // Alternate Course 3: Valid characters (letters across international alphabets, spaces, hyphens, apostrophes)
        // Disallows numbers, symbols, punctuation, emojis
        let allowedCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: " -'’"))
        let invalidCharacters = CharacterSet(charactersIn: trimmed).subtracting(allowedCharacters)
        
        if !invalidCharacters.isEmpty {
            return .invalid(.invalidFirstName("يرجى إدخال اسم أول صالح (أحرف فقط، بدون أرقام أو رموز)."))
        }
        
        // Disallow names that are only hyphens/apostrophes/spaces
        let lettersOnly = trimmed.filter { $0.isLetter }
        if lettersOnly.count < 2 {
            return .invalid(.invalidFirstName("يرجى إدخال اسم أول يحتوي على حرفين على الأقل."))
        }
        
        return .valid(sanitized: trimmed)
    }
}
