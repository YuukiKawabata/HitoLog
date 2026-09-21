import Foundation

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

struct CircleFunctionsService {
    var isAvailable: Bool {
        #if canImport(FirebaseFunctions)
        FirebaseBootstrap.isConfigured
        #else
        false
        #endif
    }

    func createCircle(name: String, emoji: String, clientRequestID: String = UUID().uuidString) async throws -> WamoriCircle {
        let data = try await call("createCircle", data: ["name": name, "emoji": emoji, "clientRequestID": clientRequestID])
        return try parseCircle(data)
    }

    func updateCircle(circleID: String, name: String, emoji: String) async throws {
        _ = try await call("updateCircle", data: ["circleID": circleID, "name": name, "emoji": emoji])
    }

    func createInvite(circleID: String, clientRequestID: String = UUID().uuidString) async throws -> CreatedCircleInvite {
        let data = try await call("createCircleInvite", data: ["circleID": circleID, "clientRequestID": clientRequestID])
        guard let id = data["inviteID"] as? String,
              let token = data["token"] as? String,
              let expiresAt = date(from: data["expiresAt"]) else { throw CircleServiceError.invalidResponse }
        return CreatedCircleInvite(id: id, token: token, expiresAt: expiresAt)
    }

    func listInvites(circleID: String) async throws -> [CircleInviteSummary] {
        let data = try await call("listCircleInvites", data: ["circleID": circleID])
        let items = data["invites"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? String, let expiresAt = date(from: item["expiresAt"]) else { return nil }
            return CircleInviteSummary(id: id, expiresAt: expiresAt, status: CircleInviteState(rawValue: item["status"] as? String ?? "invalid") ?? .invalid)
        }
    }

    func revokeInvite(circleID: String, inviteID: String) async throws {
        _ = try await call("revokeCircleInvite", data: ["circleID": circleID, "inviteID": inviteID])
    }

    func previewInvite(token: String) async throws -> CircleInvitePreview {
        let data = try await call("previewCircleInvite", data: ["token": token])
        guard let name = data["circleDisplayName"] as? String,
              let emoji = data["circleEmoji"] as? String,
              let owner = data["ownerDisplayName"] as? String,
              let expiresAt = date(from: data["expiresAt"]) else { throw CircleServiceError.invalidResponse }
        return CircleInvitePreview(
            circleDisplayName: name,
            circleEmoji: emoji,
            ownerDisplayName: owner,
            memberCount: data["memberCount"] as? Int ?? 0,
            maxMembers: data["maxMembers"] as? Int ?? AppConstants.maxCircleMembers,
            expiresAt: expiresAt,
            state: CircleInviteState(rawValue: data["state"] as? String ?? "invalid") ?? .invalid
        )
    }

    func joinCircle(token: String, clientRequestID: String = UUID().uuidString) async throws -> WamoriCircle {
        try parseCircle(try await call("joinCircleByInvite", data: ["token": token, "clientRequestID": clientRequestID]))
    }

    func createEntry(
        circleID: String,
        body: String,
        mediaItems: [CircleMedia],
        metrics: TypingMetrics,
        aiAssisted: Bool,
        locale: String = Locale.current.language.languageCode?.identifier ?? "ja",
        clientRequestID: String = UUID().uuidString
    ) async throws -> String {
        let payload: [String: Any] = [
            "circleID": circleID,
            "body": body,
            "mediaItems": mediaItems.map(mediaPayload),
            "typingMetrics": [
                "inputDurationMs": metrics.inputDurationMs,
                "characterCount": body.count,
                "editCount": metrics.editCount,
                "deleteCount": metrics.deleteCount,
                "suspiciousBulkInputCount": metrics.suspiciousBulkInputCount
            ],
            "aiAssisted": aiAssisted,
            "locale": locale,
            "timeZoneIdentifier": TimeZone.current.identifier,
            "clientRequestID": clientRequestID
        ]
        let data = try await call("createCircleEntry", data: payload)
        guard let id = data["entryID"] as? String else { throw CircleServiceError.invalidResponse }
        return id
    }

    func updateEntry(circleID: String, entryID: String, body: String, mediaItems: [CircleMedia], metrics: TypingMetrics, aiAssisted: Bool) async throws {
        _ = try await call("updateCircleEntry", data: [
            "circleID": circleID, "entryID": entryID, "body": body,
            "mediaItems": mediaItems.map(mediaPayload),
            "typingMetrics": [
                "inputDurationMs": metrics.inputDurationMs, "characterCount": body.count,
                "editCount": metrics.editCount, "deleteCount": metrics.deleteCount,
                "suspiciousBulkInputCount": metrics.suspiciousBulkInputCount
            ],
            "aiAssisted": aiAssisted
        ])
    }

