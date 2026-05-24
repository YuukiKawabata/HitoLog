import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct RemoteDataSnapshot {
    var users: [AppUser]
    var posts: [Post]
    var comments: [Comment]
    var likedPostIDs: Set<String>
    var blockedUserIDs: Set<String>
    var mutedUserIDs: Set<String>
    var reports: [ReportRecord]
}

struct FirebaseDataStore {
    var isAvailable: Bool {
        FirebaseBootstrap.isConfigured
    }

    func loadSnapshot(currentUserID: String) async throws -> RemoteDataSnapshot {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        async let usersSnapshot = db.collection("users").whereField("isDeleted", isEqualTo: false).getDocuments()
        async let postsSnapshot = db.collection("posts")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        async let commentsSnapshot = db.collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt")
            .limit(to: 300)
            .getDocuments()
        async let likesSnapshot = db.collection("likes")
            .whereField("userID", isEqualTo: currentUserID)
            .getDocuments()
        async let blocksSnapshot = db.collection("blocks")
            .whereField("blockerID", isEqualTo: currentUserID)
            .getDocuments()
        async let mutesSnapshot = db.collection("mutes")
            .whereField("muterID", isEqualTo: currentUserID)
            .getDocuments()
        async let reportsSnapshot = db.collection("reports")
            .whereField("reporterID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let usersResult = try await usersSnapshot
        let postsResult = try await postsSnapshot
        let commentsResult = try await commentsSnapshot
        let likesResult = try await likesSnapshot
        let blocksResult = try await blocksSnapshot
        let mutesResult = try await mutesSnapshot
        let reportsResult = try await reportsSnapshot

        let users = usersResult.documents.compactMap(mapUser)
        let posts = postsResult.documents.compactMap(mapPost)
        let comments = commentsResult.documents.compactMap(mapComment)
        let likedPostIDs = Set(likesResult.documents.compactMap { $0.data()["postID"] as? String })
        let blockedUserIDs = Set(blocksResult.documents.compactMap { $0.data()["blockedUserID"] as? String })
        let mutedUserIDs = Set(mutesResult.documents.compactMap { $0.data()["mutedUserID"] as? String })
        let reports = reportsResult.documents.compactMap(mapReport)

        return RemoteDataSnapshot(
            users: users,
            posts: posts,
            comments: comments,
            likedPostIDs: likedPostIDs,
            blockedUserIDs: blockedUserIDs,
            mutedUserIDs: mutedUserIDs,
            reports: reports
        )
        #else
        return RemoteDataSnapshot(
            users: [],
            posts: [],
            comments: [],
            likedPostIDs: [],
            blockedUserIDs: [],
            mutedUserIDs: [],
            reports: []
        )
        #endif
    }

    func loadUser(userID: String) async throws -> AppUser? {
        #if canImport(FirebaseFirestore)
        let document = try await Firestore.firestore()
            .collection("users")
            .document(userID)
            .getDocument()

        guard document.exists, let data = document.data() else {
            return nil
        }

        return mapUser(id: document.documentID, data: data)
        #else
        return nil
        #endif
    }

    func upsertUser(_ user: AppUser, email: String?) async throws {
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "displayName": user.displayName,
            "handle": user.handle,
            "bio": user.bio,
            "humanLevel": user.humanLevel,
            "humanVerifiedPostRate": user.humanVerifiedPostRate,
            "updatedAt": FieldValue.serverTimestamp(),
            "isDeleted": user.isDeleted
        ]
        if let email {
            data["email"] = email
        }
        if let appleUserID = user.appleUserId {
            data["appleUserID"] = appleUserID
        }
        data["avatarUrl"] = user.avatarUrl ?? FieldValue.delete()

        let ref = Firestore.firestore().collection("users").document(user.id)
        let snapshot = try await ref.getDocument()
        if snapshot.exists {
            try await ref.setData(data, merge: true)
        } else {
            data["createdAt"] = Timestamp(date: user.createdAt)
            data["notificationsEnabled"] = true
            try await ref.setData(data, merge: true)
        }
        #endif
    }

