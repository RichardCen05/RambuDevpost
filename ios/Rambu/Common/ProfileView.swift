import SwiftUI

/// The avatar at the top right of each tab; opens Profile.
struct ProfileButton: View {
    var size: CGFloat = 36
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            Avatar(name: model.settings.name, color: Brand.teal, size: size)
        }
        .accessibilityLabel(lang.t("Profile", "Profil"))
        .sheet(isPresented: $showProfile) { ProfileView() }
    }
}

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var notifications: NotificationAccess = .unknown
    @State private var showInvite = false
    @State private var showServer = false
    @State private var confirmReset = false

    private var isParent: Bool { model.role == .parent }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Avatar(name: model.settings.name, color: Brand.teal, size: 84)
                        Text(model.settings.name.isEmpty ? " " : model.settings.name)
                            .font(Brand.title(.title2)).foregroundStyle(Brand.ink)
                        Text(isParent ? lang.t("Protected parent", "Orang tua yang dilindungi") : lang.t("Caregiver", "Pengawas"))
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section(lang.t("Family", "Keluarga")) {
                    let members = model.family?.members ?? []
                    if members.isEmpty {
                        Text(lang.t("Not connected", "Belum terhubung")).foregroundStyle(Brand.ink3)
                    }
                    ForEach(members) { member in
                        HStack(spacing: 12) {
                            Avatar(name: member.name, color: member.role == .parent ? Brand.teal : personColor(member.id), size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.id == model.family?.me.id ? lang.t("\(member.name) (you)", "\(member.name) (Anda)") : member.name)
                                    .foregroundStyle(Brand.ink)
                                Text(subtitle(member)).font(.footnote).foregroundStyle(Brand.ink3)
                            }
                        }
                    }
                    if isParent {
                        Button {
                            showInvite = true
                        } label: {
                            Label(lang.t("Invite a caregiver", "Undang pengawas"), systemImage: "person.badge.plus")
                        }
                    }
                }

                Section(lang.t("Alerts", "Peringatan")) {
                    HStack {
                        Label(lang.t("Notifications", "Notifikasi"), systemImage: "bell.badge.fill")
                        Spacer()
                        switch notifications {
                        case .on:
                            Text(lang.t("On", "Nyala")).foregroundStyle(Brand.teal)
                        case .off, .notAsked:
                            Button(lang.t("Turn on", "Nyalakan")) {
                                Task { notifications = await NotificationAccess.turnOn() }
                            }
                            .buttonStyle(PillButtonStyle())
                        case .unknown:
                            EmptyView()
                        }
                    }
                    Toggle(isOn: $model.settings.readAloud) {
                        Label(lang.t("Read alerts aloud", "Bacakan peringatan"), systemImage: "speaker.wave.2.fill")
                    }
                }

                Section(lang.t("Language", "Bahasa")) {
                    Picker(lang.t("App language", "Bahasa aplikasi"),
                           selection: Binding(get: { model.settings.language }, set: { model.setLanguage($0) })) {
                        ForEach(Lang.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }

                Section(lang.t("Name", "Nama")) {
                    TextField(lang.t("Your name", "Nama Anda"), text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                }

                if !isParent {
                    Section(lang.t("Relationship", "Hubungan")) {
                        Picker(lang.t("I am their", "Saya adalah"),
                               selection: Binding(get: { model.settings.relationship }, set: { model.setRelationship($0) })) {
                            ForEach(Relationship.allCases, id: \.self) { Text($0.label(lang)).tag($0) }
                        }
                    }
                }

                Section {
                    Button { showServer = true } label: {
                        HStack {
                            Text(lang.t("Server address", "Alamat server")).foregroundStyle(Brand.ink)
                            Spacer()
                            Text(URL(string: model.settings.serverURL)?.host ?? model.settings.serverURL)
                                .foregroundStyle(Brand.ink3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section {
                    Button(lang.t("Start over on this phone", "Mulai ulang di HP ini"), role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text(lang.t("This phone forgets its role and family. Call history stays on the server.",
                                "HP ini melupakan peran dan keluarganya. Riwayat panggilan tetap di server."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(lang.t("Profile", "Profil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("Done", "Selesai")) {
                        saveName()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(lang.t("Start over on this phone?", "Mulai ulang di HP ini?"),
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(lang.t("Start over", "Mulai ulang"), role: .destructive) {
                    dismiss()
                    model.resetLocal()
                }
                Button(lang.t("Cancel", "Batal"), role: .cancel) {}
            } message: {
                Text(lang.t("You will need to set up Rambu again.", "Anda perlu mengatur Rambu lagi."))
            }
            .sheet(isPresented: $showServer) { ServerSheet() }
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
        .onAppear { name = model.settings.name }
        .task {
            notifications = await NotificationAccess.current()
            await model.refreshFamily()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { notifications = await NotificationAccess.current() } }
        }
    }

    private func subtitle(_ member: Member) -> String {
        if member.isPending { return lang.t("Waiting for approval", "Menunggu persetujuan") }
        if member.role == .parent { return lang.t("Protected parent", "Orang tua yang dilindungi") }
        return member.relation?.label(lang) ?? lang.t("Caregiver", "Pengawas")
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != model.settings.name else { return }
        model.setName(trimmed)
    }
}
