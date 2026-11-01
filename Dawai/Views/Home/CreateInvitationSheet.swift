//
//  CreateInvitationSheet.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Steps 1-3:
//  Modal sheet allowing Patient or Caregiver to generate a secure 15-minute invitation link,
//  featuring a live countdown timer and tap-to-copy card.
//

import SwiftUI
import Combine

public struct CreateInvitationSheet: View {
    let currentUser: UserIdentity
    @ObservedObject private var relationshipService = RelationshipService.shared
    @ObservedObject private var themeService = ThemeService.shared
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

    private var timerColor: Color {
        isExpired ? .red : (timeRemaining < 180 ? Color.dawaiWarning : Color.dawaiPrimary)
    }

    private var timerProgress: Double {
        isExpired ? 0 : timeRemaining / (15 * 60)
    }

    public var body: some View {
        NavigationStack {
            List {
                // MARK: – Subtitle description header
                Section {
                    Text("شارك الرابط المؤقت مع \(targetRoleText) لربط الحسابين ومتابعة الأدوية المشتركة.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if let invite = invitation {

                    // MARK: – Timer Section
                    Section("مدة الصلاحية") {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .stroke(timerColor.opacity(0.2), lineWidth: 3.5)
                                Circle()
                                    .trim(from: 0, to: timerProgress)
                                    .stroke(timerColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 1), value: timeRemaining)
                                Image(systemName: isExpired ? "xmark" : "timer")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(timerColor)
                            }
                            .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(isExpired ? "انتهت صلاحية الرابط" : "ينتهي الرابط خلال")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(isExpired ? "00:00" : timerFormatted)
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundStyle(timerColor)
                            }

                            Spacer()

                            if isExpired {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .imageScale(.medium)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // MARK: – Invite Link Section
                    Section("رابط الدعوة") {
                        LabeledContent("رمز التحقق") {
                            Text(invite.token)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            copyInvitationLink(invite: invite)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(copiedLink ? "تم النسخ!" : "نسخ الرابط")
                                        .foregroundStyle(copiedLink ? .green : .primary)
                                    Text(invite.deepLinkURL.absoluteString)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } icon: {
                                Image(systemName: copiedLink ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundStyle(copiedLink ? .green : Color.dawaiPrimary)
                            }
                        }
                        .buttonStyle(.plain)

                        if !isExpired {
                            ShareLink(
                                item: invite.deepLinkURL,
                                subject: Text("دعوة ربط حساب من تطبيق دواء"),
                                message: Text(invite.shareableText)
                            ) {
                                Label("مشاركة الرابط", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    // MARK: – Regenerate when expired
                    if isExpired {
                        Section {
                            Button(role: .destructive) {
                                regenerateInvitation()
                            } label: {
                                Label("إنشاء رابط جديد", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }

                    // MARK: – Simulator Testing (DEBUG only)
                    #if DEBUG
                    Section {
                        Button {
                            relationshipService.simulateRecipientAcceptance(
                                for: invite.id,
                                simulatedRecipientName: currentUser.role == .patient ? "سارة (مقدم رعاية)" : "عمر (مستفيد)"
                            )
                            dismiss()
                        } label: {
                            Label("محاكاة قبول الطرف الآخر", systemImage: "play.circle")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("أدوات المحاكي")
                    } footer: {
                        Text("يظهر هذا الخيار في وضع التطوير فقط ولن يظهر في TestFlight أو الإنتاج.")
                    }
                    #endif

                } else {

                    // MARK: – Initial Generate State
                    Section {
                        Button {
                            regenerateInvitation()
                        } label: {
                            Label("إنشاء الرابط الآن", systemImage: "sparkles")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } footer: {
                        Text("سيتم إنشاء رابط دعوة آمن صالح لمدة 15 دقيقة.")
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("دعوة اتصال")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .onAppear {
                // Clean up stale pending invitations before creating a fresh one
                relationshipService.clearStalePendingInvitations(for: currentUser.id)
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

    // MARK: - Actions & Timers

    private func copyInvitationLink(invite: ConnectionInvitation) {
        UIPasteboard.general.string = invite.shareableText
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copiedLink = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { copiedLink = false }
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