    func savePost(_ post: Post) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("posts")
            .document(post.id)
            .setData(post.firestoreData, merge: true)
        #endif
    }

    func updatePostBody(postID: String, body: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("posts")
            .document(postID)
            .updateData([
                "body": body,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        #endif
    }

    func deletePost(postID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("posts")
            .document(postID)
            .updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        #endif
    }

    func addComment(_ comment: Comment) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("comments")
            .document(comment.id)
            .setData(comment.firestoreData, merge: true)
        #endif
    }

    func setLike(postID: String, userID: String, isLiked: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("likes").document("\(postID)_\(userID)")
        if isLiked {
            try await ref.setData([
                "postID": postID,
                "userID": userID,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await ref.delete()
        }
        #endif
    }

    func setBlock(blockerID: String, blockedUserID: String, isBlocked: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("blocks").document("\(blockerID)_\(blockedUserID)")
        if isBlocked {
            try await ref.setData([
                "blockerID": blockerID,
                "blockedUserID": blockedUserID,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await ref.delete()
        }
        #endif
    }

    func setMute(muterID: String, mutedUserID: String, isMuted: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("mutes").document("\(muterID)_\(mutedUserID)")
        if isMuted {
            try await ref.setData([
                "muterID": muterID,
                "mutedUserID": mutedUserID,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await ref.delete()
        }
        #endif
    }

    func addReport(_ report: ReportRecord, reporterID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("reports")
            .document(report.id)
            .setData([
                "reporterID": reporterID,
                "targetDescription": report.targetDescription,
                "reason": report.reason,
                "status": report.status,
                "createdAt": Timestamp(date: report.createdAt)
            ], merge: true)
        #endif
    }

    func saveFCMToken(userID: String, token: String, isEnabled: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let tokenID = token.stableFirestoreID
        let db = Firestore.firestore()
        try await db.collection("fcmTokens")
            .document(userID)
            .collection("tokens")
            .document(tokenID)
            .setData([
                "token": token,
                "isEnabled": isEnabled,
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

        try await updateNotificationPreference(userID: userID, isEnabled: isEnabled)
        #endif
    }

    func updateNotificationPreference(userID: String, isEnabled: Bool) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("users")
            .document(userID)
            .setData([
                "notificationsEnabled": isEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        #endif
    }

    func deleteAccountData(userID: String) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        try await db.collection("users")
            .document(userID)
            .setData([
                "displayName": "Deleted User",
                "handle": "deleted_\(String(userID.prefix(8)).lowercased())",
                "bio": "",
                "avatarUrl": FieldValue.delete(),
                "notificationsEnabled": false,
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

        let posts = try await db.collection("posts")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in posts.documents {
            try await document.reference.updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }

        let comments = try await db.collection("comments")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in comments.documents {
            try await document.reference.updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }

        let likes = try await db.collection("likes")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in likes.documents {
            try await document.reference.delete()
        }

        let blocks = try await db.collection("blocks")
            .whereField("blockerID", isEqualTo: userID)
            .getDocuments()
        for document in blocks.documents {
            try await document.reference.delete()
        }

        let mutes = try await db.collection("mutes")
            .whereField("muterID", isEqualTo: userID)
            .getDocuments()
        for document in mutes.documents {
            try await document.reference.delete()
        }

        let tokenDocuments = try await db.collection("fcmTokens")
            .document(userID)
            .collection("tokens")
            .getDocuments()
        for document in tokenDocuments.documents {
            try await document.reference.delete()
        }
        #endif
    }
}

#if canImport(FirebaseFirestore)
private extension FirebaseDataStore {
    func mapUser(_ document: QueryDocumentSnapshot) -> AppUser? {
        mapUser(id: document.documentID, data: document.data())
    }

    func mapUser(id: String, data: [String: Any]) -> AppUser? {
        return AppUser(
            id: id,
            displayName: stringValue(data["displayName"], fallback: "User"),
            handle: stringValue(data["handle"], fallback: "user_\(id.prefix(8))"),
            bio: stringValue(data["bio"], fallback: ""),
            avatarUrl: data["avatarUrl"] as? String,
            appleUserId: data["appleUserID"] as? String,
            humanLevel: intValue(data["humanLevel"], fallback: 1),
            humanVerifiedPostRate: doubleValue(data["humanVerifiedPostRate"], fallback: 0),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isDeleted: boolValue(data["isDeleted"], fallback: false)
        )
    }

    func mapPost(_ document: QueryDocumentSnapshot) -> Post? {
        let data = document.data()
        guard let userID = data["userID"] as? String,
              let body = data["body"] as? String else {
            return nil
        }

        return Post(
            id: document.documentID,
            userId: userID,
            body: body,
            humanScore: intValue(data["humanScore"], fallback: 0),
            humanBadge: HumanBadge(rawValue: stringValue(data["humanBadge"], fallback: HumanBadge.checking.rawValue)) ?? .checking,
            inputDurationMs: intValue(data["inputDurationMs"], fallback: 0),
            characterCount: intValue(data["characterCount"], fallback: body.count),
            editCount: intValue(data["editCount"], fallback: 0),
            deleteCount: intValue(data["deleteCount"], fallback: 0),
            suspiciousBulkInputCount: intValue(data["suspiciousBulkInputCount"], fallback: 0),
            appCheckVerified: boolValue(data["appCheckVerified"], fallback: false),
            likeCount: intValue(data["likeCount"], fallback: 0),
            commentCount: intValue(data["commentCount"], fallback: 0),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isDeleted: boolValue(data["isDeleted"], fallback: false)
        )
    }

    func mapComment(_ document: QueryDocumentSnapshot) -> Comment? {
        let data = document.data()
        guard let postID = data["postID"] as? String,
              let userID = data["userID"] as? String,
              let body = data["body"] as? String else {
            return nil
        }

        return Comment(
            id: document.documentID,
            postId: postID,
            userId: userID,
            body: body,
            humanScore: intValue(data["humanScore"], fallback: 0),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isDeleted: boolValue(data["isDeleted"], fallback: false)
        )
    }

    func mapReport(_ document: QueryDocumentSnapshot) -> ReportRecord? {
        let data = document.data()
        guard let targetDescription = data["targetDescription"] as? String,
              let reason = data["reason"] as? String else {
            return nil
        }

        return ReportRecord(
            id: document.documentID,
            targetDescription: targetDescription,
            reason: reason,
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            status: stringValue(data["status"], fallback: "確認待ち")
        )
    }

    func stringValue(_ value: Any?, fallback: String) -> String {
        guard let value = value as? String, !value.isEmpty else { return fallback }
        return value
    }

    func intValue(_ value: Any?, fallback: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return fallback
    }

    func doubleValue(_ value: Any?, fallback: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return fallback
    }

    func boolValue(_ value: Any?, fallback: Bool) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return fallback
    }

    func dateValue(_ value: Any?, fallback: Date) -> Date {
        if let value = value as? Timestamp {
            return value.dateValue()
        }
        if let value = value as? Date {
            return value
        }
        return fallback
    }
}

private extension Post {
    var firestoreData: [String: Any] {
        [
            "userID": userId,
            "body": body,
            "humanScore": humanScore,
            "humanBadge": humanBadge.rawValue,
            "inputDurationMs": inputDurationMs,
            "characterCount": characterCount,
            "editCount": editCount,
            "deleteCount": deleteCount,
            "suspiciousBulkInputCount": suspiciousBulkInputCount,
            "appCheckVerified": appCheckVerified,
            "likeCount": likeCount,
            "commentCount": commentCount,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "isDeleted": isDeleted
        ]
    }
}

private extension Comment {
    var firestoreData: [String: Any] {
        [
            "postID": postId,
            "userID": userId,
            "body": body,
            "humanScore": humanScore,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "isDeleted": isDeleted
        ]
    }
}
#endif

private extension String {
    var stableFirestoreID: String {
        data(using: .utf8)?
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(128)
            .description ?? UUID().uuidString
    }
}
