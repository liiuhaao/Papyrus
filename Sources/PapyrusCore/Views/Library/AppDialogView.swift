import SwiftUI

private struct DialogSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

private extension View {
    func dialogSurface() -> some View {
        modifier(DialogSurfaceModifier())
    }
}

struct LibraryMigrationDialog: View {
    let destinationName: String
    let onMigrate:    () -> Void
    let onUpdatePath: () -> Void
    let onCancel:     () -> Void

    var body: some View {
        ZStack {
            Color(white: 0, opacity: 0.001)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.accentColor)
                    }

                    VStack(spacing: 5) {
                        Text("Change Library Location")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Destination: \(destinationName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Option cards
                VStack(spacing: 8) {
                    optionCard(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .accentColor,
                        title: "Migrate",
                        description: "Move all PDFs and the database to the new location.",
                        action: onMigrate
                    )
                    optionCard(
                        icon: "link",
                        iconColor: .secondary,
                        title: "Just Update Path",
                        description: "Switch to a new empty library. Existing files stay in place.",
                        action: onUpdatePath
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                Divider().opacity(0.5)

                // Cancel
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .frame(width: 360)
            .dialogSurface()
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        ))
    }

    private func optionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Modifier helpers

extension View {
    func appDialog(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                content()
                    .zIndex(999)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isPresented.wrappedValue)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isPresented.wrappedValue)
    }
}
