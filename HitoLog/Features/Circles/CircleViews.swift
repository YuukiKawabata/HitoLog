import PhotosUI
import SwiftUI
import UIKit

struct WamoriMainTabView: View {
    @EnvironmentObject private var circles: CircleDataStore
    @State private var selectedTab: WamoriTab = .circles

    var body: some View {
        TabView(selection: $selectedTab) {
            CircleNavigationView()
                .tabItem { Label("輪", systemImage: "circle.grid.2x2") }
                .tag(WamoriTab.circles)

            NavigationStack { CircleWriteRouterView() }
                .tabItem { Label("書く", systemImage: "square.and.pencil") }
                .tag(WamoriTab.write)

            NavigationStack { WamoriSelfView() }
                .tabItem { Label("自分", systemImage: "person.crop.circle") }
                .tag(WamoriTab.selfTab)
        }
        .tint(AppColor.accent)
        .onChange(of: circles.pendingRoute) { _, route in
            if case .circle = route { selectedTab = .circles }
        }
    }
}

private enum WamoriTab { case circles, write, selfTab }

struct CircleNavigationView: View {
    @EnvironmentObject private var circles: CircleDataStore
    @State private var path: [WamoriCircle] = []

    var body: some View {
        NavigationStack(path: $path) {
            CircleListView()
                .navigationDestination(for: WamoriCircle.self) { CircleHomeView(circle: $0) }
        }
        .onChange(of: circles.pendingRoute) { _, _ in openPendingCircleIfAvailable() }
        .onChange(of: circles.circles) { _, _ in openPendingCircleIfAvailable() }
        .onAppear { openPendingCircleIfAvailable() }
    }

    private func openPendingCircleIfAvailable() {
        guard case .circle(let id) = circles.pendingRoute,
              let circle = circles.circles.first(where: { $0.id == id }) else { return }
        if path.last?.id != id { path.append(circle) }
        circles.clearPendingRoute()
    }
}

struct CircleListView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var isCreating = false
    @State private var inviteToken: String?

    var body: some View {
        Group {
            if circles.circles.isEmpty {
                ContentUnavailableView {
                    Label("まだ輪がありません", systemImage: "circle.dashed")
                } description: {
                    Text("大切な人と、今日をひとつずつ。")
                } actions: {
                    Button("輪をつくる") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                    Button("招待リンクから参加") {
                        if case .invite(let token) = circles.pendingRoute { inviteToken = token }
                    }
                    .disabled({ if case .invite = circles.pendingRoute { return false }; return true }())
                }
            } else {
                List {
                    Section {
                        ForEach(circles.circles) { circle in
                            NavigationLink(value: circle) { CircleListRow(circle: circle, entries: circles.entries(in: circle.id), userID: store.currentUser.id) }
                        }
                    }
                    Section {
                        Button { isCreating = true } label: { Label("新しい輪をつくる", systemImage: "plus.circle") }
                    }
                }
            }
        }
        .navigationTitle("Wamori")
        .sheet(isPresented: $isCreating) { CreateCircleView() }
        .sheet(item: Binding(
            get: { inviteToken.map(InviteTokenItem.init) },
            set: { if $0 == nil { inviteToken = nil } }
        )) { item in CircleInvitePreviewView(token: item.token) }
        .onAppear {
            analytics.screen("circle_list")
            if case .invite(let token) = circles.pendingRoute { inviteToken = token }
        }
        .onChange(of: circles.pendingRoute) { _, route in
            if case .invite(let token) = route { inviteToken = token }
        }
    }
}

private struct InviteTokenItem: Identifiable { let token: String; var id: String { token } }

private struct CircleListRow: View {
    let circle: WamoriCircle
    let entries: [CircleEntry]
    let userID: String

    var body: some View {
        HStack(spacing: 14) {
            Text(circle.emoji.isEmpty ? "◌" : circle.emoji).font(.largeTitle).frame(width: 48, height: 48).background(AppColor.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(circle.name).font(.headline)
                Text("\(circle.memberCount)人・今日 \(todayCount)件").font(.caption).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if didPostToday { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.accent).accessibilityLabel("今日の記録済み") }
        }
        .padding(.vertical, 4)
    }

