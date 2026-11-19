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
        expiresAt: Date = Date().addingTimeInterval(15 * 60), // 15 Minutes validity
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

    /// Encodes this invitation into a URL-safe Base64 string so another device can validate and accept it without a server.
    public var encodedPayload: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a `ConnectionInvitation` from a URL-safe Base64 string.
    public static func decodeFromPayload(_ payload: String) -> ConnectionInvitation? {
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(ConnectionInvitation.self, from: data)
    }

    /// Generates the native custom-scheme deep link URI (`dawai://invite?token=...&payload=...`)
    public var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "dawai"
        components.host = "invite"
        var items = [URLQueryItem(name: "token", value: token)]
        let payload = encodedPayload
        if !payload.isEmpty {
            items.append(URLQueryItem(name: "payload", value: payload))
        }
        components.queryItems = items
        return components.url ?? URL(string: "dawai://invite?token=\(token)")!
    }

    /// Generates an HTTPS invite URL (`https://...`) so WhatsApp, iMessage, and Telegram render it as a clickable link
    /// that redirects into `dawai://invite?...` (and can also be pasted directly into the app).
    public var webInviteURL: URL {
        var components = URLComponents(string: "https://wajdwael.github.io/Dawai/invite/")!
        var items = [URLQueryItem(name: "token", value: token)]
        let payload = encodedPayload
        if !payload.isEmpty {
            items.append(URLQueryItem(name: "payload", value: payload))
        }
        components.queryItems = items
        return components.url ?? deepLinkURL
    }

    /// Generates formatted shareable text for native iOS sharing options (S#3)
    public var shareableText: String {
        let roleName = initiatorRole == .patient ? "المستفيد" : "مقدم الرعاية"
        return "دعوة اتصال آمنة من تطبيق دواي: يدعوك \(roleName) \(initiatorDisplayName) لربط الحسابين لمتابعة الأدوية.\n\(webInviteURL.absoluteString)"
    }
}

// MARK: - Portable Cross-Device Sync Bundle
public struct PortablePatientSyncBundle: Codable, Equatable {
    public let patientId: String
    public let patientDisplayName: String
    public let relationship: ActiveRelationship?
    public let medications: [MedicationItem]
    public let deletionRequests: [MedicationDeletionRequest]
    public let doseRecords: [DoseRecord]

    public init(
        patientId: String,
        patientDisplayName: String,
        relationship: ActiveRelationship?,
        medications: [MedicationItem],
        deletionRequests: [MedicationDeletionRequest],
        doseRecords: [DoseRecord]
    ) {
        self.patientId = patientId
        self.patientDisplayName = patientDisplayName
        self.relationship = relationship
        self.medications = medications
        self.deletionRequests = deletionRequests
        self.doseRecords = doseRecords
    }

    public var encodedPayload: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decodeFromPayload(_ payload: String) -> PortablePatientSyncBundle? {
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(PortablePatientSyncBundle.self, from: data)
    }

    public var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "dawai"
        components.host = "sync"
        components.queryItems = [URLQueryItem(name: "payload", value: encodedPayload)]
        return components.url ?? URL(string: "dawai://sync")!
    }
}

// MARK: - Active Relationship Model (S#7)
public struct ActiveRelationship: Codable, Identifiable, Equatable, Sendable {
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
