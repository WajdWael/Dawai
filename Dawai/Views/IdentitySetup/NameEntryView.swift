//
//  NameEntryView.swift
//  Dawai
//
//  Use-Case 1 (UC-1) Step 3: First-Name Entry Screen (Direct to Home)
//

import SwiftUI

/// S#3: User enters their first name.
/// Validates the entered name against Alternate Courses 2 & 3.
/// When user taps Next, securely provisions cryptographic credentials and redirects to Home Page.
public struct NameEntryView: View {
    @ObservedObject var viewModel: IdentitySetupViewModel
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFieldFocused: Bool

    public init(viewModel: IdentitySetupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            // Selected Role Reminder
            if let role = viewModel.selectedRole {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: role.systemImage)
                            .foregroundStyle(Color.dawaiPrimary)
                            .font(.headline)
                        
                        Text("الدور المختار")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(role.titleArabic)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.dawaiPrimary)
                    }
                }
            }

            // Name Entry Section
            Section {
                HStack {
                    TextField("أدخل اسمك الأول", text: $viewModel.firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.leading)
                        .focused($isFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            submit()
                        }
                    
                    if !viewModel.firstName.isEmpty && !viewModel.isProcessingSetup {
                        Button {
                            viewModel.firstName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("مسح النص")
                    }
                }

                // Alternate Courses 2 & 3 Name Error Display
                if let errorMessage = viewModel.nameErrorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding(.top, 2)
                        
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Alternate Course 4 Setup Failure Error Display
                if let setupError = viewModel.setupErrorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding(.top, 2)
                        
                        Text(setupError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("ما هو اسمك؟")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } footer: {
                // Explicit specification footnote (RTL leading aligned)
                Text("لا يتطلب التطبيق بريداً إلكترونياً أو كلمة مرور أو اسم مستخدم. يُستخدم الاسم الأول كاسم عرض فقط ولا يُستخدم للمصادقة أو البحث.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            // Active Provisioning Status
            if viewModel.isProcessingSetup {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.dawaiPrimary)
                        Text(viewModel.currentProgressStageText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    submit()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isProcessingSetup {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isProcessingSetup ? "جاري الإعداد..." : "متابعة")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isProcessingSetup)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.bar)
            }
        }
        .navigationTitle("الاسم الأول")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func submit() {
        isFieldFocused = false
        Task {
            await viewModel.submitNameAndCompleteSetup(appState: appState)
        }
    }
}

#Preview {
    let vm = IdentitySetupViewModel()
    vm.selectedRole = .patient
    return NavigationStack {
        NameEntryView(viewModel: vm)
            .environmentObject(AppState())
            .tint(Color.dawaiPrimary)
    }
    .environment(\.layoutDirection, .rightToLeft)
}