    @EnvironmentObject private var circles: CircleDataStore
    private var todayCount: Int { entries.filter { $0.dateKey == circles.todayDateKey }.count }
    private var didPostToday: Bool { entries.contains { $0.dateKey == circles.todayDateKey && $0.authorID == userID } }
}

struct CreateCircleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var circles: CircleDataStore
    @State private var name = ""
    @State private var emoji = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("輪の名前") {
                    TextField("家族、いつもの3人…", text: $name).textInputAutocapitalization(.never)
                    Text("\(name.count)/30").font(.caption).foregroundStyle(name.count > 30 ? AppColor.warning : AppColor.textSecondary)
                }
                Section("絵文字（任意）") { TextField("🏠", text: $emoji) }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.warning) }
            }
            .navigationTitle("輪をつくる")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { create() }.disabled(!isValid || circles.isLoading)
                }
            }
        }
    }

    private var isValid: Bool {
        let count = name.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (1...30).contains(count) && emoji.count <= 1
    }

    private func create() {
        Task {
            do { _ = try await circles.createCircle(name: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct CircleHomeView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    @State private var isComposing = false
    @State private var createdInvite: CreatedCircleInvite?
    let circle: WamoriCircle

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日の問い").font(.caption.weight(.semibold)).foregroundStyle(AppColor.accent)
                    Text(circles.dailyPrompt).font(.title3.weight(.semibold))
                    Button(circles.todaysEntry(in: circle.id) == nil ? "今日を残す" : "今日の記録を編集") { isComposing = true }
                        .buttonStyle(.borderedProminent)
                }.padding(.vertical, 8)
            }
            Section("今日のみんな") {
                let today = todaysEntries
                if today.isEmpty { ContentUnavailableView("今日の記録はまだありません", systemImage: "sun.max") }
                else { ForEach(today) { CircleEntryRowView(entry: $0) } }
            }
            Section("過去の記録") {
                ForEach(pastEntries) { CircleEntryRowView(entry: $0) }
                if pastEntries.isEmpty { Text("記録が積み重なると、ここに表示されます。") .foregroundStyle(AppColor.textSecondary) }
            }
        }
        .navigationTitle(circle.displayTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if circle.ownerID == store.currentUser.id {
                        Button { createInvite() } label: { Label("招待リンクを作る", systemImage: "person.badge.plus") }
                        NavigationLink { CircleInviteManagementView(circle: circle) } label: { Label("招待を管理", systemImage: "link") }
                    }
                    NavigationLink { CircleMembersView(circle: circle) } label: { Label("メンバーと設定", systemImage: "person.2") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $isComposing) { ComposeCircleEntryView(circle: circle, editing: circles.todaysEntry(in: circle.id)) }
        .sheet(item: $createdInvite) { invite in
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: "link.circle.fill").font(.system(size: 56)).foregroundStyle(AppColor.accent)
                    Text("招待リンクができました").font(.title2.bold())
                    if let url = invite.shareURL { ShareLink(item: url, subject: Text("Wamoriへの招待"), message: Text("Wamoriの「\(circle.name)」に招待します。")) { Label("招待を送る", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent) }
                    Text("1回限り・7日間有効です。").font(.caption).foregroundStyle(AppColor.textSecondary)
                }.padding().navigationTitle("招待")
            }
        }
    }

    private var visibleEntries: [CircleEntry] {
        circles.entries(in: circle.id).filter {
            $0.moderationStatus == .active && !store.blockedUserIDs.contains($0.authorID) && !store.mutedUserIDs.contains($0.authorID)
        }
    }
    private var todaysEntries: [CircleEntry] { visibleEntries.filter { $0.dateKey == circles.todayDateKey } }
    private var pastEntries: [CircleEntry] { visibleEntries.filter { $0.dateKey != circles.todayDateKey } }
    private func createInvite() {
        Task {
            do { createdInvite = try await circles.createInvite(circleID: circle.id) }
            catch { circles.present(error) }
        }
    }
}

