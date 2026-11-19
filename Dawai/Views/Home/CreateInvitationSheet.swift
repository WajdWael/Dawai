//
//  CreateInvitationSheet.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Steps 1-3:
//  Modal sheet allowing Patient or Caregiver to generate a secure 15-minute invitation link,
//  featuring a live countdown timer, real-time CloudKit polling, and automatic dismissal
//  upon recipient acceptance.
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
    @State private var acceptedSuccessfully: Bool = false
    @State private var syncTicks: Int = 0

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

    private var isPatientAlreadyLinked: Bool {
        currentUser.role == .patient && relationshipService.hasReachedCaregiverLimit(forPatient: currentUser.id)
    }

    private var partnerDisplayName: String {
        if currentUser.role == .patient {
            let names = relationshipService.activeCaregivers(forPatient: currentUser.id).map(\.caregiverDisplayName)
            if !names.isEmpty {
                return names.joined(separator: "، ")
            }
            return "مقدم الرعاية"
        } else {
            if let rel = relationshipService.activeRelationships.first(where: { $0.caregiverId == currentUser.id && $0.isActive }) {
                return rel.patientDisplayName
            }
            return "المستفيد"
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                if acceptedSuccessfully {
                    // MARK: – Success Acceptance Banner (Auto-dismisses)
                    Section {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.dawaiTaken.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "checkmark.circle.fill")
                                    .dawaiFont(size: 40, weight: .bold)
                                    .foregroundStyle(Color.dawaiTaken)
                            }
                            .padding(.top, 8)

                            Text("تم قبول الدعوة بنجاح!")
                                .dawaiFont(size: 22, weight: .bold)
                                .foregroundStyle(.primary)

                            Text("تم ربط حسابك مع \(partnerDisplayName) بنجاح. أصبحت المتابعة المشتركة وتحديثات الأدوية مفعلة الآن.")
                                .dawaiFont(size: 14, weight: .regular)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 8)

                            Button {
                                dismiss()
                            } label: {
                                Text("تم وإغلاق")
                                    .dawaiFont(size: 16, weight: .bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.dawaiPrimary)
                            .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    // MARK: – Header Title & Subtitle
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isPatientAlreadyLinked ? "الحساب مرتبط حالياً" : "ربط حساب \(targetRoleText)")
                                .dawaiFont(size: 20, weight: .bold)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(
                                isPatientAlreadyLinked
                                    ? "أنت مرتبط بالفعل بمقدم رعاية نشط. لا يمكن ربط أكثر من مقدم رعاية واحد للمستفيد في نفس الوقت."
                                    : "شارك الرابط المؤقت مع \(targetRoleText) لربط الحسابين ومتابعة الأدوية المشتركة."
                            )
                            .dawaiFont(size: 14, weight: .regular)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 0, trailing: 16))
                    }

                    if isPatientAlreadyLinked {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .dawaiFont(size: 24)
                                    .foregroundStyle(Color.dawaiTaken)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("يوجد مقدم رعاية مرتبط بحسابك (\(partnerDisplayName))")
                                        .dawaiFont(size: 15, weight: .bold)
                                        .foregroundStyle(.primary)
                                    Text("لربط مقدم رعاية آخر، يرجى إنهاء الارتباط الحالي من الشاشة الرئيسية أولاً.")
                                        .dawaiFont(size: 13)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    } else if let invite = invitation {

                        // MARK: – Timer Section
                        Section {
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
                                        .dawaiFont(size: 14, weight: .semibold)
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
                        } header: {
                            Text("مدة الصلاحية")
                                .dawaiFont(size: 13, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }

                        // MARK: – Invite Link Section
                        Section {
                            Button {
                                copyInvitationLink(invite: invite)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: copiedLink ? "checkmark.circle.fill" : "doc.on.doc")
                                        .dawaiFont(size: 18, weight: .semibold)
                                        .foregroundStyle(copiedLink ? .green : Color.dawaiPrimary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(copiedLink ? "تم نسخ الرابط!" : "نسخ رابط الدعوة")
                                            .dawaiFont(size: 16, weight: .medium)
                                            .foregroundStyle(copiedLink ? .green : .primary)
                                        Text("اضغط لنسخ الرابط وإرساله مباشرة")
                                            .dawaiFont(size: 12)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if !isExpired {
                                ShareLink(
                                    item: invite.shareableText,
                                    subject: Text("دعوة ربط حساب من تطبيق دواي")
                                ) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.up")
                                            .dawaiFont(size: 18, weight: .semibold)
                                            .foregroundStyle(Color.dawaiPrimary)
                                            .frame(width: 24)

                                        Text("مشاركة الرابط")
                                            .dawaiFont(size: 16, weight: .medium)
                                            .foregroundStyle(Color.dawaiPrimary)

                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Text("رابط الدعوة")
                                .dawaiFont(size: 13, weight: .semibold)
                                .foregroundStyle(.secondary)
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
            }
            .listStyle(.insetGrouped)
            .compactListTopMargin()
            .preferredColorScheme(themeService.colorScheme)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale.dawaiArabic)
            .navigationTitle("دعوة اتصال")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") { dismiss() }
                        .dawaiFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .onAppear {
                checkIfAlreadyAccepted()
                guard !isPatientAlreadyLinked, !acceptedSuccessfully else { return }

                if let existing = relationshipService.outgoingInvitations(for: currentUser, status: .pending).first(where: { !$0.isExpired }) {
                    self.invitation = existing
                    updateCountdown()
                } else {
                    relationshipService.clearStalePendingInvitations(for: currentUser.id)
                    regenerateInvitation()
                }

                // Immediate CloudKit pull when opening sheet
                CloudKitSyncManager.shared.triggerBackgroundFlushAndSync()
            }
            .onChange(of: relationshipService.activeRelationships) { _ in
                checkIfAlreadyAccepted()
            }
            .onReceive(timer) { _ in
                updateCountdown()
                syncTicks += 1
                // Trigger fast background pull from iCloud every 3 seconds while waiting
                if syncTicks % 3 == 0 {
                    CloudKitSyncManager.shared.triggerBackgroundFlushAndSync()
                    checkIfAlreadyAccepted()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale.dawaiArabic)
    }

    // MARK: - Actions & Timers

    private func checkIfAlreadyAccepted() {
        guard !acceptedSuccessfully else { return }

        let isLinked: Bool
        if currentUser.role == .patient {
            if let invite = invitation {
                isLinked = relationshipService.activeRelationships.contains {
                    $0.invitationId == invite.id
                }
            } else {
                isLinked = relationshipService.hasReachedCaregiverLimit(forPatient: currentUser.id)
            }
        } else {
            if let invite = invitation {
                isLinked = relationshipService.activeRelationships.contains {
                    $0.invitationId == invite.id || ($0.caregiverId == currentUser.id && $0.isActive)
                }
            } else {
                isLinked = !relationshipService.activeRelationships.filter({ $0.caregiverId == currentUser.id && $0.isActive }).isEmpty
            }
        }

        if isLinked {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.acceptedSuccessfully = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                dismiss()
            }
        }
    }

    private func copyInvitationLink(invite: ConnectionInvitation) {
        UIPasteboard.general.string = invite.webInviteURL.absoluteString
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
        checkIfAlreadyAccepted()
        guard let invite = invitation, !acceptedSuccessfully else { return }
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
