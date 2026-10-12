//
//  IdentityDetailsSheet.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Cryptographic Credentials Inspector (Arabic Primary)
//

import SwiftUI

/// Modal sheet inspecting the securely established anonymous credentials.
public struct IdentityDetailsSheet: View {
    let identity: UserIdentity
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copiedToClipboard = false
    @State private var showingResetConfirmation = false

    public init(identity: UserIdentity) {
        self.identity = identity
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("الدور")
                        Spacer()
                        Label(identity.role.titleArabic, systemImage: identity.role.systemImage)
                            .foregroundStyle(Color.dawaiPrimary)
                    }

                    HStack {
                        Text("اسم العرض")
                        Spacer()
                        Text(identity.displayName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("تاريخ الإنشاء")
                        Spacer()
                        Text(identity.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("ملف الهوية")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("معرّف التطبيق المجهول")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(identity.id)
                                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = identity.id
                                withAnimation { copiedToClipboard = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedToClipboard = false
                                }
                            } label: {
                                Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedToClipboard ? .green : Color.dawaiPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("بصمة المفتاح العام SHA-256")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(identity.keyFingerprint)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("خوارزمية التشفير")
                        Spacer()
                        Text("NIST P-256 (ECDSA)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("أمان التخزين")
                        Spacer()
                        Text("Apple Keychain (على هذا الجهاز فقط)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("الأمان التشفيري")
                } footer: {
                    Text("هذا المعرّف المجهول فريد لهذا الجهاز ولا يمكن ربطه بأي هوية خارجية أو حساب مستخدم.")
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("إعادة ضبط الهوية وتجربة التشغيل الأول (UC-1)")
                        }
                    }
                } header: {
                    Text("اختبار المطورين")
                } footer: {
                    Text("يقوم بمسح مفاتيح Keychain وإعادة تشغيل التطبيق كأول مرة لتجربة اختيار الدور والاسم.")
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("الإعدادات وبيانات الاعتماد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        dismiss()
                    }
                    .foregroundStyle(Color.dawaiPrimary)
                }
            }
            .confirmationDialog(
                "إعادة ضبط هوية التطبيق؟",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("إعادة الضبط والبدء من جديد", role: .destructive) {
                    dismiss()
                    RelationshipService.shared.resetForTesting()
                    appState.resetIdentityForTesting()
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيؤدي هذا إلى مسح المفاتيح المشفرة وإعادتك لشاشة اختيار الدور.")
            }
        }
    }
}

#Preview {
    IdentityDetailsSheet(
        identity: UserIdentity(
            role: .caregiver,
            displayName: "سارة",
            keyFingerprint: "e28fa4891b0c9f1a"
        )
    )
    .tint(Color.dawaiPrimary)
    .environment(\.layoutDirection, .rightToLeft)
}