private struct CircleInviteManagementView: View {
    @EnvironmentObject private var circles: CircleDataStore
    let circle: WamoriCircle
    @State private var invites: [CircleInviteSummary] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if invites.isEmpty {
                ContentUnavailableView("有効な招待はありません", systemImage: "link")
            } else {
                ForEach(invites) { invite in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(invite.status == .active ? "有効" : "利用不可")
                            Text(invite.expiresAt, style: .relative).font(.caption).foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        if invite.status == .active {
                            Button("失効", role: .destructive) { revoke(invite) }
                        }
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.warning) }
        }
        .navigationTitle("招待を管理")
        .task { await load() }
    }

    private func load() async {
        do { invites = try await circles.listInvites(circleID: circle.id) }
        catch { errorMessage = error.localizedDescription }
    }

    private func revoke(_ invite: CircleInviteSummary) {
        Task {
            do { try await circles.revokeInvite(circleID: circle.id, inviteID: invite.id); await load() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

extension CreatedCircleInvite: Identifiable {}

struct CircleEntryRowView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    @EnvironmentObject private var flags: FeatureFlagService
    let entry: CircleEntry
    var showsCommentsLink = true
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.user(for: entry.authorID)?.displayName ?? "メンバー").font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.createdAt, style: .time).font(.caption).foregroundStyle(AppColor.textSecondary)
                Menu {
                    if entry.authorID == store.currentUser.id {
                        if entry.dateKey == circles.todayDateKey {
                            Button { isEditing = true } label: { Label("編集", systemImage: "pencil") }
                        }
                        Button(role: .destructive) { isConfirmingDelete = true } label: { Label("削除", systemImage: "trash") }
                    } else {
                        if store.mutedUserIDs.contains(entry.authorID) {
                            Button { store.unmute(entry.authorID) } label: { Label("ミュート解除", systemImage: "speaker.wave.2") }
                        } else {
                            Button { store.mute(entry.authorID) } label: { Label("ミュート", systemImage: "speaker.slash") }
                        }
                        if store.blockedUserIDs.contains(entry.authorID) {
                            Button { store.unblock(entry.authorID) } label: { Label("ブロック解除", systemImage: "hand.raised.slash") }
                        } else {
                            Button(role: .destructive) { store.block(entry.authorID) } label: { Label("ブロック", systemImage: "hand.raised") }
                        }
                        Button(role: .destructive) { reportEntry() } label: { Label("通報", systemImage: "exclamationmark.bubble") }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .accessibilityLabel("その他の操作")
            }
            if !entry.body.isEmpty { Text(entry.body).font(.body) }
            if let media = entry.mediaItems.first { CircleRemoteImage(path: media.storagePath) }
            HStack {
                if flags.enableCircleReactions {
                    ForEach(ReactionKind.allCases) { kind in
                        Button { react(kind) } label: {
                            Text("\(kind.emoji) \(entry.reactionCounts[kind.rawValue, default: 0])").font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .background(circles.viewerReactionByEntryID[entry.id] == kind ? AppColor.accentSoft : Color.clear, in: Capsule())
                        }.buttonStyle(.borderless).accessibilityLabel("\(kind.emoji) リアクション")
                    }
                }
                Spacer()
                if flags.enableCircleComments && showsCommentsLink {
                    NavigationLink {
                        CircleEntryDetailView(entry: entry)
                    } label: {
                        Label("\(entry.commentCount)", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear { if flags.enableCircleReactions { circles.listenToViewerReaction(for: entry) } }
        .onDisappear { circles.stopListeningToViewerReaction(entryID: entry.id) }
        .sheet(isPresented: $isEditing) {
            if let circle = circles.circles.first(where: { $0.id == entry.circleID }) {
                ComposeCircleEntryView(circle: circle, editing: entry)
            }
        }
        .confirmationDialog("この記録を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleteEntry() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("本文、写真、コメント、リアクションが削除され、元に戻せません。")
        }
        .alert("操作を完了できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func react(_ kind: ReactionKind) {
        Task { do { try await circles.setReaction(kind, entry: entry) } catch { errorMessage = error.localizedDescription } }
    }

    private func deleteEntry() {
        Task { do { try await circles.deleteEntry(entry) } catch { errorMessage = error.localizedDescription } }
    }

    private func reportEntry() {
        store.addReport(targetType: .circleEntry, targetID: "\(entry.circleID):\(entry.id)", targetOwnerID: entry.authorID,
                        targetDescription: "輪の記録", reason: "不適切な内容")
    }
}

private struct CircleRemoteImage: View {
    let path: String
    @State private var image: Image?
    var body: some View {
        Group {
            if let image { image.resizable().scaledToFill() }
            else { ZStack { AppColor.surface; ProgressView() }.task { if let data = try? await CircleMediaUploadService().imageData(path: path), let uiImage = UIImage(data: data) { image = Image(uiImage: uiImage) } } }
        }.frame(maxWidth: .infinity).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

struct ComposeCircleEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    @EnvironmentObject private var flags: FeatureFlagService
    let circle: WamoriCircle
    let editing: CircleEntry?
    @State private var bodyText: String
    @State private var metrics = TypingMetrics()
    @State private var aiAssisted = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var composeMedia: ComposeMediaItem?
    @State private var existingMedia: [CircleMedia]
    @State private var errorMessage: String?

    init(circle: WamoriCircle, editing: CircleEntry?) {
        self.circle = circle; self.editing = editing
        _bodyText = State(initialValue: editing?.body ?? "")
        _existingMedia = State(initialValue: editing?.mediaItems ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(circle.displayTitle).font(.headline)
                    Text("今日の問い").font(.caption.weight(.semibold)).foregroundStyle(AppColor.accent)
                    Text(circles.dailyPrompt).font(.title3.weight(.semibold))
                    ZStack(alignment: .topLeading) {
                        NoPasteTextViewRepresentable(text: $bodyText, onTextChanged: { old, new in metrics.recordChange(from: old, to: new, at: Date()); if new.count > 500 { bodyText = String(new.prefix(500)) } })
                        if bodyText.isEmpty { Text("今日のことを、自分の言葉で…").foregroundStyle(AppColor.placeholder).padding(12).allowsHitTesting(false) }
                    }.frame(minHeight: 200).background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                    HStack { Spacer(); Text("\(bodyText.count)/500").font(.caption).foregroundStyle(AppColor.textSecondary) }
                    if flags.enableCircleImages {
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label("写真を1枚追加", systemImage: "photo") }
                        if let preview = composeMedia?.previewImage {
                            Image(uiImage: preview).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                            Button("選択した写真を外す", role: .destructive) { composeMedia = nil; pickerItem = nil }
                        } else if let existing = existingMedia.first {
                            CircleRemoteImage(path: existing.storagePath)
                            Button("写真を外す", role: .destructive) { existingMedia = [] }
                        }
                    }
                    Toggle("AIを併用しました", isOn: $aiAssisted)
                    Text("この輪のメンバーだけに表示されます。").font(.caption).foregroundStyle(AppColor.textSecondary)
                    if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.warning) }
                }.padding()
            }
            .background(PaperCanvas())
            .navigationTitle(editing == nil ? "今日を残す" : "今日の記録を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(editing == nil ? "残す" : "保存") { submit() }.disabled(!isValid || circles.isLoading) }
            }
            .onChange(of: pickerItem) { _, item in guard let item else { return }; Task { composeMedia = try? await ComposeMediaItem.load(from: item) } }
        }
    }

    private var isValid: Bool {
        CircleEntryDraftValidator.isValid(body: bodyText, hasMedia: composeMedia != nil || !existingMedia.isEmpty)
    }
    private func submit() {
        Task {
            var uploadedMedia: CircleMedia?
            do {
                var media = existingMedia
                if let composeMedia {
                    let uploaded = try await CircleMediaUploadService().uploadImage(composeMedia, circleID: circle.id, userID: store.currentUser.id)
                    uploadedMedia = uploaded
                    media = [uploaded]
                }
                if let editing { try await circles.updateEntry(editing, body: bodyText, mediaItems: media, metrics: metrics, aiAssisted: aiAssisted) }
                else { try await circles.createEntry(circleID: circle.id, body: bodyText, mediaItems: media, metrics: metrics, aiAssisted: aiAssisted) }
                dismiss()
            } catch {
                if let uploadedMedia { await CircleMediaUploadService().deleteDraft(uploadedMedia) }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct CircleWriteRouterView: View {
    @EnvironmentObject private var circles: CircleDataStore
    @State private var isCreating = false
    @State private var isJoining = false
    var body: some View {
        Group {
            if circles.circles.isEmpty {
                ContentUnavailableView {
                    Label("投稿先の輪がありません", systemImage: "circle.dashed")
                } description: {
                    Text("輪をつくるか、届いた招待リンクから参加してください。")
                } actions: {
                    Button("輪をつくる") { isCreating = true }.buttonStyle(.borderedProminent)
                    Button("招待リンクから参加") { isJoining = true }
                }
            }
            else if let only = circles.circles.first, circles.circles.count == 1 { ComposeCircleEntryView(circle: only, editing: circles.todaysEntry(in: only.id)) }
            else { List(circles.circles) { circle in NavigationLink(circle.displayTitle) { ComposeCircleEntryView(circle: circle, editing: circles.todaysEntry(in: circle.id)) } }.navigationTitle("投稿先を選ぶ") }
        }
        .sheet(isPresented: $isCreating) { CreateCircleView() }
        .sheet(isPresented: $isJoining) { JoinCircleLinkView() }
    }
}

struct CircleInvitePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var circles: CircleDataStore
    let token: String
    @State private var preview: CircleInvitePreview?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let preview {
                    Text(preview.circleEmoji.isEmpty ? "◌" : preview.circleEmoji).font(.system(size: 64))
                    Text(preview.circleDisplayName).font(.title.bold())
                    Text("\(preview.ownerDisplayName)さんの輪・\(preview.memberCount)/\(preview.maxMembers)人").foregroundStyle(AppColor.textSecondary)
                    Button("この輪に参加する") { join() }.buttonStyle(.borderedProminent).disabled(preview.state != .active || circles.isLoading)
                    if preview.state != .active { Text(preview.state.unavailableMessage).font(.callout).foregroundStyle(AppColor.warning) }
                } else if let errorMessage { ContentUnavailableView("招待を開けません", systemImage: "link.badge.plus", description: Text(errorMessage)) }
                else { ProgressView("招待を確認しています") }
            }.padding().navigationTitle("Wamoriへの招待").task { await load() }
        }
    }
    private func load() async { do { preview = try await circles.previewInvite(token: token) } catch { errorMessage = error.localizedDescription } }
    private func join() { Task { do { _ = try await circles.joinCircle(token: token); dismiss() } catch { errorMessage = error.localizedDescription } } }
}

private extension CircleInviteState {
    var unavailableMessage: String {
        switch self {
        case .active: return ""
        case .expired: return "この招待リンクの期限は切れています。"
        case .used: return "この招待リンクはすでに使用されています。"
        case .full: return "この輪は定員に達しています。"
        case .invalid: return "この招待リンクは利用できません。"
        }
    }
}

private struct JoinCircleLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var circles: CircleDataStore
    @State private var link = ""
    @State private var token: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://hitolog-e22d2.web.app/c/…", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.warning) }
            }
            .navigationTitle("招待リンクから参加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("確認") { parse() }.disabled(link.isEmpty) }
            }
            .sheet(item: Binding(get: { token.map(InviteTokenItem.init) }, set: { if $0 == nil { token = nil } })) { item in
                CircleInvitePreviewView(token: item.token)
            }
        }
    }

    private func parse() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              case .invite(let parsedToken) = CircleInviteRouter().route(for: url) else {
            errorMessage = "Wamoriの招待リンクを入力してください。"
            return
        }
        token = parsedToken
    }
}

