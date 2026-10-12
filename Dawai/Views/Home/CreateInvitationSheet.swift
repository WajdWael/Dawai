//
//  CreateInvitationSheet.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Steps 1-3:
//  Modal sheet allowing Patient or Caregiver to generate a secure invitation link,
//  inspect its cryptographic parameters and expiration, and share it via native iOS share sheet.
//

import SwiftUI

public struct CreateInvitationSheet: View {
    let currentUser: UserIdentity
    @ObservedObject private var relationshipService = RelationshipService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var invitation: ConnectionInvitation?
    @State private var copiedLink = false
    @State private var copiedToken = false

    public init(currentUser: UserIdentity) {
        self.currentUser = currentUser
    }

    private var targetRoleText: String {
        currentUser.role == .patient ? "مقدم رعاية" : "مستفيد"
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Card (Glass Mode)
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.dawaiPrimary.opacity(0.12))
                                .frame(width: 72, height: 72)

                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Color.dawaiPrimary)
                        }

                        Text("إنشاء دعوة ربط آمنة")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("أنشئ رابط دعوة مؤقت لمشاركته مع \(targetRoleText). تكتمل العلاقة بعد قبول الطرف الآخر وتأكيدك المتبادل.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)

                    if let invite = invitation {
                        // Invitation Details Card (Glass Mode)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("رمز الدعوة المؤقت")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(invite.token)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.dawaiPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.dawaiPrimary.opacity(0.1), in: Capsule())
                            }

                            Divider()

                            HStack {
                                Text("صلاحية الرابط")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text("48 ساعة (حتى \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("الطرف المطلوب ربطه")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(targetRoleText)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.dawaiPrimary)
                            }
                        }
                        .padding(18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )

                        // S#3: Native Share and Copy Actions
                        VStack(spacing: 12) {
                            // Native iOS ShareLink (Messages, WhatsApp, AirDrop)
                            ShareLink(
                                item: invite.deepLinkURL,
                                subject: Text("دعوة ربط حساب من تطبيق دواء"),
                                message: Text(invite.shareableText)
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("مشاركة الرابط عبر التطبيقات")
                                        .font(.system(size: 17, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Color.dawaiPrimary)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            // Copy Link Action
                            Button {
                                UIPasteboard.general.string = invite.deepLinkURL.absoluteString
                                withAnimation { copiedLink = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedLink = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedLink ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(copiedLink ? .green : Color.dawaiPrimary)

                                    Text(copiedLink ? "تم نسخ الرابط بنجاح" : "نسخ رابط الدعوة")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            // Simulator Testing Helper: Simulate Recipient Accept (S#5)
                            Button {
                                relationshipService.simulateRecipientAcceptance(
                                    for: invite.id,
                                    simulatedRecipientName: currentUser.role == .patient ? "سارة (مقدم رعاية)" : "عمر (مستفيد)"
                                )
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill")
                                    Text("محاكاة قبول الطرف الآخر (لتجربة المحاكي)")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.dawaiSecondary)
                                .padding(.top, 4)
                            }
                            .buttonStyle(.plain)
                        }

                    } else {
                        // Generate Invitation Button (S#2)
                        Button {
                            withAnimation {
                                invitation = relationshipService.createInvitation(initiator: currentUser)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.headline)
                                Text("إنشاء الرابط الآن")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.dawaiPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(red: 243.0 / 255.0, green: 245.0 / 255.0, blue: 249.0 / 255.0).ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("دعوة اتصال")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .onAppear {
                // Auto generate invitation on open for fast seamless UX (S#1 -> S#2)
                if invitation == nil {
                    invitation = relationshipService.createInvitation(initiator: currentUser)
                }
            }
        }
    }
}

#Preview {
    CreateInvitationSheet(
        currentUser: UserIdentity(
            role: .patient,
            displayName: "سارة",
            keyFingerprint: "e28fa4891b0c9f1a"
        )
    )
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
