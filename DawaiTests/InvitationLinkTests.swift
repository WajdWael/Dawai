//
//  InvitationLinkTests.swift
//  DawaiTests
//
//  TC-5: expired / invalid invitation links handled after the app is opened from the link.
//

import Foundation
import XCTest
@testable import Dawai

@MainActor
final class InvitationLinkTests: XCTestCase {
    private func makeService() -> RelationshipService {
        RelationshipService(store: InMemoryInvitationStore())
    }

    private let patient = UserIdentity(id: "patient_link_1", role: .patient, displayName: "منى", keyFingerprint: "fp_p")
    private let caregiver = UserIdentity(id: "caregiver_link_1", role: .caregiver, displayName: "ياسر", keyFingerprint: "fp_c")

    private func assertValidation(
        _ service: RelationshipService,
        link: String,
        recipient: UserIdentity,
        throws expected: InvitationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try service.validateInvitation(token: link, recipient: recipient), file: file, line: line) { error in
            XCTAssertEqual(error as? InvitationError, expected, file: file, line: line)
        }
    }

    func testValidLinkPassesValidation() throws {
        let service = makeService()
        let invite = ConnectionInvitation(
            initiatorId: patient.id,
            initiatorDisplayName: patient.displayName,
            initiatorRole: .patient,
            initiatorKeyFingerprint: patient.keyFingerprint
        )
        let url = invite.deepLinkURL
        XCTAssertTrue(service.isInviteLink(url))
        XCTAssertEqual(service.handleIncomingURL(url), invite.token)
        let validated = try service.validateInvitation(token: url.absoluteString, recipient: caregiver)
        XCTAssertEqual(validated.token, invite.token)
    }

    func testExpiredLinkIsRejectedAsExpiredForBothLinkFormats() {
        let service = makeService()
        let invite = ConnectionInvitation(
            initiatorId: patient.id,
            initiatorDisplayName: patient.displayName,
            initiatorRole: .patient,
            initiatorKeyFingerprint: patient.keyFingerprint,
            createdAt: Date().addingTimeInterval(-3600),
            expiresAt: Date().addingTimeInterval(-60)
        )
        XCTAssertTrue(invite.isExpired)
        assertValidation(service, link: invite.deepLinkURL.absoluteString, recipient: caregiver, throws: .tokenExpired)
        assertValidation(service, link: invite.webInviteURL.absoluteString, recipient: caregiver, throws: .tokenExpired)
    }

    func testMalformedOrUnknownInviteLinksAreRejectedAsInvalid() {
        let service = makeService()
        let badLinks = [
            "dawai://invite",
            "dawai://invite?payload=not-a-valid-payload",
            "dawai://invite?token=deadbeefdeadbeef",
            "https://wajdwael.github.io/Dawai/invite/?token=zzzz"
        ]
        for link in badLinks {
            let url = URL(string: link)!
            XCTAssertTrue(service.isInviteLink(url), link)
            assertValidation(service, link: link, recipient: caregiver, throws: .tokenNotFound)
        }
    }

    func testMalformedPayloadLinkReturnsNoTokenSoAppMustStillSurfaceAnError() {
        let service = makeService()
        let url = URL(string: "dawai://invite?payload=not-a-valid-payload")!
        XCTAssertNil(service.handleIncomingURL(url))
        XCTAssertTrue(service.isInviteLink(url))
    }

    func testNonInviteURLIsNotTreatedAsInvite() {
        let service = makeService()
        XCTAssertFalse(service.isInviteLink(URL(string: "https://example.com/other")!))
        XCTAssertFalse(service.isInviteLink(URL(string: "mailto:test@example.com")!))
    }

    func testSelfAndIncompatibleRoleLinksAreRejected() {
        let service = makeService()
        let invite = ConnectionInvitation(
            initiatorId: patient.id,
            initiatorDisplayName: patient.displayName,
            initiatorRole: .patient,
            initiatorKeyFingerprint: patient.keyFingerprint
        )
        let link = invite.deepLinkURL.absoluteString
        assertValidation(service, link: link, recipient: patient, throws: .selfInvitation)

        let otherPatient = UserIdentity(id: "patient_link_2", role: .patient, displayName: "هند", keyFingerprint: "fp_p2")
        assertValidation(
            service,
            link: link,
            recipient: otherPatient,
            throws: .incompatibleRoles(initiatorRole: .patient, recipientRole: .patient)
        )
    }
}

