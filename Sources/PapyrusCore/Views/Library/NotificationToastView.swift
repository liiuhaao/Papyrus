// NotificationToastView.swift
// Unified notification system — replaces the capsule toast + ImportProgressPanel.

import SwiftUI

// MARK: - Notification Stack

struct NotificationStack: View {
    let toast: String?

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if let toast {
                ToastNotificationCard(message: toast)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

// MARK: - Toast Card (instant feedback)

private struct ToastNotificationCard: View {
    let message: String

    private var isErrorMessage: Bool {
        let normalized = message.lowercased()
        return normalized.contains("failed") || normalized.contains("error")
    }

    private var icon: String {
        if isErrorMessage { return "exclamationmark.circle.fill" }
        if message.hasPrefix("Status:") { return statusIcon(from: message) }
        if message.hasPrefix("Rating cleared") { return "star" }
        if message.hasPrefix("Rating:") { return "star.fill" }
        if message.lowercased().contains("copied") { return "doc.on.doc.fill" }
        return "checkmark"
    }

    private var iconColor: Color {
        if isErrorMessage { return .red }
        if message.contains("Reading")  { return AppStatusStyle.tint(for: .reading)  }
        if message.contains("Read") { return AppStatusStyle.tint(for: .read) }
        if message.contains("Unread")   { return AppStatusStyle.tint(for: .unread)   }
        if message.hasPrefix("Rating:") { return .orange }
        return .secondary
    }

    private func statusIcon(from msg: String) -> String {
        if msg.contains("Reading")  { return AppStatusStyle.icon(for: .reading)  }
        if msg.contains("Read") { return AppStatusStyle.icon(for: .read) }
        return AppStatusStyle.icon(for: .unread)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}
