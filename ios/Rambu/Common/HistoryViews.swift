import SwiftUI

// MARK: - Formatting

/// Times and durations as History shows them: "Today, 14:03", "1 min 2 sec".
enum CallFormat {
    static func when(_ date: Date, lang: Lang, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = lang.locale
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        let clock = time.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return lang.t("Today, \(clock)", "Hari ini, \(clock)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return lang.t("Yesterday, \(clock)", "Kemarin, \(clock)")
        }
        let day = DateFormatter()
        day.locale = lang.locale
        day.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        day.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
        return "\(day.string(from: date)), \(clock)"
    }

    static func duration(_ seconds: Int?, lang: Lang) -> String {
        guard let seconds, seconds >= 0 else { return "" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes == 0 { return lang.t("\(rest) sec", "\(rest) dtk") }
        if rest == 0 { return lang.t("\(minutes) min", "\(minutes) mnt") }
        return lang.t("\(minutes) min \(rest) sec", "\(minutes) mnt \(rest) dtk")
    }
}

extension CallRecord {
    var isListening: Bool { status == "listening" }

    func title(_ lang: Lang) -> String {
        if isListening { return lang.t("Call in progress", "Panggilan sedang berlangsung") }
        if couldNotAssess { return lang.t("Call not checked", "Panggilan tidak diperiksa") }
        if let first = Signal.strongest(signals) { return first.title(lang) }
        return lang.t("Phone call", "Panggilan telepon")
    }

    var mascot: String { couldNotAssess ? "mascot-rest" : level.mascot }
}

// MARK: - Shared pieces

/// Safe / Worth a look / Danger, or grey "Could not assess".
struct ResultBadge: View {
    var record: CallRecord
    @Environment(\.lang) private var lang

    var body: some View {
        if record.couldNotAssess {
            Label(lang.t("Could not assess", "Tidak bisa dinilai"), systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink3)
        } else if record.isListening {
            Label(lang.t("Listening", "Mendengarkan"), systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.teal)
        } else {
            RiskBadge(risk: record.level)
        }
    }
}

/// "Dimas marked this call as scam" (red) or "... as safe" (green).
struct DecisionStrip: View {
    var decision: Decision
    @Environment(\.lang) private var lang

    var body: some View {
        let name = decision.byName
        HStack(spacing: 8) {
            Image(systemName: decision.isScam ? "hand.raised.fill" : "checkmark.shield.fill")
            Text(decision.isScam
                 ? lang.t("\(name) marked this call as scam", "\(name) menandai panggilan ini sebagai penipuan")
                 : lang.t("\(name) marked this call as safe", "\(name) menandai panggilan ini aman"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(decision.isScam ? Brand.redInk : Brand.greenInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(decision.isScam ? Brand.redSoft : Brand.greenSoft)
    }
}

/// One call in History (also the "Latest call" card on parent Home).
struct CallCard: View {
    var record: CallRecord
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.title(lang))
                        .font(.headline)
                        .foregroundStyle(Brand.ink)
                        .multilineTextAlignment(.leading)
                    ResultBadge(record: record)
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                        Text(meta)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Brand.ink3).padding(.top, 2)
            }
            .padding(16)
            if let decision = record.decision { DecisionStrip(decision: decision) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Brand.ink.opacity(0.05), radius: 12, y: 4)
    }

