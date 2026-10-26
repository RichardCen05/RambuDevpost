import SwiftUI

struct CaregiverHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeader(name: model.settings.name)

                let shown = visibleAlerts
                if shown.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "bell").font(.title3).foregroundStyle(Brand.teal)
                        Text(lang.t("No new alerts", "Tidak ada peringatan baru")).font(.headline).foregroundStyle(Brand.ink)
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.tealSoft))
                } else {
                    ForEach(shown) { alert in
                        Button { model.openAlertId = alert.id } label: { AlertCard(alert: alert) }
                            .buttonStyle(.plain)
                    }
                }

                Text(lang.t("People you protect", "Orang yang Anda lindungi"))
                    .font(.headline)
                    .foregroundStyle(Brand.ink)
                    .padding(.top, 4)

                if let family = model.family, let parent = family.parent {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Avatar(name: parent.name, color: Brand.teal, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(parent.name).font(.headline).foregroundStyle(Brand.ink)
                                    if family.activeCall != nil {
                                        Label(lang.t("Analysis in progress", "Analisis berlangsung"), systemImage: "waveform")
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.teal)
                                            .symbolEffect(.variableColor.iterative, options: .repeating)
                                    } else {
                                        Text(lang.t("No active analysis session", "Tidak ada sesi analisis aktif"))
                                            .font(.subheadline).foregroundStyle(Brand.ink3)
                                    }
                                }
                                Spacer()
                            }
                            .padding(16)
                            let others = family.caregivers.filter { $0.id != family.me.id }
                            if !others.isEmpty {
                                Divider().padding(.leading, 16)
                                HStack(spacing: 12) {
                                    HStack(spacing: -10) {
                                        ForEach([family.me] + others) { Avatar(name: $0.name, color: personColor($0.id), size: 30) }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lang.t("Together with \(others.map(\.name).joined(separator: ", "))",
                                                    "Bersama \(others.map(\.name).joined(separator: ", "))"))
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                                        Text(lang.t("Only one answer is needed", "Cukup satu jawaban"))
                                            .font(.footnote).foregroundStyle(Brand.ink3)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Brand.canvas.ignoresSafeArea())
        .refreshable {
            await model.refreshFamily()
            await model.refreshAlerts()
        }
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                await model.refreshAlerts()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Undecided alerts from the last day, plus ones decided in the last half hour so everyone sees the outcome.
    private var visibleAlerts: [FamilyAlert] {
        let now = Date.now
        return model.alerts.filter { alert in
            if let decision = alert.decision { return now.timeIntervalSince(decision.at) < 30 * 60 }
            return now.timeIntervalSince(alert.raisedAt) < 24 * 60 * 60
        }
    }
}
