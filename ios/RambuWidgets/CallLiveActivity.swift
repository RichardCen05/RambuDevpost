import ActivityKit
import SwiftUI
import WidgetKit

/// The phone screen belongs to the call, so this is where the parent sees Rambu while talking.
struct RambuCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RambuCallAttributes.self) { context in
            LockScreenCallView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(context.state.isListening ? Color.white.opacity(0.94) : context.state.risk.soft)
                .activitySystemActionForegroundColor(Brand.teal)
        } dynamicIsland: { context in
            let state = context.state
            let accent = state.isListening ? Brand.tealBright : state.risk.tint
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(state.mascot + (state.isListening ? "-dark" : "-dark"))
                        .resizable().scaledToFit().frame(width: 48, height: 58)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startDate, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: 56, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.headline).foregroundStyle(accent)
                        Text(state.headline).font(.subheadline).foregroundStyle(.white).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: state.isListening ? "ear.fill" : state.risk.symbolName)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(state.title).font(.caption2.weight(.semibold)).foregroundStyle(accent)
            } minimal: {
                Image(systemName: state.isListening ? "ear.fill" : state.risk.symbolName)
                    .foregroundStyle(accent)
            }
        }
    }
}

struct LockScreenCallView: View {
    var attributes: RambuCallAttributes
    var state: RambuCallAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(state.mascot).resizable().scaledToFit().frame(width: 58, height: 70)
            VStack(alignment: .leading, spacing: 3) {
                Label(state.title, systemImage: state.isListening ? "ear.fill" : state.risk.symbolName)
                    .font(.headline)
                    .foregroundStyle(state.isListening ? Brand.teal : state.risk.tint)
                Text(state.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(3)
                Text(attributes.parentName)
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink3)
            }
            Spacer(minLength: 0)
            Text(attributes.startDate, style: .timer)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Brand.ink3)
                .frame(maxWidth: 52, alignment: .trailing)
        }
        .padding(16)
    }
}

extension Risk {
    var symbolName: String {
        switch self {
        case .low: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .highRisk: "exclamationmark.octagon.fill"
        }
    }
}