    private var meta: String {
        let when = CallFormat.when(record.startedAt, lang: lang)
        let length = CallFormat.duration(record.durationSeconds, lang: lang)
        return length.isEmpty ? when : "\(when) · \(length)"
    }
}

/// Navigation value for opening one call's detail.
struct CallRoute: Hashable {
    let id: String
}

// MARK: - History tab

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Spacer()
                        ProfileButton()
                    }
                    Text(lang.t("History", "Riwayat"))
                        .font(Brand.title())
                        .foregroundStyle(Brand.ink)

                    if model.history.isEmpty {
                        VStack(spacing: 12) {
                            Image("mascot-rest").resizable().scaledToFit().frame(height: 150)
                            Text(lang.t("No calls yet", "Belum ada panggilan"))
                                .font(.headline).foregroundStyle(Brand.ink)
                            Text(lang.t("Calls Rambu listens to show up here.", "Panggilan yang didengar Rambu muncul di sini."))
                                .font(.subheadline).foregroundStyle(Brand.ink2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(model.history) { record in
                            NavigationLink(value: CallRoute(id: record.id)) {
                                CallCard(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refreshHistory() }
            .task { await model.refreshHistory() }
            .navigationDestination(for: CallRoute.self) { CallDetailView(id: $0.id) }
        }
    }
}

// MARK: - Call detail

struct CallDetailView: View {
    var id: String
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var detail: CallRecord?
    @State private var loaded = false

    private var record: CallRecord? { detail ?? model.history.first { $0.id == id } }

    var body: some View {
        ScrollView {
            if let record {
                content(record)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
            } else if loaded {
                Text(lang.t("This call couldn't be loaded.", "Panggilan ini tidak bisa dimuat."))
                    .foregroundStyle(Brand.ink2)
                    .padding(40)
            } else {
                ProgressView().padding(60)
            }
        }
        .background(Brand.canvas.ignoresSafeArea())
        .navigationTitle(lang.t("Call", "Panggilan"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await model.callDetail(id)
            loaded = true
        }
    }

    @ViewBuilder
    private func content(_ record: CallRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(record)

            if record.couldNotAssess {
                Banner(
                    symbol: "exclamationmark.triangle.fill",
                    title: lang.t("Analysis was unsuccessful — this call wasn't confirmed safe.",
                                  "Analisis tidak berhasil — panggilan ini belum dipastikan aman."),
                    detail: record.status == "no_speech"
                        ? lang.t("No speech the puck could analyze.", "Tidak ada suara yang bisa dianalisis puck.")
                        : lang.t("The Rambu server could not finish the check.", "Server Rambu tidak bisa menyelesaikan pemeriksaan."),
                    tint: Brand.hairline, soft: .white, ink: Brand.ink2
                )
            }

            if let decision = record.decision {
                DecisionStrip(decision: decision)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !record.signals.isEmpty {
                sectionTitle(lang.t("Signals found", "Tanda yang ditemukan"))
                Card(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(record.signals, id: \.self) { signal in
                            HStack(spacing: 12) {
                                Image(systemName: signal.symbol)
                                    .foregroundStyle(record.level.ink)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(record.level.soft))
                                Text(signal.title(lang)).font(.body.weight(.medium)).foregroundStyle(Brand.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                        }
                    }
                }
            }

            if !record.evidence.isEmpty {
                sectionTitle(lang.t("What the caller said", "Yang dikatakan penelepon"))
                ForEach(record.evidence, id: \.self) { item in
                    QuoteCard(evidence: item, tint: record.level.tint)
                }
            }

            if model.role == .parent, let transcript = record.transcript, !transcript.isEmpty {
                sectionTitle(lang.t("Full transcript (masked)", "Transkrip lengkap (disamarkan)"))
                Card {
                    Text(transcript)
                        .font(.callout)
                        .foregroundStyle(Brand.ink2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func header(_ record: CallRecord) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(record.mascot).resizable().scaledToFit().frame(width: 64, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    ResultBadge(record: record).font(.title3)
                    Text(CallFormat.when(record.startedAt, lang: lang))
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                    let length = CallFormat.duration(record.durationSeconds, lang: lang)
                    if !length.isEmpty {
                        Label(lang.t("Duration \(length)", "Durasi \(length)"), systemImage: "clock")
                            .font(.subheadline).foregroundStyle(Brand.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(Brand.ink).padding(.top, 4)
    }
}

/// One flagged sentence with the signals it shows.
struct QuoteCard: View {
    var evidence: Evidence
    var tint: Color = Brand.red
    @Environment(\.lang) private var lang

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(evidence.quote)”")
                    .font(.body.italic())
                    .foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(evidence.signals, id: \.self) { signal in
                    Label(signal.title(lang), systemImage: signal.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
    }
}
