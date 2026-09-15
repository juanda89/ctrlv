import ControlVCore
import Foundation

@MainActor
@Observable
final class FeedbackViewModel {
    var rating: Int?
    var category: FeedbackCategory = .idea
    var message: String = ""
    var contactEmail: String

    private(set) var isSending = false
    private(set) var didSend = false
    private(set) var lastError: String?

    private let client: FeedbackClientProtocol
    private let tracker: FeedbackPromptTracker
    private let installID: String
    private let sessionToken: String?
    private let appVersion: String

    init(
        client: FeedbackClientProtocol,
        tracker: FeedbackPromptTracker,
        installID: String,
        sessionToken: String?,
        contactEmail: String?,
        appVersion: String,
        initialRating: Int? = nil
    ) {
        self.client = client
        self.tracker = tracker
        self.installID = installID
        self.sessionToken = sessionToken
        self.contactEmail = contactEmail ?? ""
        self.appVersion = appVersion
        self.rating = initialRating
    }

    /// A rating alone is enough (quick "★★★★★"); otherwise a message is required.
    var canSend: Bool {
        !isSending && (rating != nil || !trimmedMessage.isEmpty)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send() async {
        guard canSend else { return }
        isSending = true
        lastError = nil
        defer { isSending = false }

        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let submission = FeedbackSubmission(
            rating: rating,
            category: category,
            message: trimmedMessage,
            contactEmail: email.contains("@") ? email : nil,
            installID: installID,
            sessionToken: sessionToken,
            appVersion: appVersion
        )

        do {
            try await client.submit(submission)
            tracker.markSubmitted()
            didSend = true
        } catch {
            lastError = error.localizedDescription
        }
    }
}