    func deleteEntry(circleID: String, entryID: String) async throws {
        _ = try await call("deleteCircleEntry", data: ["circleID": circleID, "entryID": entryID])
    }

    func setReaction(circleID: String, entryID: String, kind: ReactionKind) async throws {
        _ = try await call("setCircleReaction", data: ["circleID": circleID, "entryID": entryID, "kind": kind.rawValue])
    }

    func createComment(circleID: String, entryID: String, body: String, clientRequestID: String = UUID().uuidString) async throws {
        _ = try await call("createCircleComment", data: ["circleID": circleID, "entryID": entryID, "body": body, "clientRequestID": clientRequestID])
    }

    func deleteComment(circleID: String, entryID: String, commentID: String) async throws {
        _ = try await call("deleteCircleComment", data: ["circleID": circleID, "entryID": entryID, "commentID": commentID])
    }

    func leaveCircle(circleID: String) async throws { _ = try await call("leaveCircle", data: ["circleID": circleID]) }
    func transferOwnership(circleID: String, userID: String) async throws { _ = try await call("transferCircleOwnership", data: ["circleID": circleID, "userID": userID]) }
    func removeMember(circleID: String, userID: String) async throws { _ = try await call("removeCircleMember", data: ["circleID": circleID, "userID": userID]) }
    func deleteCircle(circleID: String) async throws { _ = try await call("deleteCircle", data: ["circleID": circleID]) }
    func updateTimeZone(_ identifier: String) async throws { _ = try await call("updateTimeZone", data: ["timeZoneIdentifier": identifier]) }
    func prepareAccountDeletion() async throws { _ = try await call("prepareCircleAccountDeletion", data: [:]) }

    private func mediaPayload(_ media: CircleMedia) -> [String: Any] {
        var payload: [String: Any] = [
            "id": media.id,
            "type": media.type.rawValue,
            "storagePath": media.storagePath,
            "width": media.width,
            "height": media.height,
            "sizeBytes": media.sizeBytes
        ]
        if let durationMs = media.durationMs { payload["durationMs"] = durationMs }
        return payload
    }

    private func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        #if canImport(FirebaseFunctions)
        guard isAvailable else { throw CircleServiceError.unavailable }
        do {
            let result = try await Functions.functions(region: "asia-northeast1").httpsCallable(name).call(data)
            guard let dictionary = result.data as? [String: Any] else { throw CircleServiceError.invalidResponse }
            return dictionary
        } catch let error as CircleServiceError {
            throw error
        } catch {
            throw map(error)
        }
        #else
        throw CircleServiceError.unavailable
        #endif
    }

    private func parseCircle(_ data: [String: Any]) throws -> WamoriCircle {
        guard let payload = (data["circle"] as? [String: Any]) ?? (data["data"] as? [String: Any]),
              let id = payload["id"] as? String,
              let name = payload["name"] as? String,
              let ownerID = payload["ownerID"] as? String else { throw CircleServiceError.invalidResponse }
        let now = Date()
        return WamoriCircle(id: id, name: name, emoji: payload["emoji"] as? String ?? "", ownerID: ownerID,
                            memberCount: payload["memberCount"] as? Int ?? 1,
                            maxMembers: payload["maxMembers"] as? Int ?? AppConstants.maxCircleMembers,
                            status: CircleStatus(rawValue: payload["status"] as? String ?? "active") ?? .active,
                            createdAt: date(from: payload["createdAt"]) ?? now,
                            updatedAt: date(from: payload["updatedAt"]) ?? now)
    }

    private func date(from value: Any?) -> Date? {
        if let milliseconds = value as? Double { return Date(timeIntervalSince1970: milliseconds / 1_000) }
        if let milliseconds = value as? Int { return Date(timeIntervalSince1970: Double(milliseconds) / 1_000) }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    private func map(_ error: Error) -> CircleServiceError {
        let nsError = error as NSError
        let details = nsError.userInfo["details"] as? [String: Any]
        let code = (details?["code"] as? String) ?? (nsError.userInfo["code"] as? String) ?? ""
        switch code {
        case "invalid-invite": return .invalidInvite
        case "invite-expired": return .inviteExpired
        case "invite-used": return .inviteUsed
        case "circle-full": return .circleFull
        case "already-member": return .alreadyMember
        case "entry-already-exists": return .entryAlreadyExists
        case "entry-edit-window-closed": return .editWindowClosed
        case "permission-denied": return .permissionDenied
        case "ownership-transfer-required": return .ownershipTransferRequired
        case "operation-in-progress": return .operationInProgress
        default:
            if nsError.domain == NSURLErrorDomain { return .network }
            return .server(nsError.localizedDescription)
        }
    }
}
