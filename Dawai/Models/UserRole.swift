//
//  UserRole.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Set Up User Identity
//

import Foundation

/// Represents the role selected by the user during the initial identity setup.
public enum UserRole: String, Codable, CaseIterable, Identifiable {
    case patient
    case caregiver

    public var id: String { rawValue }

    /// Arabic title matching design: "انا مستفيد" / "انا مقدم الرعاية"
    public var titleArabic: String {
        switch self {
        case .patient:
            return "انا مستفيد"
        case .caregiver:
            return "انا مقدم الرعاية"
        }
    }

    /// Arabic subtitle: "(مريض/متلقي الرعاية)"
    public var subtitleArabic: String? {
        switch self {
        case .patient:
            return "(مريض/متلقي الرعاية)"
        case .caregiver:
            return nil
        }
    }

    /// English fallback title
    public var title: String {
        titleArabic
    }

    /// Descriptive summary of the role's purpose in Dawai.
    public var roleDescription: String {
        switch self {
        case .patient:
            return "مريض أو متلقي الرعاية"
        case .caregiver:
            return "مقدم الرعاية ومساعد المريض"
        }
    }

    /// SF Symbol icon associated with this role.
    public var systemImage: String {
        switch self {
        case .patient:
            return "person.fill"
        case .caregiver:
            return "heart.square.fill"
        }
    }
}
