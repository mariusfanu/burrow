import SwiftUI

/// Tells VoiceOver about something that changed away from where it's reading.
@MainActor
enum Announcer {
    static func say(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
