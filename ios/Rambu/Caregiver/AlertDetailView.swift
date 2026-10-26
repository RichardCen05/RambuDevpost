import SwiftUI

/// Caregiver's view of one warning: what Rambu heard, who was told, and the Safe / Scam decision.
struct AlertDetailView: View {
    var alertId: String
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSafe = false
    @State private var submitting = false

    private var alert: FamilyAlert? { model.alerts.first { $0.id == alertId } }

    var body: some View {
        Group {
            if let alert {
                content(alert)
            } else {
                VStack(spacing: 16) {
                    closeButton(ink: Brand.teal).frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    ProgressView()
                    Text(lang.t("Loading alert…", "Memuat peringatan…")).foregroundStyle(Brand.ink2)
                    Spacer()
                }
                .padding(20)
            }
        }
        .background(Brand.canvas.ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                await model.refreshAlerts()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Content

    private func content(_ alert: FamilyAlert) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(alert)
                if let decision = alert.decision { decisionBanner(alert, decision) }
                evidence(alert)
                recipients(alert)
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { buttons(alert) }
        .confirmationDialog(
            lang.t("Mark this call as safe?", "Tandai panggilan ini aman?"),
            isPresented: $confirmSafe,
            titleVisibility: .visible
        ) {
            Button(lang.t("Yes, it's safe", "Ya, aman")) { submit(alert, scam: false) }
            Button(lang.t("Cancel", "Batal"), role: .cancel) {}
        } message: {
            Text(lang.t("\(alert.parentName) will be told the call looks safe.",
                        "\(alert.parentName) akan diberi tahu bahwa panggilan ini terlihat aman."))
        }
    }

    private func header(_ alert: FamilyAlert) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                closeButton(ink: alert.headerInk)
                Image(systemName: alert.level.symbol)
                Text(alert.level.label(lang))
                Spacer()
                if alert.callEnded {
                    Text(lang.t("Call ended", "Panggilan selesai"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(alert.headerInk.opacity(0.18)))
                } else {
                    Label(lang.t("Call in progress", "Panggilan berlangsung"), systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .font(.headline)
            .foregroundStyle(alert.headerInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(alert.level.tint)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.caregiverTitle(lang))
                        .font(Brand.title(.title))
                        .foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "phone.arrow.down.left.fill")
                        Text(lang.t("Phone call", "Panggilan telepon"))
                        Text("·")
                        Text(alert.raisedAt, format: .dateTime.hour().minute())
                    }
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
                Image(alert.level.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 100)
                    .accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alert.level.soft)
        }
    }

    private func decisionBanner(_ alert: FamilyAlert, _ decision: Decision) -> some View {
        let mine = decision.byId == model.family?.me.id
        let tint = decision.isScam ? Brand.red : Brand.green
        return HStack(spacing: 12) {
            Image(systemName: mine ? "checkmark.circle.fill" : "lock.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.decisionLine(lang) ?? "").font(.headline).foregroundStyle(Brand.ink)
                Text(mine
                     ? lang.t("\(alert.parentName) has been told.", "\(alert.parentName) sudah diberi tahu.")
                     : lang.t("Only one answer is needed.", "Cukup satu jawaban."))
                    .font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
            Text(decision.at, format: .dateTime.hour().minute()).font(.footnote).foregroundStyle(Brand.ink3)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(decision.isScam ? Brand.redSoft : Brand.greenSoft))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func evidence(_ alert: FamilyAlert) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("What the caller said", "Yang dikatakan penelepon"))
                .font(.headline).foregroundStyle(Brand.ink)
            if alert.evidence.isEmpty {
                ForEach(alert.signals, id: \.self) { signal in
                    Card {
                        Label(signal.title(lang), systemImage: signal.symbol)
                            .font(.body.weight(.semibold)).foregroundStyle(Brand.ink)
                    }
                }
            } else {
                ForEach(alert.evidence, id: \.self) { item in
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.quote)
                                .font(.title3)
                                .foregroundStyle(Brand.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(lang.t("Flagged by Rambu: ", "Ditandai Rambu: ")
                                 + item.signals.map { $0.title(lang) }.joined(separator: ", "))
                                .font(.footnote)
                                .foregroundStyle(Brand.ink3)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func recipients(_ alert: FamilyAlert) -> some View {
        if !alert.recipients.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.t("Sent to", "Dikirim ke")).font(.headline).foregroundStyle(Brand.ink)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(alert.recipients.enumerated()), id: \.offset) { index, person in
                            if index > 0 { Divider().padding(.leading, 64) }
                            HStack(spacing: 12) {
                                Avatar(name: person.name, color: personColor(person.id), size: 36)
                                Text(person.id == model.family?.me.id ? lang.t("\(person.name) (you)", "\(person.name) (Anda)") : person.name)
                                    .font(.body.weight(.medium)).foregroundStyle(Brand.ink)
                                Spacer()
                                if alert.decision?.byId == person.id {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.teal)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func buttons(_ alert: FamilyAlert) -> some View {
        let locked = alert.decision != nil || submitting
        return HStack(spacing: 12) {
            Button { confirmSafe = true } label: {
                Label(lang.t("Safe", "Aman"), systemImage: "checkmark")
            }
            .buttonStyle(SecondaryButtonStyle())
            Button { submit(alert, scam: true) } label: {
                Label(lang.t("Scam", "Penipuan"), systemImage: "hand.raised.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Brand.red))
        }
        .disabled(locked)
        .opacity(alert.decision != nil ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Brand.canvas.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private func closeButton(ink: Color) -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ink.opacity(0.18)))
        }
        .accessibilityLabel(lang.t("Close", "Tutup"))
    }

    private func submit(_ alert: FamilyAlert, scam: Bool) {
        guard !submitting else { return }
        submitting = true
        Task {
            _ = await model.decide(alert, scam: scam)
            submitting = false
        }
    }
}
