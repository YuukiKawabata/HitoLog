import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct RemoteDataSnapshot {
    var users: [AppUser]
    var posts: [Post]
    var comments: [Comment]
    var likedPostIDs: Set<String>
    var bookmarkedPostIDs: Set<String>
    var blockedUserIDs: Set<String>
    var mutedUserIDs: Set<String>
    var mutedWords: [MutedWord]
    var topicRooms: [TopicRoom]
    var followedTopicIDs: Set<String>
    var feedControls: [FeedControl]
    var followingUserIDs: Set<String>
    var followerCountsByUserID: [String: Int]
    var followingCountsByUserID: [String: Int]
    var followersByUserID: [String: Set<String>]
    var followingByUserID: [String: Set<String>]
    var reports: [ReportRecord]
    var notifications: [AppNotification]
    var adminReports: [ReportRecord]
    var hasMorePosts: Bool
}

struct TimelinePostPage {
    var posts: [Post]
    var users: [AppUser]
    var hasMore: Bool
}

struct RemoteFollowState {
    var users: [AppUser]
    var followerIDs: Set<String>
    var followingIDs: Set<String>
}

struct RemoteBookmarkState {
    var postIDs: Set<String>
    var posts: [Post]
    var users: [AppUser]
}

private struct FollowRecord {
    let followerID: String
    let followeeID: String
}

struct FirebaseDataStore {
    var isAvailable: Bool {
        FirebaseBootstrap.isConfigured
    }

