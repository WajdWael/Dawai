//
//  ReceiveInvitationSheet.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Steps 4 & 5:
//  Modal allowing recipient to enter or review an incoming invitation,
//  validating role compatibility, identity, and expiration before clicking Accept or Reject.
//

import SwiftUI

public struct ReceiveInvitationSheet: View {
    let currentUser: UserIdentity
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var themeService = ThemeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput: String = ""
    @State private var validatedInvitation: ConnectionInvitation?
    @State private var validationError: String?
    @State private var isProcessing = false

    public init(currentUser: UserIdentity, prefilledToken: String? = nil) {
        self.currentUser = currentUser
        _tokenInput = State(initialValue: prefilledToken ?? "")
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Icon & Title
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.dawaiPrimary.opacity(0.12))
                                .frame(width: 72, height: 72)

                            Image(systemName: "envelope.open.fill")
                                .dawaiFont(size: 32, weight: .bold)
                                .foregroundStyle(Color.dawaiPrimary)
                        }

                        if let invite = validatedInvitation {
                            Text("\(invite.initiatorDisplayName) يدعوك للارتباط")
                                .dawaiFont(size: 24, weight: .bold, design: .rounded)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("دعوة ارتباط")
                                .dawaiFont(size: 24, weight: .bold, design: .rounded)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.top, 16)

                    // Link Input Field (if not already loaded)
                    if validatedInvitation == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("رابط الدعوة")
                                    .dawaiFont(size: 16, weight: .bold)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Button {
                                    if let clip = UIPasteboard.general.string, !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        tokenInput = clip
                                        validateToken()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard")
                                            .dawaiFont(size: 12, weight: .semibold)
                                        Text("لصق وفحص")
                                            .dawaiFont(size: 12, weight: .bold)
                                    }
                                    .foregroundStyle(Color.dawaiPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.dawaiPrimary.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            HStack {
                                TextField("الصق رابط الدعوة هنا", text: $tokenInput)
                                    .dawaiFont(size: 16, weight: .medium, design: .monospaced)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .multilineTextAlignment(.leading)

                                if !tokenInput.isEmpty {
                                    Button {
                                        tokenInput = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                            // Error Display (S#4: Incompatible roles, expired, invalid)
                            if let error = validationError {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                        .font(.subheadline)
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.top, 4)
                            }

                            Button {
                                validateToken()
                            } label: {
                                HStack(spacing: 8) {
                                    if isProcessing {
                                        ProgressView().tint(.white)
                                    }
                                    Text("فحص الدعوة")
                                        .dawaiFont(size: 17, weight: .bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    tokenInput.isEmpty
                                        ? AnyShapeStyle(Color.gray.opacity(0.3))
                                        : AnyShapeStyle(Color.dawaiPrimary)
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(tokenInput.isEmpty || isProcessing)
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        .padding(18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                    }

                    // S#5: Validated Invitation Review & Decision
                    if let invitation = validatedInvitation {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text("مرسل الدعوة")
                                    .dawaiFont(size: 15, weight: .medium)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(invitation.initiatorDisplayName)
                                    .dawaiFont(size: 16, weight: .bold)
                                    .foregroundStyle(.primary)
                            }

                            HStack {
                                Text("دور المرسل")
                                    .dawaiFont(size: 15, weight: .medium)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(invitation.initiatorRole.titleArabic)
                                    .dawaiFont(size: 15, weight: .bold)
                                    .foregroundStyle(Color.dawaiPrimary)
                            }

                            Divider()

                            // S#5: Action Buttons (Accept / Reject)
                            VStack(spacing: 12) {
                                Button {
                                    acceptInvitation(invitation)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("قبول وتفعيل الارتباط")
                                            .dawaiFont(size: 17, weight: .bold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.dawaiPrimary)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    rejectInvitation(invitation)
                                } label: {
                                    Text("رفض الدعوة")
                                        .dawaiFont(size: 16, weight: .bold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(.ultraThinMaterial)
                                        .foregroundStyle(.red)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.dawaiBackground.ignoresSafeArea())
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("قبول دعوة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                    }
                    .dawaiFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .onAppear {
                if !tokenInput.isEmpty {
                    validateToken()
                } else if let clip = UIPasteboard.general.string,
                          clip.contains("payload=") || clip.contains("dawai://") || clip.contains("Dawai/invite") || clip.contains("eyJ") {
                    tokenInput = clip
                    validateToken()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }

    private func validateToken() {
        validationError = nil
        isProcessing = true
        do {
            let invite = try relationshipService.validateInvitation(
                token: tokenInput,
                recipient: currentUser
            )
            withAnimation {
                self.validatedInvitation = invite
                self.isProcessing = false
            }
        } catch let error as LocalizedError {
            withAnimation {
                self.validationError = error.errorDescription ?? error.localizedDescription
                self.isProcessing = false
            }
        } catch {
            withAnimation {
                self.validationError = "حدث خطأ غير متوقع أثناء فحص الرمز."
                self.isProcessing = false
            }
        }
    }

    private func acceptInvitation(_ invitation: ConnectionInvitation) {
        do {
            try relationshipService.acceptInvitation(token: invitation.token, recipient: currentUser)
            dismiss()
        } catch let error as LocalizedError {
            validationError = error.errorDescription
        } catch {
            validationError = "تعذر قبول الدعوة."
        }
    }

    private func rejectInvitation(_ invitation: ConnectionInvitation) {
        do {
            try relationshipService.rejectInvitation(token: invitation.token, recipient: currentUser)
            dismiss()
        } catch let error as InvitationError {
            validationError = error.errorDescription ?? "تعذر رفض الدعوة."
        } catch {
            validationError = "تعذر رفض الدعوة."
        }
    }
}

#Preview {
    ReceiveInvitationSheet(
        currentUser: UserIdentity(
            role: .caregiver,
            displayName: "عمر",
            keyFingerprint: "1a2b3c4d5e6f7a8b"
        )
    )
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
