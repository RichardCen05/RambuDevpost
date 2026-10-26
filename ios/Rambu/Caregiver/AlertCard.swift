import SwiftUI

// MARK: - Alert copy and helpers shared by caregiver and parent screens

extension Signal {
    /// How strongly a signal points to a scam; used to pick the evidence line caregivers see first.
    var weight: Int {
        switch self {
        case .secretCode: 5
        case .transfer, .remoteApp: 4
        case .impersonation: 2
        case .urgency: 1
        }
    }
}

extension FamilyAlert {
    /// The flagged caller sentence that says the most about the scam.
    var strongestEvidence: Evidence? {
        evidence.enumerated().max { lhs, rhs in
            let left = lhs.element.signals.map(\.weight).reduce(0, +)
            let right = rhs.element.signals.map(\.weight).reduce(0, +)
            return left == right ? lhs.offset < rhs.offset : left < right
        }?.element
    }

    /// The most recent signal heard on the call.
    var latestSignal: Signal? { Signal.strongest(signals) }

    /// Plain sentence for the parent, e.g. "The caller is asking for a secret code".
    func parentHeadline(_ lang: Lang) -> String {
        latestSignal?.headline(lang) ?? lang.t("This call may be a scam", "Panggilan ini mungkin penipuan")
    }

    func caregiverTitle(_ lang: Lang) -> String {
        lang.t("\(parentName) may be getting scammed", "\(parentName) mungkin sedang ditipu")
    }

    /// The verdict as the parent hears it, nil until a caregiver decided.
    func verdictSentence(_ lang: Lang) -> String? {
        guard let decision else { return nil }
        if decision.isScam {
            return lang.t(
                "\(decision.byName) says this is a scam. Hang up and call the number on the back of your card.",
                "\(decision.byName) bilang ini penipuan. Tutup teleponnya, lalu hubungi nomor di balik kartu Anda."
            )
        }
        return lang.t("\(decision.byName) checked: this looks safe.", "\(decision.byName) sudah mengecek: ini terlihat aman.")
    }

    func decisionLine(_ lang: Lang) -> String? {
        guard let decision else { return nil }
        return decision.isScam
            ? lang.t("Marked as scam by \(decision.byName)", "Ditandai penipuan oleh \(decision.byName)")
            : lang.t("Marked as safe by \(decision.byName)", "Ditandai aman oleh \(decision.byName)")
    }

    /// Text color that reads well on the level's solid color.
    var headerInk: Color { level == .needsReview ? Brand.amberInk : .white }
}

// MARK: - Card on Caregiver Home

/// Compact alert on Caregiver Home: level strip, "{parent} may be getting scammed", the strongest flagged line.
struct AlertCard: View {
    var alert: FamilyAlert
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: alert.level.symbol)
                Text(alert.level.label(lang))
                Spacer()
                if alert.callEnded {
                    Text(lang.t("Call ended", "Panggilan selesai")).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(alert.headerInk.opacity(0.18)))
                }
                Text(alert.raisedAt, format: .dateTime.hour().minute())
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(alert.headerInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(alert.level.tint)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.caregiverTitle(lang))
                        .font(Brand.title(.title3))
                        .foregroundStyle(Brand.ink)
                        .multilineTextAlignment(.leading)
                    if let quote = alert.strongestEvidence?.quote {
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(.subheadline)
                            .foregroundStyle(Brand.ink2)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let line = alert.decisionLine(lang) {
                        Label(line, systemImage: "lock.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(alert.decision?.isScam == true ? Brand.redInk : Brand.greenInk)
                    } else {
                        Label(lang.t("Tap to decide", "Ketuk untuk memutuskan"), systemImage: "hand.tap.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(alert.level.ink)
                    }
                }
                Spacer(minLength: 0)
                Image(alert.level.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 70)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alert.level.soft)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: alert.level.tint.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}