    func loadSnapshot(currentUserID: String) async throws -> RemoteDataSnapshot {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        async let usersSnapshot = db.collection("users").whereField("isDeleted", isEqualTo: false).getDocuments()
        async let postsSnapshot = timelinePostsQuery(db: db, before: nil).getDocuments()
        async let likesSnapshot = db.collection("likes")
            .whereField("userID", isEqualTo: currentUserID)
            .getDocuments()
        async let bookmarksSnapshot = db.collection("bookmarks")
            .whereField("userID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        async let blocksSnapshot = db.collection("blocks")
            .whereField("blockerID", isEqualTo: currentUserID)
            .getDocuments()
        async let mutesSnapshot = db.collection("mutes")
            .whereField("muterID", isEqualTo: currentUserID)
            .getDocuments()
        async let mutedWordsSnapshot = db.collection("mutedWords")
            .whereField("userID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments()
        async let topicRoomsSnapshot = db.collection("topicRooms")
            .whereField("moderationStatus", isEqualTo: ModerationStatus.active.rawValue)
            .order(by: "lastPostAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        async let topicFollowsSnapshot = db.collection("topicFollows")
            .whereField("userID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments()
        async let feedControlsSnapshot = db.collection("feedControls")
            .whereField("userID", isEqualTo: currentUserID)
            .order(by: "updatedAt", descending: true)
            .limit(to: 200)
            .getDocuments()
        async let followingSnapshot = db.collection("follows")
            .whereField("followerID", isEqualTo: currentUserID)
            .getDocuments()
        async let followersSnapshot = db.collection("follows")
            .whereField("followeeID", isEqualTo: currentUserID)
            .getDocuments()
        async let reportsSnapshot = db.collection("reports")
            .whereField("reporterID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        async let notificationsSnapshot = db.collection("notifications")
            .whereField("recipientID", isEqualTo: currentUserID)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let usersResult = try await usersSnapshot
        let postsResult = try await postsSnapshot
        let likesResult = try await likesSnapshot
        let bookmarksResult = try await bookmarksSnapshot
        let blocksResult = try await blocksSnapshot
        let mutesResult = try await mutesSnapshot
        let mutedWordsResult = try await mutedWordsSnapshot
        let topicRoomsResult = try await topicRoomsSnapshot
        let topicFollowsResult = try await topicFollowsSnapshot
        let feedControlsResult = try await feedControlsSnapshot
        let followingResult = try await followingSnapshot
        let followersResult = try await followersSnapshot
        let reportsResult = try await reportsSnapshot
        let notificationsResult = try await notificationsSnapshot

        let users = usersResult.documents.compactMap(mapUser)
        let activeUserIDs = Set(users.map(\.id))
        let loadedPosts = postsResult.documents.compactMap(mapPost)
            .filter { $0.moderationStatus == .active }
        let sourcePostIDs = loadedPosts.compactMap(\.sourcePostID)
        let sourcePosts = try await loadPosts(postIDs: sourcePostIDs)
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let posts = uniquePosts(loadedPosts + sourcePosts)
        let likedPostIDs = Set(likesResult.documents.compactMap { $0.data()["postID"] as? String })
        let bookmarkedPostIDs = Set(bookmarksResult.documents.compactMap { $0.data()["postID"] as? String })
        let blockedUserIDs = Set(blocksResult.documents.compactMap { $0.data()["blockedUserID"] as? String })
        let mutedUserIDs = Set(mutesResult.documents.compactMap { $0.data()["mutedUserID"] as? String })
        let mutedWords = mutedWordsResult.documents.compactMap(mapMutedWord)
        let topicRooms = topicRoomsResult.documents.compactMap(mapTopicRoom)
        let followedTopicIDs = Set(topicFollowsResult.documents.compactMap { $0.data()["topic"] as? String })
        let feedControls = feedControlsResult.documents.compactMap(mapFeedControl)
        let followRecords = (followingResult.documents + followersResult.documents).compactMap(mapFollow).filter {
            activeUserIDs.contains($0.followerID) && activeUserIDs.contains($0.followeeID)
        }
        let followState = followState(from: followRecords, currentUserID: currentUserID)
        let reports = reportsResult.documents.compactMap(mapReport)
        let notifications = notificationsResult.documents.compactMap(mapNotification)
        let adminReports = users.first(where: { $0.id == currentUserID })?.isAdmin == true
            ? try await loadAdminReports()
            : []

        return RemoteDataSnapshot(
            users: users,
            posts: posts,
            comments: [],
            likedPostIDs: likedPostIDs,
            bookmarkedPostIDs: bookmarkedPostIDs,
            blockedUserIDs: blockedUserIDs,
            mutedUserIDs: mutedUserIDs,
            mutedWords: mutedWords,
            topicRooms: topicRooms,
            followedTopicIDs: followedTopicIDs,
            feedControls: feedControls,
            followingUserIDs: followState.followingUserIDs,
            followerCountsByUserID: followState.followerCountsByUserID,
            followingCountsByUserID: followState.followingCountsByUserID,
            followersByUserID: followState.followersByUserID,
            followingByUserID: followState.followingByUserID,
            reports: reports,
            notifications: notifications,
            adminReports: adminReports,
            hasMorePosts: postsResult.documents.count >= Self.timelinePageSize
        )
        #else
        return RemoteDataSnapshot(
            users: [],
            posts: [],
            comments: [],
            likedPostIDs: [],
            bookmarkedPostIDs: [],
            blockedUserIDs: [],
            mutedUserIDs: [],
            mutedWords: [],
            topicRooms: [],
            followedTopicIDs: [],
            feedControls: [],
            followingUserIDs: [],
            followerCountsByUserID: [:],
            followingCountsByUserID: [:],
            followersByUserID: [:],
            followingByUserID: [:],
            reports: [],
            notifications: [],
            adminReports: [],
            hasMorePosts: false
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

    func loadTimelinePosts(currentUserID: String, before cursor: Date?, limit: Int = 25) async throws -> TimelinePostPage {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let snapshot = try await timelinePostsQuery(db: db, before: cursor, limit: limit + 1).getDocuments()
        let documents = Array(snapshot.documents.prefix(limit))
        let loadedPosts = documents.compactMap(mapPost).filter { $0.moderationStatus == .active }
        let sourcePosts = try await loadPosts(postIDs: loadedPosts.compactMap(\.sourcePostID))
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let posts = uniquePosts(loadedPosts + sourcePosts)
        let authorIDs = Array(Set(posts.map(\.userId) + [currentUserID]))
        let users = try await loadUsers(userIDs: authorIDs)
        return TimelinePostPage(posts: posts, users: users, hasMore: snapshot.documents.count > limit)
        #else
        return TimelinePostPage(posts: [], users: [], hasMore: false)
        #endif
    }

    func loadTopicPosts(topic: String, limit: Int = 50) async throws -> TimelinePostPage {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("posts")
            .whereField("topics", arrayContains: topic)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let loadedPosts = snapshot.documents.compactMap(mapPost).filter { $0.moderationStatus == .active }
        let sourcePosts = try await loadPosts(postIDs: loadedPosts.compactMap(\.sourcePostID))
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let posts = uniquePosts(loadedPosts + sourcePosts)
        let users = try await loadUsers(userIDs: Array(Set(posts.map(\.userId))))
        return TimelinePostPage(posts: posts, users: users, hasMore: snapshot.documents.count >= limit)
        #else
        return TimelinePostPage(posts: [], users: [], hasMore: false)
        #endif
    }

    func searchPosts(query: String, limit: Int = 50) async throws -> TimelinePostPage {
        #if canImport(FirebaseFirestore)
        guard let token = PostSearchTokenizer.primaryToken(for: query) else {
            return TimelinePostPage(posts: [], users: [], hasMore: false)
        }

        let snapshot = try await Firestore.firestore()
            .collection("posts")
            .whereField("searchTokens", arrayContains: token)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let loadedPosts = snapshot.documents.compactMap(mapPost).filter { $0.moderationStatus == .active }
        let sourcePosts = try await loadPosts(postIDs: loadedPosts.compactMap(\.sourcePostID))
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let posts = uniquePosts(loadedPosts + sourcePosts)
        let users = try await loadUsers(userIDs: Array(Set(posts.map(\.userId))))
        return TimelinePostPage(posts: posts, users: users, hasMore: snapshot.documents.count >= limit)
        #else
        return TimelinePostPage(posts: [], users: [], hasMore: false)
        #endif
    }

    func loadComments(postID: String) async throws -> [Comment] {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("comments")
            .whereField("postID", isEqualTo: postID)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt")
            .limit(to: 200)
            .getDocuments()

        return snapshot.documents.compactMap(mapComment).filter { $0.moderationStatus == .active }
        #else
        return []
        #endif
    }

    func loadFollowState(userID: String) async throws -> RemoteFollowState {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        async let followersSnapshot = db.collection("follows")
            .whereField("followeeID", isEqualTo: userID)
            .limit(to: 200)
            .getDocuments()
        async let followingSnapshot = db.collection("follows")
            .whereField("followerID", isEqualTo: userID)
            .limit(to: 200)
            .getDocuments()

        let followersResult = try await followersSnapshot
        let followingResult = try await followingSnapshot
        let followerRecords = followersResult.documents.compactMap(mapFollow)
        let followingRecords = followingResult.documents.compactMap(mapFollow)
        let followerIDs = Set(followerRecords.map(\.followerID))
        let followingIDs = Set(followingRecords.map(\.followeeID))
        let users = try await loadUsers(userIDs: Array(followerIDs.union(followingIDs).union([userID])))
        return RemoteFollowState(users: users, followerIDs: followerIDs, followingIDs: followingIDs)
        #else
        return RemoteFollowState(users: [], followerIDs: [], followingIDs: [])
        #endif
    }

    func loadNotifications(recipientID: String) async throws -> [AppNotification] {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("notifications")
            .whereField("recipientID", isEqualTo: recipientID)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap(mapNotification)
        #else
        return []
        #endif
    }

    func loadBookmarkedPosts(userID: String) async throws -> RemoteBookmarkState {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("bookmarks")
            .whereField("userID", isEqualTo: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        let postIDs = snapshot.documents.compactMap { $0.data()["postID"] as? String }
        let loadedPosts = try await loadPosts(postIDs: postIDs)
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let sourcePosts = try await loadPosts(postIDs: loadedPosts.compactMap(\.sourcePostID))
            .filter { !$0.isDeleted && $0.moderationStatus == .active }
        let posts = uniquePosts(loadedPosts + sourcePosts)
        let users = try await loadUsers(userIDs: Array(Set(posts.map(\.userId))))
        return RemoteBookmarkState(postIDs: Set(postIDs), posts: posts, users: users)
        #else
        return RemoteBookmarkState(postIDs: [], posts: [], users: [])
        #endif
    }

    func markNotificationsRead(notificationIDs: [String]) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let batch = db.batch()
        for notificationID in notificationIDs {
            batch.updateData([
                "isRead": true,
                "readAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("notifications").document(notificationID))
        }
        try await batch.commit()
        #endif
    }

    func searchUsers(query: String) async throws -> [AppUser] {
        #if canImport(FirebaseFirestore)
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        let db = Firestore.firestore()
        async let handleSnapshot = db.collection("users")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "handleLowercase")
            .start(at: [needle])
            .end(at: ["\(needle)\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()
        async let nameSnapshot = db.collection("users")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "displayNameLowercase")
            .start(at: [needle])
            .end(at: ["\(needle)\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()

        let handleResult = try await handleSnapshot
        let nameResult = try await nameSnapshot
        let documents = handleResult.documents + nameResult.documents
        return uniqueUsers(documents.compactMap(mapUser).filter { !$0.isSuspended })
        #else
        return []
        #endif
    }

    func upsertUser(_ user: AppUser, email: String?) async throws {
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "displayName": user.displayName,
            "handle": user.handle,
            "displayNameLowercase": user.displayNameLowercase,
            "handleLowercase": user.handleLowercase,
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
        data["website"] = user.website ?? FieldValue.delete()
        data["location"] = user.location ?? FieldValue.delete()
        data["occupation"] = user.occupation ?? FieldValue.delete()

        let ref = Firestore.firestore().collection("users").document(user.id)
        let snapshot = try await ref.getDocument()
        if snapshot.exists {
            let existingData = snapshot.data() ?? [:]
            if existingData["isAdmin"] == nil {
                data["isAdmin"] = false
            }
            if existingData["isSuspended"] == nil {
                data["isSuspended"] = false
            }
            if existingData["followerCount"] == nil {
                data["followerCount"] = user.followerCount
            }
            if existingData["followingCount"] == nil {
                data["followingCount"] = user.followingCount
            }
            try await ref.setData(data, merge: true)
        } else {
            data["createdAt"] = Timestamp(date: user.createdAt)
            data["notificationsEnabled"] = true
            data["isAdmin"] = false
            data["isSuspended"] = false
            data["followerCount"] = 0
            data["followingCount"] = 0
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
                "topics": TopicExtractor.topics(in: body),
                "searchTokens": PostSearchTokenizer.tokens(in: body, topics: TopicExtractor.topics(in: body)),
                "editCount": FieldValue.increment(Int64(1)),
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

    func deleteComment(commentID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("comments")
            .document(commentID)
            .setData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        #endif
    }

    func hideComment(commentID: String, reason: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("comments")
            .document(commentID)
            .setData([
                "moderationStatus": ModerationStatus.hidden.rawValue,
                "hiddenReason": reason,
                "hiddenAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
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

    func setBookmark(postID: String, userID: String, isBookmarked: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("bookmarks").document("\(userID)_\(postID)")
        if isBookmarked {
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

    func setMutedWord(_ mutedWord: MutedWord, isMuted: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("mutedWords").document(mutedWord.id)
        if isMuted {
            try await ref.setData([
                "userID": mutedWord.userID,
                "word": mutedWord.word,
                "normalizedWord": mutedWord.normalizedWord,
                "createdAt": Timestamp(date: mutedWord.createdAt)
            ], merge: true)
        } else {
            try await ref.delete()
        }
        #endif
    }

    func setTopicFollow(userID: String, topic: String, isFollowing: Bool) async throws {
        #if canImport(FirebaseFirestore)
        let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) ?? topic
        guard !normalizedTopic.isEmpty else { return }

        let ref = Firestore.firestore().collection("topicFollows").document("\(userID)_\(normalizedTopic)")
        if isFollowing {
            try await ref.setData([
                "userID": userID,
                "topic": normalizedTopic,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await ref.delete()
        }
        #endif
    }

    func setFeedControl(_ feedControl: FeedControl) async throws {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("feedControls").document(feedControl.id)
        try await ref.setData([
            "userID": feedControl.userID,
            "targetType": feedControl.targetType.rawValue,
            "targetID": feedControl.targetID,
            "preference": feedControl.preference.rawValue,
            "createdAt": Timestamp(date: feedControl.createdAt),
            "updatedAt": Timestamp(date: feedControl.updatedAt)
        ], merge: true)
        #endif
    }

    func deleteFeedControl(_ feedControl: FeedControl) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("feedControls").document(feedControl.id).delete()
        #endif
    }

    func setFollow(followerID: String, followeeID: String, isFollowing: Bool) async throws {
        #if canImport(FirebaseFirestore)
        guard followerID != followeeID else { return }

        let ref = Firestore.firestore().collection("follows").document("\(followerID)_\(followeeID)")
        if isFollowing {
            try await ref.setData([
                "followerID": followerID,
                "followeeID": followeeID,
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
                "targetType": report.targetType.rawValue,
                "targetID": report.targetID ?? "",
                "targetOwnerID": report.targetOwnerID ?? "",
                "targetDescription": report.targetDescription,
                "reason": report.reason,
                "status": report.status,
                "createdAt": Timestamp(date: report.createdAt)
            ], merge: true)
        #endif
    }

    func addFeedback(_ feedback: AppFeedback) async throws {
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "userID": feedback.userID,
            "category": feedback.category.rawValue,
            "message": feedback.message,
            "appVersion": feedback.appVersion,
            "buildNumber": feedback.buildNumber,
            "platform": feedback.platform,
            "status": feedback.status,
            "createdAt": Timestamp(date: feedback.createdAt)
        ]
        if let contactEmail = feedback.contactEmail, !contactEmail.isEmpty {
            data["contactEmail"] = contactEmail
        }

        try await Firestore.firestore()
            .collection("feedback")
            .document(feedback.id)
            .setData(data, merge: true)
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

    func loadAdminReports() async throws -> [ReportRecord] {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("reports")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        return snapshot.documents.compactMap(mapReport)
        #else
        return []
        #endif
    }

    func resolveReport(reportID: String, status: String, adminNote: String, adminID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("reports")
            .document(reportID)
            .setData([
                "status": status,
                "adminNote": adminNote,
                "resolvedAt": FieldValue.serverTimestamp(),
                "resolvedBy": adminID
            ], merge: true)
        #endif
    }

    func hideContent(targetType: ReportTargetType, targetID: String, reason: String, adminID: String) async throws {
        #if canImport(FirebaseFirestore)
        let collection: String
        switch targetType {
        case .post:    collection = "posts"
        case .comment: collection = "comments"
        case .article: collection = "articles"
        case .user, .other:
            return
        }

        try await Firestore.firestore()
            .collection(collection)
            .document(targetID)
            .setData([
                "moderationStatus": ModerationStatus.hidden.rawValue,
                "hiddenReason": reason,
                "hiddenAt": FieldValue.serverTimestamp(),
                "hiddenBy": adminID,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        #endif
    }

    func setUserSuspended(userID: String, isSuspended: Bool, reason: String, adminID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("users")
            .document(userID)
            .setData([
                "isSuspended": isSuspended,
                "suspensionReason": reason,
                "suspendedAt": FieldValue.serverTimestamp(),
                "suspendedBy": adminID,
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

        let bookmarks = try await db.collection("bookmarks")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in bookmarks.documents {
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

        let mutedWords = try await db.collection("mutedWords")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in mutedWords.documents {
            try await document.reference.delete()
        }

        let feedback = try await db.collection("feedback")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in feedback.documents {
            try await document.reference.delete()
        }

        let topicFollows = try await db.collection("topicFollows")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in topicFollows.documents {
            try await document.reference.delete()
        }

        let feedControls = try await db.collection("feedControls")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        for document in feedControls.documents {
            try await document.reference.delete()
        }

        let following = try await db.collection("follows")
            .whereField("followerID", isEqualTo: userID)
            .getDocuments()
        for document in following.documents {
            try await document.reference.delete()
        }

        let followers = try await db.collection("follows")
            .whereField("followeeID", isEqualTo: userID)
            .getDocuments()
        for document in followers.documents {
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
    static var timelinePageSize: Int { 26 }

    func timelinePostsQuery(db: Firestore, before cursor: Date?, limit: Int = Self.timelinePageSize) -> Query {
        var query: Query = db.collection("posts")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        if let cursor {
            query = query.whereField("createdAt", isLessThan: Timestamp(date: cursor))
        }

        return query
    }

    func loadUsers(userIDs: [String]) async throws -> [AppUser] {
        let uniqueIDs = Array(Set(userIDs)).filter { !$0.isEmpty }
        guard !uniqueIDs.isEmpty else { return [] }

        let db = Firestore.firestore()
        var loadedUsers: [AppUser] = []
        for chunk in uniqueIDs.chunked(into: 10) {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            loadedUsers += snapshot.documents.compactMap(mapUser)
        }
        return uniqueUsers(loadedUsers)
    }

    func loadPosts(postIDs: [String]) async throws -> [Post] {
        let uniqueIDs = Array(Set(postIDs)).filter { !$0.isEmpty }
        guard !uniqueIDs.isEmpty else { return [] }

        let db = Firestore.firestore()
        var loadedPosts: [Post] = []
        for chunk in uniqueIDs.chunked(into: 10) {
            let snapshot = try await db.collection("posts")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            loadedPosts += snapshot.documents.compactMap(mapPost)
        }
        return loadedPosts.sorted { $0.createdAt > $1.createdAt }
    }

    func uniqueUsers(_ users: [AppUser]) -> [AppUser] {
        var seen = Set<String>()
        return users.filter { user in
            guard !seen.contains(user.id), !user.isDeleted else { return false }
            seen.insert(user.id)
            return true
        }
    }

    func uniquePosts(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts
            .filter { post in
                guard !seen.contains(post.id), !post.isDeleted else { return false }
                seen.insert(post.id)
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

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
            isDeleted: boolValue(data["isDeleted"], fallback: false),
            isAdmin: boolValue(data["isAdmin"], fallback: false),
            isSuspended: boolValue(data["isSuspended"], fallback: false),
            followerCount: intValue(data["followerCount"], fallback: 0),
            followingCount: intValue(data["followingCount"], fallback: 0),
            website: (data["website"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            location: (data["location"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            occupation: (data["occupation"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
            topics: data["topics"] as? [String] ?? TopicExtractor.topics(in: body),
            searchTokens: data["searchTokens"] as? [String] ?? PostSearchTokenizer.tokens(in: body, topics: data["topics"] as? [String] ?? TopicExtractor.topics(in: body)),
            mediaItems: postMediaItems(from: data["mediaItems"]),
            shareType: PostShareType(rawValue: stringValue(data["shareType"], fallback: PostShareType.original.rawValue)) ?? .original,
            sourcePostID: nonEmptyString(data["sourcePostID"]),
            sourceUserID: nonEmptyString(data["sourceUserID"]),
            commentPermission: CommentPermission(rawValue: stringValue(data["commentPermission"], fallback: CommentPermission.everyone.rawValue)) ?? .everyone,
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
            repostCount: intValue(data["repostCount"], fallback: 0),
            quoteCount: intValue(data["quoteCount"], fallback: 0),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isDeleted: boolValue(data["isDeleted"], fallback: false),
            moderationStatus: ModerationStatus(rawValue: stringValue(data["moderationStatus"], fallback: ModerationStatus.active.rawValue)) ?? .active,
            hiddenReason: data["hiddenReason"] as? String,
            hiddenAt: optionalDateValue(data["hiddenAt"])
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
            isDeleted: boolValue(data["isDeleted"], fallback: false),
            moderationStatus: ModerationStatus(rawValue: stringValue(data["moderationStatus"], fallback: ModerationStatus.active.rawValue)) ?? .active,
            hiddenReason: data["hiddenReason"] as? String,
            hiddenAt: optionalDateValue(data["hiddenAt"])
        )
    }

    func mapMutedWord(_ document: QueryDocumentSnapshot) -> MutedWord? {
        let data = document.data()
        guard let userID = data["userID"] as? String,
              let word = data["word"] as? String else {
            return nil
        }

        let normalizedWord = stringValue(data["normalizedWord"], fallback: MutedWordNormalizer.normalize(word))
        guard !normalizedWord.isEmpty else { return nil }

        return MutedWord(
            id: document.documentID,
            userID: userID,
            word: word,
            normalizedWord: normalizedWord,
            createdAt: dateValue(data["createdAt"], fallback: Date())
        )
    }

    func mapTopicRoom(_ document: QueryDocumentSnapshot) -> TopicRoom? {
        let data = document.data()
        let topic = stringValue(data["topic"], fallback: document.documentID)
        guard !topic.isEmpty else { return nil }

        return TopicRoom(
            topic: topic,
            title: stringValue(data["title"], fallback: "#\(topic)"),
            description: stringValue(data["description"], fallback: ""),
            postCount: intValue(data["postCount"], fallback: 0),
            followerCount: intValue(data["followerCount"], fallback: 0),
            lastPostAt: optionalDateValue(data["lastPostAt"]),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isOfficial: boolValue(data["isOfficial"], fallback: false),
            moderationStatus: ModerationStatus(rawValue: stringValue(data["moderationStatus"], fallback: ModerationStatus.active.rawValue)) ?? .active
        )
    }

    func mapFeedControl(_ document: QueryDocumentSnapshot) -> FeedControl? {
        let data = document.data()
        guard let userID = data["userID"] as? String,
              let targetTypeRaw = data["targetType"] as? String,
              let targetType = FeedControlTargetType(rawValue: targetTypeRaw),
              let targetID = data["targetID"] as? String,
              let preferenceRaw = data["preference"] as? String,
              let preference = FeedControlPreference(rawValue: preferenceRaw),
              !targetID.isEmpty else {
            return nil
        }

        return FeedControl(
            id: document.documentID,
            userID: userID,
            targetType: targetType,
            targetID: targetID,
            preference: preference,
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date())
        )
    }

    func mapFollow(_ document: QueryDocumentSnapshot) -> FollowRecord? {
        let data = document.data()
        guard let followerID = data["followerID"] as? String,
              let followeeID = data["followeeID"] as? String,
              followerID != followeeID else {
            return nil
        }

        return FollowRecord(followerID: followerID, followeeID: followeeID)
    }

    func followState(
        from records: [FollowRecord],
        currentUserID: String
    ) -> (
        followingUserIDs: Set<String>,
        followerCountsByUserID: [String: Int],
        followingCountsByUserID: [String: Int],
        followersByUserID: [String: Set<String>],
        followingByUserID: [String: Set<String>]
    ) {
        var followersByUserID: [String: Set<String>] = [:]
        var followingByUserID: [String: Set<String>] = [:]

        for record in records {
            followingByUserID[record.followerID, default: []].insert(record.followeeID)
            followersByUserID[record.followeeID, default: []].insert(record.followerID)
        }

        return (
            followingUserIDs: followingByUserID[currentUserID, default: []],
            followerCountsByUserID: followersByUserID.mapValues { $0.count },
            followingCountsByUserID: followingByUserID.mapValues { $0.count },
            followersByUserID: followersByUserID,
            followingByUserID: followingByUserID
        )
    }

    func postMediaItems(from value: Any?) -> [PostMedia] {
        guard let rawItems = value as? [[String: Any]] else {
            return []
        }

        return rawItems.compactMap { item in
            guard let id = item["id"] as? String,
                  let typeValue = item["type"] as? String,
                  let type = PostMediaType(rawValue: typeValue),
                  let storagePath = item["storagePath"] as? String,
                  let downloadURL = item["downloadURL"] as? String else {
                return nil
            }

            return PostMedia(
                id: id,
                type: type,
                storagePath: storagePath,
                downloadURL: downloadURL,
                thumbnailURL: item["thumbnailURL"] as? String,
                width: intValue(item["width"], fallback: 0),
                height: intValue(item["height"], fallback: 0),
                durationMs: optionalIntValue(item["durationMs"]),
                sizeBytes: int64Value(item["sizeBytes"], fallback: 0),
                sortOrder: intValue(item["sortOrder"], fallback: 0)
            )
        }
        .sorted { $0.sortOrder < $1.sortOrder }
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
            status: stringValue(data["status"], fallback: "確認待ち"),
            reporterID: data["reporterID"] as? String,
            targetType: ReportTargetType(rawValue: stringValue(data["targetType"], fallback: ReportTargetType.other.rawValue)) ?? .other,
            targetID: nonEmptyString(data["targetID"]),
            targetOwnerID: nonEmptyString(data["targetOwnerID"]),
            adminNote: nonEmptyString(data["adminNote"]),
            resolvedAt: optionalDateValue(data["resolvedAt"]),
            resolvedBy: nonEmptyString(data["resolvedBy"])
        )
    }

    func mapNotification(_ document: QueryDocumentSnapshot) -> AppNotification? {
        let data = document.data()
        guard let typeValue = data["type"] as? String,
              let type = AppNotificationType(rawValue: typeValue),
              let recipientID = data["recipientID"] as? String,
              let actorID = data["actorID"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        return AppNotification(
            id: document.documentID,
            type: type,
            recipientID: recipientID,
            actorID: actorID,
            postID: nonEmptyString(data["postID"]),
            text: text,
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            isRead: boolValue(data["isRead"], fallback: false),
            readAt: optionalDateValue(data["readAt"])
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

    func optionalIntValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    func int64Value(_ value: Any?, fallback: Int64) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
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

    func optionalDateValue(_ value: Any?) -> Date? {
        if let value = value as? Timestamp {
            return value.dateValue()
        }
        if let value = value as? Date {
            return value
        }
        return nil
    }

    func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

}

// MARK: - Article

extension FirebaseDataStore {
    func saveArticle(_ article: Article) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("articles")
            .document(article.id)
            .setData(article.firestoreData, merge: true)
        #endif
    }

    func saveArticleBody(articleID: String, body: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("articleBodies")
            .document(articleID)
            .setData(["body": body], merge: true)
        #endif
    }

    func loadArticleBody(articleID: String) async throws -> String? {
        #if canImport(FirebaseFirestore)
        let doc = try await Firestore.firestore()
            .collection("articleBodies")
            .document(articleID)
            .getDocument()
        return doc.data()?["body"] as? String
        #else
        return nil
        #endif
    }

    func loadUserArticles(userID: String, limit: Int = 30) async throws -> [Article] {
        #if canImport(FirebaseFirestore)
        let snap = try await Firestore.firestore()
            .collection("articles")
            .whereField("userID", isEqualTo: userID)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap(mapArticle)
        #else
        return []
        #endif
    }

    func loadTimelineArticles(limit: Int = 30) async throws -> [Article] {
        #if canImport(FirebaseFirestore)
        let snap = try await Firestore.firestore()
            .collection("articles")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("status", isEqualTo: ArticleStatus.published.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap(mapArticle)
        #else
        return []
        #endif
    }

    func loadTopicArticles(topic: String, limit: Int = 30) async throws -> [Article] {
        #if canImport(FirebaseFirestore)
        let snap = try await Firestore.firestore()
            .collection("articles")
            .whereField("topics", arrayContains: topic)
            .whereField("isDeleted", isEqualTo: false)
            .whereField("status", isEqualTo: ArticleStatus.published.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap(mapArticle)
        #else
        return []
        #endif
    }

    func deleteArticle(articleID: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore()
            .collection("articles")
            .document(articleID)
            .updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        #endif
    }

    func searchArticles(query: String, limit: Int = 20) async throws -> [Article] {
        #if canImport(FirebaseFirestore)
        guard let token = PostSearchTokenizer.primaryToken(for: query) else { return [] }
        let snap = try await Firestore.firestore()
            .collection("articles")
            .whereField("searchTokens", arrayContains: token)
            .whereField("isDeleted", isEqualTo: false)
            .whereField("status", isEqualTo: ArticleStatus.published.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap(mapArticle)
        #else
        return []
        #endif
    }

    func recordArticleUnlock(userID: String, articleID: String, price: ArticlePrice, transactionID: String) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let docID = "\(userID)_\(articleID)"
        let unlockData: [String: Any] = [
            "userID": userID,
            "articleID": articleID,
            "price": price.rawValue,
            "transactionID": transactionID,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("articleUnlocks").document(docID).setData(unlockData, merge: false)
        try await db.collection("articles").document(articleID).updateData([
            "purchaseCount": FieldValue.increment(Int64(1))
        ])
        #endif
    }

    func loadArticleUnlockIDs(userID: String) async throws -> [String] {
        #if canImport(FirebaseFirestore)
        let snap = try await Firestore.firestore()
            .collection("articleUnlocks")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        return snap.documents.compactMap { $0.data()["articleID"] as? String }
        #else
        return []
        #endif
    }

    func mapArticle(_ document: QueryDocumentSnapshot) -> Article? {
        #if canImport(FirebaseFirestore)
        let data = document.data()
        guard let userID = data["userID"] as? String,
              let title = data["title"] as? String else { return nil }
        let freePreviewBody = data["freePreviewBody"] as? String ?? ""
        let combined = "\(title) \(freePreviewBody)"
        return Article(
            id: document.documentID,
            userID: userID,
            title: title,
            freePreviewBody: freePreviewBody,
            status: ArticleStatus(rawValue: stringValue(data["status"], fallback: ArticleStatus.published.rawValue)) ?? .published,
            price: ArticlePrice(rawValue: stringValue(data["price"], fallback: ArticlePrice.free.rawValue)) ?? .free,
            topics: data["topics"] as? [String] ?? TopicExtractor.topics(in: combined),
            searchTokens: data["searchTokens"] as? [String] ?? PostSearchTokenizer.tokens(in: combined, topics: []),
            commentPermission: CommentPermission(rawValue: stringValue(data["commentPermission"], fallback: CommentPermission.everyone.rawValue)) ?? .everyone,
            humanBadge: HumanBadge(rawValue: stringValue(data["humanBadge"], fallback: HumanBadge.checking.rawValue)) ?? .checking,
            humanScore: intValue(data["humanScore"], fallback: 0),
            inputDurationMs: intValue(data["inputDurationMs"], fallback: 0),
            editCount: intValue(data["editCount"], fallback: 0),
            deleteCount: intValue(data["deleteCount"], fallback: 0),
            commentCount: intValue(data["commentCount"], fallback: 0),
            purchaseCount: intValue(data["purchaseCount"], fallback: 0),
            bookmarkCount: intValue(data["bookmarkCount"], fallback: 0),
            createdAt: dateValue(data["createdAt"], fallback: Date()),
            updatedAt: dateValue(data["updatedAt"], fallback: Date()),
            isDeleted: boolValue(data["isDeleted"], fallback: false),
            moderationStatus: ModerationStatus(rawValue: stringValue(data["moderationStatus"], fallback: ModerationStatus.active.rawValue)) ?? .active,
            hiddenReason: data["hiddenReason"] as? String,
            hiddenAt: optionalDateValue(data["hiddenAt"])
        )
        #else
        return nil
        #endif
    }
}

private extension Post {
    var firestoreData: [String: Any] {
        [
            "userID": userId,
            "body": body,
            "topics": topics,
            "searchTokens": searchTokens,
            "mediaItems": mediaItems.map(\.firestoreData),
            "shareType": shareType.rawValue,
            "sourcePostID": sourcePostID ?? "",
            "sourceUserID": sourceUserID ?? "",
            "commentPermission": commentPermission.rawValue,
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
            "repostCount": repostCount,
            "quoteCount": quoteCount,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "isDeleted": isDeleted,
            "moderationStatus": moderationStatus.rawValue
        ]
    }
}

private extension PostMedia {
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "type": type.rawValue,
            "storagePath": storagePath,
            "downloadURL": downloadURL,
            "width": width,
            "height": height,
            "sizeBytes": sizeBytes,
            "sortOrder": sortOrder
        ]

        if let thumbnailURL {
            data["thumbnailURL"] = thumbnailURL
        }
        if let durationMs {
            data["durationMs"] = durationMs
        }

        return data
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
            "isDeleted": isDeleted,
            "moderationStatus": moderationStatus.rawValue
        ]
    }
}

private extension Article {
    var firestoreData: [String: Any] {
        [
            "userID": userID,
            "title": title,
            "freePreviewBody": freePreviewBody,
            "status": status.rawValue,
            "price": price.rawValue,
            "topics": topics,
            "searchTokens": searchTokens,
            "commentPermission": commentPermission.rawValue,
            "humanBadge": humanBadge.rawValue,
            "humanScore": humanScore,
            "inputDurationMs": inputDurationMs,
            "editCount": editCount,
            "deleteCount": deleteCount,
            "commentCount": commentCount,
            "purchaseCount": purchaseCount,
            "bookmarkCount": bookmarkCount,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "isDeleted": isDeleted,
            "moderationStatus": moderationStatus.rawValue
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
