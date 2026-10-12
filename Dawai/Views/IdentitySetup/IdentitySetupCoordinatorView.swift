//
//  IdentitySetupCoordinatorView.swift
//  Dawai
//
//  Use-Case 1 (UC-1): Setup Flow Coordinator
//

import SwiftUI

/// Houses the NavigationStack orchestrating the UC-1 setup sequence:
/// S#2 Role Selection -> S#3 Name Entry -> Home Page.
public struct IdentitySetupCoordinatorView: View {
    @StateObject private var viewModel = IdentitySetupViewModel()

    public init() {}

    public var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            RoleSelectionView(viewModel: viewModel)
                .navigationDestination(for: SetupStep.self) { step in
                    switch step {
                    case .nameEntry:
                        NameEntryView(viewModel: viewModel)
                    }
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#Preview {
    IdentitySetupCoordinatorView()
        .environmentObject(AppState())
        .environment(\.layoutDirection, .rightToLeft)
        .tint(Color.dawaiPrimary)
}
