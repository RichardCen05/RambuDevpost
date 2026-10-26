import SwiftUI

struct ParentHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var showInvite = false

    var body: some View {
        NavigationStack {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: CallRoute.self) { CallDetailView(id: $0.id) }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeader(name: model.settings.name)

                // ParentCallSection() goes here (Parent/ParentCallView.swift, other branch)
                ParentIssueBanners()

                let family = model.family
                if let pending = family?.pending, !pending.isEmpty {
                    ForEach(pending) { member in
                        Banner(
                            symbol: "person.badge.plus",
                            title: lang.t("\(member.name) wants to join", "\(member.name) ingin bergabung"),
                            detail: member.relation?.label(lang) ?? "",
                            tint: Brand.tealBright, soft: Brand.tealSoft, ink: .white,
                            action: lang.t("Allow", "Izinkan"),
                            onAction: { Task { await model.allow(member) } }
                        )
                    }
                }

                if family?.caregivers.isEmpty ?? true {
                    Button { showInvite = true } label: {
                        Card {
                            HStack(spacing: 14) {
                                Image(systemName: "person.2.badge.plus.fill")
                                    .font(.title3)
                                    .foregroundStyle(Brand.teal)
                                    .frame(width: 48, height: 48)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.tealSoft))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(lang.t("Connect family", "Hubungkan keluarga")).font(.headline).foregroundStyle(Brand.ink)
                                    Text(lang.t("Tap to invite a family member.", "Ketuk untuk mengundang anggota keluarga."))
                                        .font(.subheadline).foregroundStyle(Brand.ink2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Brand.ink3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let caregivers = family?.caregivers {
                    Card {
                        HStack(spacing: 12) {
                            HStack(spacing: -10) {
                                ForEach(caregivers) { Avatar(name: $0.name, color: personColor($0.id), size: 36) }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.t("Protected together with", "Dilindungi bersama"))
                                    .font(.footnote).foregroundStyle(Brand.ink3)
                                Text(caregivers.map(\.name).joined(separator: ", "))
                                    .font(.headline).foregroundStyle(Brand.ink)
                            }
                            Spacer()
                        }
                    }
                }

                Text(lang.t("Latest call", "Panggilan terakhir"))
                    .font(.headline)
                    .foregroundStyle(Brand.ink)
                    .padding(.top, 8)
                if let latest = model.history.first {
                    NavigationLink(value: CallRoute(id: latest.id)) {
                        CallCard(record: latest)
                    }
                    .buttonStyle(.plain)
                } else {
                    Card {
                        HStack(spacing: 14) {
                            Image("mascot-calm").resizable().scaledToFit().frame(width: 56, height: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(lang.t("No calls yet", "Belum ada panggilan")).font(.headline).foregroundStyle(Brand.ink)
                                Text(lang.t("Answer calls on speaker; Rambu listens through the puck.",
                                            "Angkat telepon dengan loudspeaker; Rambu mendengar lewat puck."))
                                    .font(.subheadline).foregroundStyle(Brand.ink2)
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
            await model.refreshHistory()
        }
        .task { await model.refreshHistory() }
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(isPresented: $showInvite) {
            NavigationStack {
                ScrollView { InvitePanel().padding(20) }
                    .background(Brand.canvas)
                    .navigationTitle(lang.t("Invite a caregiver", "Undang pengawas"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button(lang.t("Done", "Selesai")) { showInvite = false } }
            }
            .task { if model.family?.invite == nil { await model.renewInvite() } }
        }
    }
}
