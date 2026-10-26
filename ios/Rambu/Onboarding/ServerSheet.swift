import SwiftUI

/// Prototype setting: the backend runs behind a Cloudflare quick tunnel whose address changes on restart.
struct ServerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var state: CheckState = .idle

    enum CheckState: Equatable { case idle, checking, ok, failed }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://….trycloudflare.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(lang.t("Server address", "Alamat server"))
                } footer: {
                    Text(lang.t(
                        "Both phones must use the same address. The parent's phone also sends it to the puck.",
                        "Kedua HP harus memakai alamat yang sama. HP orang tua juga mengirimkannya ke puck."
                    ))
                }
                Section {
                    Button(lang.t("Test connection", "Tes koneksi")) { Task { await check() } }
                    switch state {
                    case .checking: ProgressView()
                    case .ok: Label(lang.t("Connected", "Terhubung"), systemImage: "checkmark.circle.fill").foregroundStyle(Brand.green)
                    case .failed: Label(lang.t("Can't reach the server", "Server tidak terjangkau"), systemImage: "xmark.octagon.fill").foregroundStyle(Brand.red)
                    case .idle: EmptyView()
                    }
                }
            }
            .navigationTitle(lang.t("Server", "Server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.t("Cancel", "Batal")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("Save", "Simpan")) {
                        model.settings.serverURL = normalized
                        NotificationCenter.default.post(name: .rambuServerChanged, object: nil)
                        dismiss()
                    }
                    .disabled(URL(string: normalized)?.host == nil)
                }
            }
            .onAppear { address = model.settings.serverURL }
        }
    }

    private var normalized: String {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.isEmpty, !value.contains("://") { value = "https://" + value }
        return value
    }

    private func check() async {
        state = .checking
        guard let url = URL(string: normalized) else { state = .failed; return }
        state = await APIClient(baseURL: url, token: nil).health() ? .ok : .failed
    }
}

extension Notification.Name {
    static let rambuServerChanged = Notification.Name("rambuServerChanged")
}
