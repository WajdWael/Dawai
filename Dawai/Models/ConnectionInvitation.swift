//
//  ConnectionInvitation.swift
//  Dawai
//
//  Use-Case 2 (UC-2): Link Patient and Caregiver
//  Data models representing secure invitations, relationships, and permissions.
//

import Foundation

// MARK: - Invitation Status Lifecycle (UC-2 S#2 -> S#5 -> S#6 -> S#7)
public enum InvitationStatus: String, Codable, CaseIterable {
    /// S#2: Invitation generated, waiting for recipient to open & accept.
    case pending = "pending"
    
    /// S#5: Recipient reviewed and clicked Accept. Waiting for initiator confirmation.
    case accepted = "accepted"
    
    /// S#6 & S#7: Initiator confirmed connection. Relationship is now Active.
    case confirmed = "confirmed"
    
    /// Recipient clicked Reject.
    case rejected = "rejected"
    
    /// Invitation expired (TTL elapsed).
    case expired = "expired"

    public var titleArabic: String {
        switch self {
        case .pending:
            return "في انتظار القبول"
        case .accepted:
            return "تم القبول، بانتظار التأكيد"
        case .confirmed:
            return "متصل ونشط"
        case .rejected:
            return "تم رفض الدعوة"
        case .expired:
            return "منتهية الصلاحية"
        }
    }
}

// MARK: - Connection Invitation Model
public struct ConnectionInvitation: Codable, Identifiable, Equatable {
    public let id: UUID
    /// Unique cryptographic invitation token
    public let token: String
    
    // Initiator Info (S#1 & S#2)
    public let initiatorId: String
    public let initiatorDisplayName: String
    public let initiatorRole: UserRole
    public let initiatorKeyFingerprint: String
    
    // Timestamps
    public let createdAt: Date
    public let expiresAt: Date
    
    // Lifecycle Status
    public var status: InvitationStatus
    
    // Recipient Info (populated when accepted S#5)
    public var recipientId: String?
    public var recipientDisplayName: String?
    public var recipientRole: UserRole?
    public var recipientKeyFingerprint: String?
    
    public init(
        id: UUID = UUID(),
        token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased(),
        initiatorId: String,
        initiatorDisplayName: String,
        initiatorRole: UserRole,
        initiatorKeyFingerprint: String,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(48 * 3600), // 48 Hours validity
        status: InvitationStatus = .pending,
        recipientId: String? = nil,
        recipientDisplayName: String? = nil,
        recipientRole: UserRole? = nil,
        recipientKeyFingerprint: String? = nil
    ) {
        self.id = id
        self.token = token
        self.initiatorId = initiatorId
        self.initiatorDisplayName = initiatorDisplayName
        self.initiatorRole = initiatorRole
        self.initiatorKeyFingerprint = initiatorKeyFingerprint
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.recipientId = recipientId
        self.recipientDisplayName = recipientDisplayName
        self.recipientRole = recipientRole
        self.recipientKeyFingerprint = recipientKeyFingerprint
    }

    /// Whether this invitation has passed its expiration date
    public var isExpired: Bool {
        Date() > expiresAt
    }

    /// Generates the standard deep link URI
    public var deepLinkURL: URL {
        URL(string: "dawai://invite?token=\(token)")!
    }

    /// Generates formatted shareable text for native iOS sharing options (S#3)
    public var shareableText: String {
        let roleName = initiatorRole == .patient ? "المستفيد" : "مقدم الرعاية"
        return "دعوة اتصال آمنة من تطبيق دواء: يدعوك \(roleName) \(initiatorDisplayName) لربط الحسابين لمتابعة الأدوية.\nرابط الدعوة: dawai://invite?token=\(token)\nرمز الدعوة: \(token)"
    }
}

// MARK: - Active Relationship Model (S#7)
public struct ActiveRelationship: Codable, Identifiable, Equatable {
    public let id: UUID
    public let invitationId: UUID
    public let patientId: String
    public let patientDisplayName: String
    public let caregiverId: String
    public let caregiverDisplayName: String
    public let establishedAt: Date
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        invitationId: UUID,
        patientId: String,
        patientDisplayName: String,
        caregiverId: String,
        caregiverDisplayName: String,
        establishedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.invitationId = invitationId
        self.patientId = patientId
        self.patientDisplayName = patientDisplayName
        self.caregiverId = caregiverId
        self.caregiverDisplayName = caregiverDisplayName
        self.establishedAt = establishedAt
        self.isActive = isActive
    }
}
