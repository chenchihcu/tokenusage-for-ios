import SwiftUI
import WidgetKit

/// Everything the extension shows: Home Screen and Lock Screen widgets, the reset countdown
/// Live Activity and the Control Center control (spec-competitive-gap-v3.1.md).
@main
struct OpenTokenUsageWidgets: WidgetBundle {
    var body: some Widget {
        QuotaWidget()
        LockQuotaWidget()
        ResetCountdownLiveActivity()
        ResetCountdownControl()
    }
}
