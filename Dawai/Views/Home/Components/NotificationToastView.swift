//
//  NotificationToastView.swift
//  Dawai
//
//  Use-Case 2 (UC-2) Step 8:
//  Apple Glass Mode notification toast banner informing users of connection events
//  (e.g., invitation accepted, connection confirmed & active).
//

import SwiftUI

public struct NotificationToastView: View {
    let message: String
    let onDismiss: () -> Void

    public init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dawaiPrimary)
                    .frame(width: 32, height: 32)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.dawaiGlassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation {
                    onDismiss()
                }
            }
        }
    }
}
