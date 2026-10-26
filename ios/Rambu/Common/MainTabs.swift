import SwiftUI

enum Tab: Hashable { case home, history, puck }

struct MainTabs: View {
    var role: Role
    @Environment(\.lang) private var lang
    @State private var tab: Tab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    if role == .parent { ParentHomeView() } else { CaregiverHomeView() }
                case .history:
                    HistoryView()
                case .puck:
                    PuckTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(tab: $tab, tabs: role == .parent ? [.home, .history, .puck] : [.home, .history])
                .padding(.bottom, 8)
        }
        .background(Brand.canvas.ignoresSafeArea())
    }
}

struct TabBar: View {
    @Binding var tab: Tab
    var tabs: [Tab]
    @Environment(\.lang) private var lang

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol(item)).font(.system(size: 19, weight: .semibold))
                        Text(title(item)).font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(tab == item ? Brand.teal : Brand.ink2)
                    .frame(width: 72, height: 52)
                    .background(Capsule().fill(tab == item ? Brand.tealSoft : .clear))
                }
            }
        }
        .padding(5)
        .background(Capsule().fill(.white))
        .shadow(color: Brand.ink.opacity(0.1), radius: 16, y: 6)
    }

    private func symbol(_ item: Tab) -> String {
        switch item {
        case .home: "house.fill"
        case .history: "clock.fill"
        case .puck: "circle.circle.fill"
        }
    }

    private func title(_ item: Tab) -> String {
        switch item {
        case .home: lang.t("Home", "Beranda")
        case .history: lang.t("History", "Riwayat")
        case .puck: "Puck"
        }
    }
}

struct PlaceholderScreen: View {
    var title: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(Brand.title()).foregroundStyle(Brand.ink)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// Large greeting with the profile avatar at the top right.
struct HomeHeader: View {
    var name: String
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                ProfileButton()
            }
            Text(lang.t("Hi, \(name)", "Halo, \(name)"))
                .font(Brand.title())
                .foregroundStyle(Brand.ink)
        }
    }
}
