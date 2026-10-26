import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Brand.teal
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isEnabled ? .white : Brand.ink3.opacity(0.6))
            .background(Capsule().fill(isEnabled ? tint : Brand.hairline))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Brand.teal)
            .background(Capsule().fill(.white))
            .shadow(color: Brand.ink.opacity(0.06), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Brand.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Capsule().fill(tint))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Layout

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .shadow(color: Brand.ink.opacity(0.05), radius: 12, y: 4)
    }
}

/// Onboarding step frame: back button, segmented progress, big title, subtitle, content, bottom button.
struct StepScaffold<Content: View, Footer: View>: View {
    var step: Int
    var total: Int
    var title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundStyle(Brand.teal)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white))
                    }
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? Brand.teal : Brand.hairline)
                        .frame(width: 36, height: 5)
                }
            }
            .padding(.bottom, 20)

            Text(title)
                .font(Brand.title())
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Brand.ink2)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Brand.canvas.ignoresSafeArea())
    }
}

struct IconRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.teal))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Brand.ink)
                Text(detail).font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
    }
}

struct Avatar: View {
    var name: String
    var color: Color = Brand.teal
    var size: CGFloat = 40

    var initial: String {
        let last = name.split(separator: " ").last.map(String.init) ?? name
        return last.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }
}

/// Stable color per person so the same caregiver always looks the same.
func personColor(_ id: String) -> Color {
    let palette: [Color] = [Color(hex: 0x1E6E9E), Color(hex: 0x6347A8), Color(hex: 0xB8562B), Color(hex: 0x2E7D4F)]
    let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
}

struct Banner: View {
    var symbol: String
    var title: String
    var detail: String
    var tint: Color = Brand.amber
    var soft: Color = Brand.amberSoft
    var ink: Color = Brand.amberInk
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(ink)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(detail).font(.footnote).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
            if let action, let onAction {
                Button(action, action: onAction).buttonStyle(PillButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(soft))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.35)))
    }
}

struct RiskBadge: View {
    var risk: Risk
    @Environment(\.lang) private var lang

    var body: some View {
        Label(risk.label(lang), systemImage: risk.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(risk.tint)
    }
}

/// Six-box code display used by the parent's invite and the caregiver's code entry.
struct CodeBoxes: View {
    var code: String
    var active: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let chars = Array(code)
                Text(index < chars.count ? String(chars[index]) : "")
                    .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(active && index == chars.count ? Brand.teal : Brand.hairline, lineWidth: active && index == chars.count ? 2 : 1)
                    )
                if index == 2 { Spacer().frame(width: 4) }
            }
        }
    }
}

struct ErrorLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Brand.red)
    }
}