struct CircleEntryDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    let entry: CircleEntry
    @State private var commentText = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { CircleEntryRowView(entry: entry, showsCommentsLink: false) }
            Section("コメント") {
                ForEach(visibleComments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(store.user(for: comment.userID)?.displayName ?? "メンバー").font(.caption.weight(.semibold))
                            Spacer()
                            Text(comment.createdAt, style: .relative).font(.caption2).foregroundStyle(AppColor.textSecondary)
                        }
                        Text(comment.body)
                    }
                    .swipeActions {
                        if comment.userID == store.currentUser.id {
                            Button("削除", role: .destructive) { deleteComment(comment) }
                        } else {
                            Button("通報", role: .destructive) {
                                store.addReport(targetType: .circleComment, targetID: "\(comment.circleID):\(comment.entryID):\(comment.id)", targetOwnerID: comment.userID,
                                                targetDescription: "輪のコメント", reason: "不適切な内容")
                            }
                        }
                    }
                }
            }
            Section {
                TextField("コメントを書く", text: $commentText, axis: .vertical)
                    .lineLimit(1...5)
                    .onChange(of: commentText) { _, value in
                        if value.count > 500 { commentText = String(value.prefix(500)) }
                    }
                Button("送信") { submitComment() }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || circles.isLoading)
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(AppColor.warning) }
            }
        }
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { circles.listenToComments(for: entry) }
        .onDisappear { circles.stopListeningToComments(entryID: entry.id) }
    }

    private var visibleComments: [CircleComment] {
        circles.comments(for: entry.id).filter {
            $0.moderationStatus == .active && !store.blockedUserIDs.contains($0.userID) && !store.mutedUserIDs.contains($0.userID)
        }
    }

    private func deleteComment(_ comment: CircleComment) {
        Task { do { try await circles.deleteComment(comment) } catch { errorMessage = error.localizedDescription } }
    }

    private func submitComment() {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do { try await circles.createComment(body: body, entry: entry); commentText = "" }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct CircleMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var circles: CircleDataStore
    let circle: WamoriCircle
    @State private var isEditingCircle = false
    @State private var pendingAction: CircleMemberAction?
    @State private var errorMessage: String?
    var body: some View {
        List {
            if circle.ownerID == store.currentUser.id {
                Section { Button("輪の名前を編集") { isEditingCircle = true } }
            }
            Section("メンバー") {
                ForEach(circles.members(in: circle.id)) { member in
                    HStack {
                        Text(store.user(for: member.userID)?.displayName ?? "メンバー")
                        Spacer()
                        if member.role == .owner { Text("オーナー").font(.caption).foregroundStyle(AppColor.accent) }
                        else if circle.ownerID == store.currentUser.id {
                            Menu {
                                Button("オーナーを移譲") { pendingAction = .transfer(member.userID) }
                                Button("輪から外す", role: .destructive) { pendingAction = .remove(member.userID) }
                                Button("通報", role: .destructive) { reportMember(member.userID) }
                            } label: { Image(systemName: "ellipsis.circle") }
                        } else if member.userID != store.currentUser.id {
                            Menu {
                                Button(store.mutedUserIDs.contains(member.userID) ? "ミュート解除" : "ミュート") {
                                    if store.mutedUserIDs.contains(member.userID) { store.unmute(member.userID) } else { store.mute(member.userID) }
                                }
                                Button("通報", role: .destructive) { reportMember(member.userID) }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                }
            }
            Section {
                Button("この輪を通報", role: .destructive) {
                    store.addReport(targetType: .circle, targetID: circle.id, targetOwnerID: circle.ownerID,
                                    targetDescription: "輪", reason: "不適切な輪")
                }
                Button(circle.ownerID == store.currentUser.id ? "輪を削除" : "輪から退出", role: .destructive) {
                    pendingAction = circle.ownerID == store.currentUser.id ? .deleteCircle : .leave
                }
            }
        }
        .navigationTitle("メンバーと設定")
        .sheet(isPresented: $isEditingCircle) { EditCircleView(circle: circle) }
        .confirmationDialog(pendingAction?.title ?? "確認", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            if let action = pendingAction {
                Button(action.buttonTitle, role: action.isDestructive ? .destructive : nil) { perform(action) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text(pendingAction?.message ?? "") }
        .alert("操作を完了できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func reportMember(_ userID: String) {
        store.addReport(targetType: .circleMember, targetID: "\(circle.id):\(userID)", targetOwnerID: userID,
                        targetDescription: "輪のメンバー", reason: "不適切な行為")
    }

    private func perform(_ action: CircleMemberAction) {
        pendingAction = nil
        Task {
            do {
                switch action {
                case .transfer(let userID): try await circles.transferOwnership(of: circle, to: userID)
                case .remove(let userID): try await circles.removeMember(from: circle, userID: userID)
                case .leave: try await circles.leave(circle); dismiss()
                case .deleteCircle: try await circles.delete(circle); dismiss()
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum CircleMemberAction: Equatable {
    case transfer(String)
    case remove(String)
    case leave
    case deleteCircle

    var title: String {
        switch self {
        case .transfer: return "オーナーを移譲しますか？"
        case .remove: return "このメンバーを輪から外しますか？"
        case .leave: return "この輪から退出しますか？"
        case .deleteCircle: return "この輪を削除しますか？"
        }
    }
    var buttonTitle: String {
        switch self {
        case .transfer: return "移譲する"
        case .remove: return "外す"
        case .leave: return "退出する"
        case .deleteCircle: return "削除する"
        }
    }
    var message: String {
        switch self {
        case .transfer: return "移譲後は相手が輪の管理者になります。"
        case .remove: return "対象メンバーは輪の記録へ直ちにアクセスできなくなります。"
        case .leave: return "あなたの記録とコメントは輪から削除され、元に戻せません。"
        case .deleteCircle: return "輪の記録、写真、コメント、招待がすべて削除され、元に戻せません。"
        }
    }
    var isDestructive: Bool {
        switch self { case .transfer: return false; default: return true }
    }
}

private struct EditCircleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var circles: CircleDataStore
    let circle: WamoriCircle
    @State private var name: String
    @State private var emoji: String
    @State private var errorMessage: String?

    init(circle: WamoriCircle) {
        self.circle = circle
        _name = State(initialValue: circle.name)
        _emoji = State(initialValue: circle.emoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("輪の名前", text: $name)
                TextField("絵文字（任意）", text: $emoji)
                if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.warning) }
            }
            .navigationTitle("輪を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            do { try await circles.updateCircle(circle, name: name, emoji: emoji); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 30 || emoji.count > 1)
                }
            }
        }
    }
}

struct WamoriSelfView: View {
    @EnvironmentObject private var flags: FeatureFlagService
    @State private var isShowingPublicCompose = false
    var body: some View {
        List {
            Section {
                NavigationLink { ProfileView() } label: { Label("プロフィールと記録", systemImage: "person.crop.circle") }
                NavigationLink { NotificationsView() } label: { Label("通知", systemImage: "bell") }
                if flags.showLegacyPublicTimeline { NavigationLink { TimelineView { isShowingPublicCompose = true } } label: { Label("みんなの投稿", systemImage: "person.3") } }
                NavigationLink { SettingsView() } label: { Label("設定", systemImage: "gearshape") }
            }
        }.navigationTitle("自分").sheet(isPresented: $isShowingPublicCompose) { ComposePostView() }
    }
}
