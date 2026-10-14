//
//  CreateInvitationSheet.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Steps 1-3:
//  Modal sheet allowing Patient or Caregiver to generate a secure 15-minute invitation link,
//  featuring a live countdown timer and tap-to-copy card.
//

import SwiftUI

public struct CreateInvitationSheet: View {
    let currentUser: UserIdentity
    @ObservedObject private var relationshipService = RelationshipService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var invitation: ConnectionInvitation?
    @State private var copiedLink = false
    @State private var timeRemaining: TimeInterval = 15 * 60
    @State private var isExpired: Bool = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(currentUser: UserIdentity) {
        self.currentUser = currentUser
    }

    private var targetRoleText: String {
        currentUser.role == .patient ? "مقدم رعاية" : "مستفيد"
    }

    private var timerFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.dawaiPrimary.opacity(0.12))
                                .frame(width: 68, height: 68)

                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Color.dawaiPrimary)
                        }

                        Text("إنشاء دعوة ربط آمنة")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("شارك الرابط المؤقت مع \(targetRoleText) لربط الحسابين ومتابعة الأدوية المشتركة.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 10)

                    if let invite = invitation {
                        // 1. Live Countdown Timer Card (15 minutes)
                        timerCard

                        // 2. Interactive Tap-to-Copy Link Card
                        tapToCopyCard(invite: invite)

                        // 3. Native iOS ShareLink & Simulator Actions
                        VStack(spacing: 12) {
                            if !isExpired {
                                ShareLink(
                                    item: invite.deepLinkURL,
                                    subject: Text("دعوة ربط حساب من تطبيق دواء"),
                                    message: Text(invite.shareableText)
                                ) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.up.fill")
                                            .font(.system(size: 17, weight: .bold))
                                        Text("مشاركة الرابط عبر التطبيقات")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color.dawaiPrimary)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: Color.dawaiPrimary.opacity(0.25), radius: 10, x: 0, y: 4)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Regenerate Button when expired
                                Button {
                                    regenerateInvitation()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 17, weight: .bold))
                                        Text("إنشاء رابط جديد (١٥ دقيقة)")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Generate Invitation Button
                        Button {
                            regenerateInvitation()
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
                .padding(.bottom, 28)
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
                if invitation == nil {
                    regenerateInvitation()
                } else {
                    updateCountdown()
                }
            }
            .onReceive(timer) { _ in
                updateCountdown()
            }
        }
    }

    // MARK: - 1. Live Countdown Timer Card
    private var timerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(
                        isExpired ? Color.red.opacity(0.2) : (timeRemaining < 180 ? Color.orange.opacity(0.2) : Color.dawaiPrimary.opacity(0.15)),
                        lineWidth: 3.5
                    )
                    .frame(width: 48, height: 48)

                Circle()
                    .trim(from: 0, to: isExpired ? 0 : CGFloat(timeRemaining / (15 * 60)))
                    .stroke(
                        isExpired ? Color.red : (timeRemaining < 180 ? Color.orange : Color.dawaiPrimary),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 48, height: 48)
                    .animation(.linear(duration: 1), value: timeRemaining)

                Image(systemName: isExpired ? "exclamationmark" : "timer")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isExpired ? Color.red : (timeRemaining < 180 ? Color.orange : Color.dawaiPrimary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isExpired ? "انتهت صلاحية الرابط" : "صلاحية الرابط تنتهي خلال:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(isExpired ? "00:00" : timerFormatted)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(isExpired ? Color.red : (timeRemaining < 180 ? Color.orange : Color.dawaiPrimary))

                    Text("(١٥ دقيقة فقط)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isExpired ? Color.red.opacity(0.06) : (timeRemaining < 180 ? Color.orange.opacity(0.06) : Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isExpired ? Color.red.opacity(0.3) : (timeRemaining < 180 ? Color.orange.opacity(0.3) : Color.black.opacity(0.06)),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 2. Interactive Tap-To-Copy Link Card
    private func tapToCopyCard(invite: ConnectionInvitation) -> some View {
        Button {
            copyInvitationLink(invite: invite)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header with Token and Status
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("رابط الدعوة المباشر")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("رمز التحقق: \(invite.token)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Copied badge or tap indicator
                    HStack(spacing: 5) {
                        Image(systemName: copiedLink ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 13, weight: .bold))

                        Text(copiedLink ? "تم النسخ!" : "اضغط للنسخ")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(copiedLink ? Color.white : Color.dawaiPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        copiedLink ? Color.green : Color.dawaiPrimary.opacity(0.12),
                        in: Capsule()
                    )
                }

                // URL Display Box
                HStack {
                    Text(invite.deepLinkURL.absoluteString)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dawaiPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 240.0 / 255.0, green: 242.0 / 255.0, blue: 246.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Bottom Hint
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dawaiPrimary)

                    Text(copiedLink ? "تم نسخ الرابط إلى الحافظة بنجاح، يمكنك مشاركته الآن." : "انقر على هذه البطاقة لنسخ الرابط مباشرة دون الحاجة لزر إضافي.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(copiedLink ? Color.green : .secondary)

                    Spacer()
                }
            }
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        copiedLink ? Color.green : Color.dawaiPrimary.opacity(0.3),
                        lineWidth: copiedLink ? 2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions & Timers
    private func copyInvitationLink(invite: ConnectionInvitation) {
        UIPasteboard.general.string = invite.shareableText
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copiedLink = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                copiedLink = false
            }
        }
    }

    private func regenerateInvitation() {
        withAnimation {
            let newInvite = relationshipService.createInvitation(initiator: currentUser)
            self.invitation = newInvite
            self.timeRemaining = 15 * 60
            self.isExpired = false
            self.copiedLink = false
        }
    }

    private func updateCountdown() {
        guard let invite = invitation else { return }
        let diff = invite.expiresAt.timeIntervalSince(Date())
        if diff <= 0 {
            timeRemaining = 0
            isExpired = true
        } else {
            timeRemaining = diff
            isExpired = false
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
