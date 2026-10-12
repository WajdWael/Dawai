//
//  RoleSelectionView.swift
//  Dawai
//
//  Use-Case 1 (UC-1) Step 2: Role Selection (True RTL Arabic)
//

import SwiftUI

/// S#2: User selects their role as either Patient (مستفيد) or Caregiver (مقدم الرعاية).
/// Built with native Right-To-Left (RTL) hierarchy matching the Arabic design.
public struct RoleSelectionView: View {
    @ObservedObject var viewModel: IdentitySetupViewModel

    public init(viewModel: IdentitySetupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // Screen Background: soft clean slate
            Color(red: 243.0 / 255.0, green: 245.0 / 255.0, blue: 249.0 / 255.0)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                // Header Title: كيف رح تستخدم التطبيق؟
                // In RTL, .leading aligns to the RIGHT side of the screen.
                Text("كيف رح تستخدم التطبيق؟")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                // Error Message (Alternate Course 1)
                if let errorMessage = viewModel.roleErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Role Options Cards
                VStack(spacing: 16) {
                    // Option 1: Beneficiary / Patient (انا مستفيد)
                    ArabicRoleCard(
                        title: "انا مستفيد",
                        subtitle: "(مريض/متلقي الرعاية)",
                        systemImage: "person.fill",
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectRoleAndProceed(.patient)
                            }
                        }
                    )

                    // Option 2: Caregiver (انا مقدم الرعاية)
                    ArabicRoleCard(
                        title: "انا مقدم الرعاية",
                        subtitle: nil,
                        systemImage: "heart.square.fill",
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectRoleAndProceed(.caregiver)
                            }
                        }
                    )
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Custom native Arabic role card with true RTL alignment.
/// In RTL: Leading edge is on the RIGHT, Trailing edge is on the LEFT.
private struct ArabicRoleCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 1. Icon appears on the RIGHT (leading edge in RTL)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.dawaiPrimary)
                    .frame(width: 36, height: 36)

                // 2. Arabic Text appears next to the icon (leading-aligned in RTL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.dawaiPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }

                // 3. Spacer pushes towards the LEFT (trailing edge in RTL)
                Spacer()
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle != nil ? "\(title), \(subtitle!)" : title)
    }
}

#Preview {
    NavigationStack {
        RoleSelectionView(viewModel: IdentitySetupViewModel())
            .tint(Color.dawaiPrimary)
    }
    .environment(\.layoutDirection, .rightToLeft)
}
