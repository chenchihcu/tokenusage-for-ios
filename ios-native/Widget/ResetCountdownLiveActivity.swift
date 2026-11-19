import ActivityKit
import SwiftUI
import WidgetKit

/// 「重置倒數」 on the Lock Screen and in the Dynamic Island (FR-16, FR-17, FR-20).
struct ResetCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ResetCountdownAttributes.self) { context in
            ResetCountdownLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding()
                .activityBackgroundTint(nil)
                .widgetURL(URL(string: "opentokenusage://quotas"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ProviderBadge(id: context.attributes.providerId, name: context.attributes.providerName, base: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.providerName).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(context.attributes.windowLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("剩 \(Int(context.state.remaining.rounded()))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(QuotaLevel(remaining: context.state.remaining).textTint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Countdown(reset: context.state.resetDate, isStale: context.isStale)
                            .font(.title3.monospacedDigit().weight(.semibold))
                        Spacer()
                        Text("資料 \(context.state.dataDate, format: .dateTime.hour().minute())")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                ProviderBadge(id: context.attributes.providerId, name: context.attributes.providerName, base: 18)
            } compactTrailing: {
                Countdown(reset: context.state.resetDate, isStale: context.isStale)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 56)
            } minimal: {
                ProviderBadge(id: context.attributes.providerId, name: context.attributes.providerName, base: 18)
            }
            .widgetURL(URL(string: "opentokenusage://quotas"))
        }
    }
}

/// System-drawn countdown, exact without app updates (FR-16); 「已重置」 once it has passed.
struct Countdown: View {
    let reset: Date?
    let isStale: Bool

    var body: some View {
        if let reset, reset > Date(), !isStale {
            Text(timerInterval: Date()...reset, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(reset == nil ? "—" : "已重置")
        }
    }
}

struct ResetCountdownLockView: View {
    let attributes: ResetCountdownAttributes
    let state: ResetCountdownAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderBadge(id: attributes.providerId, name: attributes.providerName, base: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.providerName).font(.headline).lineLimit(1)
                Text(attributes.windowLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("剩 \(Int(state.remaining.rounded()))% · 資料 \(state.dataDate, format: .dateTime.hour().minute())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(isPast ? "" : "重置倒數").font(.caption2).foregroundStyle(.secondary)
                Countdown(reset: state.resetDate, isStale: isStale)
                    .font(.title2.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var isPast: Bool { isStale || (state.resetDate.map { $0 <= Date() } ?? true) }

    private var spoken: String {
        var text = "\(attributes.providerName) \(attributes.windowLabel)，剩餘 \(Int(state.remaining.rounded()))%"
        if isPast {
            text += "，已重置"
        } else if let reset = state.resetDate {
            text += "，\(PaceEstimate.span(reset.timeIntervalSinceNow))後重置"
        }
        return text
    }
}
