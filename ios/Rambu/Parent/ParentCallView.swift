import SwiftUI

/// What the parent sees about the call happening right now (or one that just ended):
/// listening, a warning, or the caregiver's verdict. Renders nothing when there is no current call.
struct ParentCallSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    /// How long a finished call stays on Home before the Latest call card takes over.
    static let recentWindow: TimeInterval = 10 * 60

    var body: some View {
        Group {
            if let alert = currentAlert {
                if let decision = alert.decision {
                    VerdictCard(alert: alert, decision: decision)
                } else {
                    WarningCard(alert: alert)
                }
            } else if let call = model.family?.activeCall {
                ListeningCard(call: call)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentAlert)
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                await model.refreshAlerts()
                SpeechService.shared.announceParentUpdates(model)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The alert for the active call, or the newest alert if it is still going or just happened.
    private var currentAlert: FamilyAlert? {
        if let id = model.family?.activeCall?.alertId, let alert = model.alerts.first(where: { $0.id == id }) {
            return alert
        }
        guard let newest = model.alerts.first else { return nil }
        if !newest.callEnded { return newest }
        let lastEvent = newest.decision?.at ?? newest.raisedAt
        return Date.now.timeIntervalSince(lastEvent) < Self.recentWindow ? newest : nil
    }
}

// MARK: - Listening

private struct ListeningCard: View {
    var call: ActiveCall
    @Environment(\.lang) private var lang

    var body: some View {
        HStack(spacing: 14) {
            Image("mascot-calm").resizable().scaledToFit().frame(width: 56, height: 68).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(lang.t("Rambu is listening", "Rambu sedang mendengarkan"), systemImage: "waveform")
                    .font(.headline).foregroundStyle(Brand.teal)
                Text(lang.t("Keep the speaker on. We will warn you if something sounds wrong.",
                            "Tetap nyalakan speaker. Kami akan memberi tahu jika ada yang mencurigakan."))
                    .font(.subheadline).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(call.startedAt, style: .timer)
                .font(.subheadline.monospacedDigit()).foregroundStyle(Brand.ink3)
                .frame(maxWidth: 56, alignment: .trailing)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.tealSoft))
    }
}

// MARK: - Warning

private struct WarningCard: View {
    var alert: FamilyAlert
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: alert.level.symbol)
                Text(alert.level.label(lang))
                Spacer()
                if alert.callEnded {
                    Text(lang.t("Call ended", "Panggilan selesai")).font(.subheadline.weight(.semibold))
                }
            }
            .font(.title3.weight(.bold))
            .foregroundStyle(alert.headerInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(alert.level.tint)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(alert.parentHeadline(lang))
                        .font(Brand.title(.title))
                        .foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(alert.level.mascot).resizable().scaledToFit().frame(width: 80, height: 96).accessibilityHidden(true)
                }
                Text(lang.t("Do not share any codes or send money. Wait for your family.",
                            "Jangan berikan kode apa pun atau kirim uang. Tunggu keluarga Anda."))
                    .font(.title3)
                    .foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !alert.recipients.isEmpty {
                    let names = alert.recipients.map(\.name).joined(separator: ", ")
                    HStack(spacing: 10) {
                        HStack(spacing: -8) {
                            ForEach(alert.recipients, id: \.id) { Avatar(name: $0.name, color: personColor($0.id), size: 28) }
                        }
                        Text(lang.t("Sent to \(names)", "Dikirim ke \(names)"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.8)))
                }
            }
            .padding(18)
            .background(alert.level.soft)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: alert.level.tint.opacity(0.2), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Verdict

private struct VerdictCard: View {
    var alert: FamilyAlert
    var decision: Decision
    @Environment(\.lang) private var lang

    var body: some View {
        let scam = decision.isScam
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(scam ? lang.t("Scam", "Penipuan") : lang.t("Safe", "Aman"),
                          systemImage: scam ? "hand.raised.fill" : "checkmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(scam ? .white : Brand.green)
                    Text(scam
                         ? lang.t("\(decision.byName) says this is a scam.", "\(decision.byName) bilang ini penipuan.")
                         : lang.t("\(decision.byName) checked: this looks safe.", "\(decision.byName) sudah mengecek: ini terlihat aman."))
                        .font(Brand.title(.largeTitle))
                        .foregroundStyle(scam ? .white : Brand.greenInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(scam ? "mascot-stop-danger" : "mascot-happy-safe")
                    .resizable().scaledToFit().frame(width: 84, height: 100).accessibilityHidden(true)
            }
            if scam {
                Label(lang.t("Hang up and call the number on the back of your card.",
                             "Tutup teleponnya, lalu hubungi nomor di balik kartu Anda."),
                      systemImage: "phone.down.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Brand.red)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
            }
            if alert.callEnded {
                Text(lang.t("Call ended", "Panggilan selesai"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scam ? .white.opacity(0.85) : Brand.ink3)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(scam ? Brand.red : Brand.greenSoft))
        .shadow(color: (scam ? Brand.red : Brand.green).opacity(0.22), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }
}
