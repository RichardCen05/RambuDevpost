import SwiftUI

struct CaregiverHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeader(name: model.settings.name)

                HStack(spacing: 12) {
                    Image(systemName: "bell").font(.title3).foregroundStyle(Brand.teal)
                    Text(lang.t("No new alerts", "Tidak ada peringatan baru")).font(.headline).foregroundStyle(Brand.ink)
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.tealSoft))

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
                                    Text(lang.t("No active call", "Tidak ada panggilan aktif"))
                                        .font(.subheadline).foregroundStyle(Brand.ink3)
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
        .refreshable { await model.refreshFamily() }
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
