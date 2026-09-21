import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class CircleDataStore: ObservableObject {
    @Published private(set) var circles: [WamoriCircle] = []
    @Published private(set) var entriesByCircleID: [String: [CircleEntry]] = [:]
    @Published private(set) var membersByCircleID: [String: [CircleMember]] = [:]
    @Published private(set) var commentsByEntryID: [String: [CircleComment]] = [:]
    @Published private(set) var viewerReactionByEntryID: [String: ReactionKind] = [:]
    @Published var pendingRoute: CircleRoute?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var timeZone: TimeZone = .current

    private let functions: CircleFunctionsService
    private var userID: String?
    #if canImport(FirebaseFirestore)
    private var membershipListener: ListenerRegistration?
    private var circleListeners: [String: ListenerRegistration] = [:]
    private var entryListeners: [String: ListenerRegistration] = [:]
    private var memberListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var reactionListeners: [String: ListenerRegistration] = [:]
    #endif

    init(functions: CircleFunctionsService = CircleFunctionsService()) {
        self.functions = functions
    }

    func activate(userID: String?, timeZoneIdentifier: String? = nil) async {
        guard self.userID != userID else { return }
        stopListening()
        self.userID = userID
        circles = []
        entriesByCircleID = [:]
        membersByCircleID = [:]
        commentsByEntryID = [:]
        viewerReactionByEntryID = [:]
        if let identifier = timeZoneIdentifier, let storedZone = TimeZone(identifier: identifier) {
            timeZone = storedZone
        } else {
            timeZone = .current
        }
        guard let userID else { return }
        await registerCurrentTimeZone()
        listenForMemberships(userID: userID)
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        guard let route = CircleInviteRouter().route(for: url) else { return false }
        pendingRoute = route
        return true
    }

    func clearPendingRoute() { pendingRoute = nil }

    func present(_ error: Error) { errorMessage = error.localizedDescription }

    func entries(in circleID: String) -> [CircleEntry] {
        entriesByCircleID[circleID] ?? []
    }

    func members(in circleID: String) -> [CircleMember] {
        membersByCircleID[circleID] ?? []
    }

    func comments(for entryID: String) -> [CircleComment] {
        commentsByEntryID[entryID] ?? []
    }

    func todaysEntry(in circleID: String) -> CircleEntry? {
        let key = todayDateKey
        return entries(in: circleID).first { $0.authorID == userID && $0.dateKey == key && !$0.isDeleted }
    }

    var todayDateKey: String { Self.dateKey(for: Date(), timeZone: timeZone) }

    var dailyPrompt: String { DailyPrompt.text(for: todayDateKey) }

    func createCircle(name: String, emoji: String) async throws -> WamoriCircle {
        let circle = try await perform { try await functions.createCircle(name: name, emoji: emoji) }
        AnalyticsService.shared.capture("circle_created", properties: ["has_emoji": !emoji.isEmpty])
        return circle
    }

    func updateCircle(_ circle: WamoriCircle, name: String, emoji: String) async throws {
        try await perform { try await functions.updateCircle(circleID: circle.id, name: name, emoji: emoji) }
    }

    func previewInvite(token: String) async throws -> CircleInvitePreview {
        try await perform { try await functions.previewInvite(token: token) }
    }

    func joinCircle(token: String) async throws -> WamoriCircle {
        let circle = try await perform { try await functions.joinCircle(token: token) }
        pendingRoute = .circle(id: circle.id)
        AnalyticsService.shared.capture("circle_joined")
        return circle
    }

    func createInvite(circleID: String) async throws -> CreatedCircleInvite {
        let invite = try await perform { try await functions.createInvite(circleID: circleID) }
        AnalyticsService.shared.capture("circle_invite_created")
        return invite
    }

    func listInvites(circleID: String) async throws -> [CircleInviteSummary] {
        try await perform { try await functions.listInvites(circleID: circleID) }
    }

    func revokeInvite(circleID: String, inviteID: String) async throws {
        try await perform { try await functions.revokeInvite(circleID: circleID, inviteID: inviteID) }
    }

    func createEntry(circleID: String, body: String, mediaItems: [CircleMedia], metrics: TypingMetrics, aiAssisted: Bool) async throws {
        _ = try await perform {
            try await functions.createEntry(circleID: circleID, body: body, mediaItems: mediaItems, metrics: metrics, aiAssisted: aiAssisted)
        }
        AnalyticsService.shared.capture("circle_entry_created", properties: ["has_text": !body.isEmpty, "has_image": !mediaItems.isEmpty, "ai_assisted": aiAssisted])
    }

    func updateEntry(_ entry: CircleEntry, body: String, mediaItems: [CircleMedia], metrics: TypingMetrics, aiAssisted: Bool) async throws {
        try await perform {
            try await functions.updateEntry(circleID: entry.circleID, entryID: entry.id, body: body, mediaItems: mediaItems, metrics: metrics, aiAssisted: aiAssisted)
        }
        AnalyticsService.shared.capture("circle_entry_updated", properties: ["has_text": !body.isEmpty, "has_image": !mediaItems.isEmpty])
    }

    func deleteEntry(_ entry: CircleEntry) async throws {
        try await perform { try await functions.deleteEntry(circleID: entry.circleID, entryID: entry.id) }
        AnalyticsService.shared.capture("circle_entry_deleted")
    }

    func setReaction(_ kind: ReactionKind, entry: CircleEntry) async throws {
        try await perform { try await functions.setReaction(circleID: entry.circleID, entryID: entry.id, kind: kind) }
        AnalyticsService.shared.capture("circle_reaction_toggled", properties: ["kind": kind.rawValue])
    }

    func listenToViewerReaction(for entry: CircleEntry) {
        #if canImport(FirebaseFirestore)
        guard FirebaseBootstrap.isConfigured, let userID, reactionListeners[entry.id] == nil else { return }
        reactionListeners[entry.id] = Firestore.firestore().collection("circles").document(entry.circleID)
            .collection("entries").document(entry.id).collection("reactions").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let raw = snapshot?.data()?["kind"] as? String, let kind = ReactionKind(rawValue: raw) {
                        self.viewerReactionByEntryID[entry.id] = kind
                    } else {
                        self.viewerReactionByEntryID[entry.id] = nil
                    }
                }
            }
        #endif
    }

    func stopListeningToViewerReaction(entryID: String) {
        #if canImport(FirebaseFirestore)
        reactionListeners.removeValue(forKey: entryID)?.remove()
        viewerReactionByEntryID[entryID] = nil
        #endif
    }

    func createComment(body: String, entry: CircleEntry) async throws {
        try await perform { try await functions.createComment(circleID: entry.circleID, entryID: entry.id, body: body) }
        AnalyticsService.shared.capture("circle_comment_created")
    }

    func deleteComment(_ comment: CircleComment) async throws {
        try await perform { try await functions.deleteComment(circleID: comment.circleID, entryID: comment.entryID, commentID: comment.id) }
    }

    func transferOwnership(of circle: WamoriCircle, to userID: String) async throws {
        try await perform { try await functions.transferOwnership(circleID: circle.id, userID: userID) }
    }

    func removeMember(from circle: WamoriCircle, userID: String) async throws {
        try await perform { try await functions.removeMember(circleID: circle.id, userID: userID) }
    }

    func leave(_ circle: WamoriCircle) async throws {
        try await perform { try await functions.leaveCircle(circleID: circle.id) }
    }

    func delete(_ circle: WamoriCircle) async throws {
        try await perform { try await functions.deleteCircle(circleID: circle.id) }
    }

    func prepareAccountDeletion() async throws {
        guard functions.isAvailable else { return }
        try await perform { try await functions.prepareAccountDeletion() }
    }

    func listenToComments(for entry: CircleEntry) {
        #if canImport(FirebaseFirestore)
        guard FirebaseBootstrap.isConfigured, commentListeners[entry.id] == nil else { return }
        commentListeners[entry.id] = Firestore.firestore().collection("circles").document(entry.circleID)
            .collection("entries").document(entry.id).collection("comments")
            .whereField("isDeleted", isEqualTo: false).order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription; return }
                    self.commentsByEntryID[entry.id] = snapshot?.documents.compactMap(Self.comment(from:)) ?? []
                }
            }
        #endif
    }

    func stopListeningToComments(entryID: String) {
        #if canImport(FirebaseFirestore)
        commentListeners.removeValue(forKey: entryID)?.remove()
        commentsByEntryID[entryID] = nil
        #endif
    }

    nonisolated static func dateKey(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    #if DEBUG
    func loadScreenshotFixtures() {
        let now = Date()
        let today = Self.dateKey(for: now, timeZone: .current)
        let circle = WamoriCircle(id: "screenshot-family", name: "家族の輪", emoji: "🏠", ownerID: "local-placeholder",
                                  memberCount: 4, maxMembers: 5, status: .active,
                                  createdAt: now.addingTimeInterval(-2_592_000), updatedAt: now)
        circles = [circle, WamoriCircle(id: "screenshot-friends", name: "いつもの3人", emoji: "☕️", ownerID: "aoi",
                                        memberCount: 3, maxMembers: 5, status: .active,
                                        createdAt: now.addingTimeInterval(-1_296_000), updatedAt: now.addingTimeInterval(-900))]
        userID = "local-placeholder"
        timeZone = .current
        membersByCircleID[circle.id] = [
            CircleMember(id: "local-placeholder", userID: "local-placeholder", role: .owner, joinedAt: circle.createdAt, status: .active),
            CircleMember(id: "aoi", userID: "aoi", role: .member, joinedAt: circle.createdAt, status: .active),
            CircleMember(id: "nagi", userID: "nagi", role: .member, joinedAt: circle.createdAt, status: .active),
            CircleMember(id: "ren", userID: "ren", role: .member, joinedAt: circle.createdAt, status: .active)
        ]
        entriesByCircleID[circle.id] = [
            CircleEntry(id: "aoi_\(today)", circleID: circle.id, authorID: "aoi", dateKey: today,
                        body: "今日はみんなで久しぶりに食卓を囲めた。何でもない話をしている時間が、いちばん落ち着く。", mediaItems: [],
                        promptID: "daily-\(today)-ja", promptTextSnapshot: DailyPrompt.text(for: today), humanScore: 94, humanBadge: .verified,
                        aiAssisted: false, inputDurationMs: 82_000, characterCount: 50, editCount: 4, deleteCount: 2,
                        suspiciousBulkInputCount: 0, createdAt: now.addingTimeInterval(-2_700), updatedAt: now.addingTimeInterval(-2_700),
                        isDeleted: false, moderationStatus: .active, commentCount: 2, reactionCounts: ["empathy": 3, "insight": 0, "cheer": 1]),
            CircleEntry(id: "nagi_\(today)", circleID: circle.id, authorID: "nagi", dateKey: today,
                        body: "帰り道の空がきれいでした。明日も無理せず、ひとつずつ。", mediaItems: [],
                        promptID: "daily-\(today)-ja", promptTextSnapshot: DailyPrompt.text(for: today), humanScore: 90, humanBadge: .verified,
                        aiAssisted: false, inputDurationMs: 44_000, characterCount: 31, editCount: 2, deleteCount: 1,
                        suspiciousBulkInputCount: 0, createdAt: now.addingTimeInterval(-1_200), updatedAt: now.addingTimeInterval(-1_200),
                        isDeleted: false, moderationStatus: .active, commentCount: 1, reactionCounts: ["empathy": 2, "insight": 1, "cheer": 2])
        ]
    }
    #endif

    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { return try await operation() }
        catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func registerCurrentTimeZone() async {
        guard functions.isAvailable else { return }
        do {
            try await functions.updateTimeZone(TimeZone.current.identifier)
            timeZone = .current
        } catch {
            // A recently changed server timezone remains authoritative until its cooldown expires.
        }
    }

    private func stopListening() {
        #if canImport(FirebaseFirestore)
        membershipListener?.remove()
        membershipListener = nil
        circleListeners.values.forEach { $0.remove() }
        entryListeners.values.forEach { $0.remove() }
        memberListeners.values.forEach { $0.remove() }
        commentListeners.values.forEach { $0.remove() }
        reactionListeners.values.forEach { $0.remove() }
        circleListeners = [:]
        entryListeners = [:]
        memberListeners = [:]
        commentListeners = [:]
        reactionListeners = [:]
        #endif
    }

    private func listenForMemberships(userID: String) {
        #if canImport(FirebaseFirestore)
        guard FirebaseBootstrap.isConfigured else { return }
        membershipListener = Firestore.firestore().collection("users").document(userID)
            .collection("circleMemberships").whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription; return }
                    let ids = Set(snapshot?.documents.compactMap { document in
                        (document.data()["circleID"] as? String) ?? document.documentID
                    } ?? [])
                    self.reconcileListeners(circleIDs: ids)
                }
            }
        #endif
    }

    private func reconcileListeners(circleIDs: Set<String>) {
        #if canImport(FirebaseFirestore)
        let removed = Set(circleListeners.keys).subtracting(circleIDs)
        for id in removed {
            circleListeners.removeValue(forKey: id)?.remove()
            entryListeners.removeValue(forKey: id)?.remove()
            memberListeners.removeValue(forKey: id)?.remove()
            entriesByCircleID[id] = nil
            membersByCircleID[id] = nil
        }
        circles.removeAll { !circleIDs.contains($0.id) }
        for id in circleIDs where circleListeners[id] == nil { listenToCircle(id) }
        #endif
    }

    #if canImport(FirebaseFirestore)
    private func listenToCircle(_ circleID: String) {
        let reference = Firestore.firestore().collection("circles").document(circleID)
        circleListeners[circleID] = reference.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription; return }
                guard let snapshot, snapshot.exists, let circle = Self.circle(from: snapshot) else { return }
                self.circles.removeAll { $0.id == circleID }
                self.circles.append(circle)
                self.circles.sort { $0.updatedAt > $1.updatedAt }
            }
        }
        entryListeners[circleID] = reference.collection("entries")
            .whereField("isDeleted", isEqualTo: false).order(by: "dateKey", descending: true).limit(to: 90)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription; return }
                    self.entriesByCircleID[circleID] = snapshot?.documents.compactMap(Self.entry(from:)) ?? []
                }
            }
        memberListeners[circleID] = reference.collection("members")
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.membersByCircleID[circleID] = snapshot?.documents.compactMap(Self.member(from:)) ?? []
                }
            }
    }

    private static func circle(from document: DocumentSnapshot) -> WamoriCircle? {
        guard let data = document.data(), let name = data["name"] as? String, let ownerID = data["ownerID"] as? String else { return nil }
        let now = Date()
        return WamoriCircle(id: document.documentID, name: name, emoji: data["emoji"] as? String ?? "", ownerID: ownerID,
                            memberCount: data["memberCount"] as? Int ?? 1, maxMembers: data["maxMembers"] as? Int ?? AppConstants.maxCircleMembers,
                            status: CircleStatus(rawValue: data["status"] as? String ?? "active") ?? .active,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? now,
                            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? now)
    }

    private static func member(from document: QueryDocumentSnapshot) -> CircleMember? {
        let data = document.data()
        let userID = data["userID"] as? String ?? document.documentID
        return CircleMember(id: userID, userID: userID,
                            role: CircleMemberRole(rawValue: data["role"] as? String ?? "member") ?? .member,
                            joinedAt: (data["joinedAt"] as? Timestamp)?.dateValue() ?? Date(),
                            status: CircleMemberStatus(rawValue: data["status"] as? String ?? "active") ?? .active)
    }

    private static func entry(from document: QueryDocumentSnapshot) -> CircleEntry? {
        let data = document.data()
        guard let circleID = data["circleID"] as? String, let authorID = data["authorID"] as? String,
              let dateKey = data["dateKey"] as? String else { return nil }
        let media = (data["mediaItems"] as? [[String: Any]] ?? []).compactMap { item -> CircleMedia? in
            guard let id = item["id"] as? String, let path = item["storagePath"] as? String else { return nil }
            return CircleMedia(id: id, type: CircleMediaType(rawValue: item["type"] as? String ?? "image") ?? .image,
                               storagePath: path, width: item["width"] as? Int ?? 0, height: item["height"] as? Int ?? 0,
                               durationMs: item["durationMs"] as? Int, sizeBytes: (item["sizeBytes"] as? NSNumber)?.int64Value ?? 0)
        }
        return CircleEntry(id: document.documentID, circleID: circleID, authorID: authorID, dateKey: dateKey,
                           body: data["body"] as? String ?? "", mediaItems: media,
                           promptID: data["promptID"] as? String ?? "", promptTextSnapshot: data["promptTextSnapshot"] as? String ?? "",
                           humanScore: data["humanScore"] as? Int ?? 0,
                           humanBadge: HumanBadge(rawValue: data["humanBadge"] as? String ?? "checking") ?? .checking,
                           aiAssisted: data["aiAssisted"] as? Bool ?? false,
                           inputDurationMs: data["inputDurationMs"] as? Int ?? 0, characterCount: data["characterCount"] as? Int ?? 0,
                           editCount: data["editCount"] as? Int ?? 0, deleteCount: data["deleteCount"] as? Int ?? 0,
                           suspiciousBulkInputCount: data["suspiciousBulkInputCount"] as? Int ?? 0,
                           createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                           updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                           isDeleted: data["isDeleted"] as? Bool ?? false,
                           moderationStatus: ModerationStatus(rawValue: data["moderationStatus"] as? String ?? "active") ?? .active,
                           commentCount: data["commentCount"] as? Int ?? 0,
                           reactionCounts: data["reactionCounts"] as? [String: Int] ?? [:])
    }

    private static func comment(from document: QueryDocumentSnapshot) -> CircleComment? {
        let data = document.data()
        guard let circleID = data["circleID"] as? String,
              let entryID = data["entryID"] as? String,
              let userID = data["userID"] as? String else { return nil }
        return CircleComment(
            id: document.documentID,
            circleID: circleID,
            entryID: entryID,
            userID: userID,
            body: data["body"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            isDeleted: data["isDeleted"] as? Bool ?? false,
            moderationStatus: ModerationStatus(rawValue: data["moderationStatus"] as? String ?? "active") ?? .active
        )
    }
    #endif
}
