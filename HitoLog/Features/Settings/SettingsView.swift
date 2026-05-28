import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var pushService: PushNotificationService
    @EnvironmentObject private var analytics: AnalyticsService
    @AppStorage("hasCompletedInitialExperience") private var hasCompletedInitialExperience = true
    @State private var isShowingLogoutConfirmation = false
    @State private var isShowingDeleteConfirmation = false
    @State private var accountDeleteErrorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppSpacing.md) {
                    BrandIconView(size: 52)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("HitoLog")
                            .font(.headline)
                        Text(AppConstants.copy)
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }

            Section("アカウント") {
                NavigationLink {
                    ProfileEditView()
                } label: {
                    Label("プロフィール編集", systemImage: "person.crop.circle")
                }

                Button {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("通知") {
                Toggle(isOn: Binding(
                    get: { pushService.isNotificationsEnabled },
                    set: { isEnabled in
                        Task {
                            await pushService.setNotificationsEnabled(isEnabled)
                        }
                    }
                )) {
                    Label("コメント・いいね・フォロー", systemImage: "bell.badge")
                }

                if pushService.authorizationStatus == .denied {
                    Text("iOSの設定で通知がオフになっています。通知を受け取るには設定アプリから許可してください。")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Section("サポート") {
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("フィードバックを送る", systemImage: "bubble.left.and.bubble.right")
                }

                Button {
                    analytics.capture("app_review_requested", properties: [
                        "entry_point": "settings"
                    ])
                    AppReviewService.requestReview()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("アプリをレビュー", systemImage: "star.bubble")
                }
            }

            Section("プライバシー") {
                Toggle(isOn: Binding(
                    get: { analytics.isEnabled },
                    set: { analytics.setEnabled($0) }
                )) {
                    Label("利用状況の分析", systemImage: "chart.line.uptrend.xyaxis")
                }

                Text("画面表示や操作イベントをPostHogに送信し、改善に利用します。投稿本文やフィードバック本文は分析イベントに含めません。")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)

                #if DEBUG
                if !analytics.isConfigured {
                    Text("PostHogProjectTokenが未設定のため、現在は分析イベントを送信しません。")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                #endif
            }

            Section("表示") {
                NavigationLink {
                    FeedControlSettingsView()
                } label: {
                    Label("フィード設定", systemImage: "slider.horizontal.3")
                }
            }

            Section("安全") {
                if store.currentUser.isAdmin {
                    NavigationLink {
                        AdminReportManagementView()
                    } label: {
                        Label("通報管理", systemImage: "checkmark.shield")
                    }
                }

                NavigationLink {
                    UserManagementListView(mode: .blocked)
                } label: {
                    Label("ブロックしたユーザー", systemImage: "hand.raised")
                }

                NavigationLink {
                    UserManagementListView(mode: .muted)
                } label: {
                    Label("ミュートしたユーザー", systemImage: "speaker.slash")
                }

                NavigationLink {
                    MutedWordsView()
                } label: {
                    Label("ミュートワード", systemImage: "text.badge.xmark")
                }

                NavigationLink {
                    ReportHistoryView()
                } label: {
                    Label("通報履歴", systemImage: "exclamationmark.bubble")
                }
            }

            Section("アプリ") {
                #if DEBUG
                Toggle(isOn: Binding(
                    get: { store.isDemoDataVisible },
                    set: { isEnabled in
                        if isEnabled {
                            store.showScreenshotDemoData()
                        } else {
                            Task {
                                await store.hideScreenshotDemoData()
                            }
                        }
                    }
                )) {
                    Label("スクリーンショット用デモデータ", systemImage: "sparkles")
                }

                Text("オンにすると他ユーザー、投稿、コメントを端末内だけに表示します。Firebaseには保存しません。")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                #endif

                NavigationLink {
                    LegalDocumentView(title: "利用規約", bodyText: legalTermsText)
                } label: {
                    Label("利用規約", systemImage: "doc.text")
                }

                NavigationLink {
                    LegalDocumentView(title: "コミュニティガイドライン", bodyText: communityGuidelinesText)
                } label: {
                    Label("コミュニティガイドライン", systemImage: "checkmark.shield")
                }

                NavigationLink {
                    LegalDocumentView(title: "プライバシーポリシー", bodyText: privacyPolicyText)
                } label: {
                    Label("プライバシーポリシー", systemImage: "lock.doc")
                }
            }

            Section {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text("アカウント削除")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ログアウトしますか？", isPresented: $isShowingLogoutConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ログアウト", role: .destructive) {
                authSession.signOut()
                store.deactivateRemoteUser()
                hasCompletedInitialExperience = false
            }
        } message: {
            Text("この端末では初回画面に戻ります。")
        }
        .alert("アカウントを削除しますか？", isPresented: $isShowingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await store.deleteCurrentAccountData()
                        let didDelete = await authSession.deleteAccount()
                        if didDelete {
                            await MainActor.run {
                                store.resetLocalAccount()
                                hasCompletedInitialExperience = false
                            }
                        } else {
                            await MainActor.run {
                                accountDeleteErrorMessage = authSession.errorMessage ?? "アカウントを削除できませんでした。もう一度サインインしてからお試しください。"
                            }
                        }
                    } catch {
                        await MainActor.run {
                            accountDeleteErrorMessage = "アカウント情報を削除できませんでした。通信状態を確認して、もう一度お試しください。"
                        }
                    }
                }
            }
        } message: {
            Text("アカウント情報を削除し、この端末のローカル状態も初期化します。")
        }
        .alert("削除できません", isPresented: Binding(
            get: { accountDeleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    accountDeleteErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountDeleteErrorMessage ?? "")
        }
        .task {
            analytics.screen("settings")
            await pushService.refreshAuthorizationStatus()
        }
    }
}

private struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var category: AppFeedbackCategory = .usability
    @State private var message = ""
    @State private var allowsContact = false
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("種類") {
                Picker("種類", selection: $category) {
                    ForEach(AppFeedbackCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }
            }

            Section("内容") {
                TextField("気づいたことを入力", text: $message, axis: .vertical)
                    .lineLimit(6...12)

                HStack {
                    Text("\(message.count)/\(AppConstants.maxFeedbackLength)")
                    Spacer()
                    if !canSubmitMessage {
                        Text("5文字以上で入力してください")
                    }
                }
                .font(.caption)
                .foregroundStyle(canSubmitMessage || message.isEmpty ? AppColor.textSecondary : AppColor.warning)
            }

            Section("返信") {
                Toggle(isOn: $allowsContact) {
                    Label("メールで返信を受け取る", systemImage: "envelope")
                }
                .disabled(authSession.email == nil)

                if allowsContact, let email = authSession.email {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                } else if authSession.email == nil {
                    Text("返信を希望する場合は、メールアドレスを取得できるサインイン状態で送信してください。")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Section {
                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    if isSubmitting {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                            Text("送信中")
                        }
                    } else {
                        Label("送信", systemImage: "paperplane.fill")
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle("フィードバック")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            analytics.screen("feedback")
        }
        .alert("送信しました", isPresented: $didSubmit) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("フィードバックを受け付けました。")
        }
        .alert("送信できません", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "通信状態を確認して、もう一度お試しください。")
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitMessage: Bool {
        trimmedMessage.count >= 5 && trimmedMessage.count <= AppConstants.maxFeedbackLength
    }

    private var canSubmit: Bool {
        canSubmitMessage && !isSubmitting
    }

    private func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await store.submitFeedback(
                category: category,
                message: message,
                allowsContact: allowsContact,
                contactEmail: authSession.email
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            didSubmit = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = feedbackErrorMessage(for: error)
        }
    }

    private func feedbackErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("permission") {
            return "送信権限を確認できませんでした。アカウント状態を同期してから、もう一度お試しください。"
        }
        return message
    }
}

private struct ProfileEditView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var handle = ""
    @State private var bio = ""
    @State private var avatarDataURL: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarProcessingError: String?
    @State private var isShowingValidationError = false
    @State private var isSavingProfile = false
    @State private var profileSaveErrorMessage: String?
    @State private var hasEditedDisplayName = false
    @State private var hasEditedHandle = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppSpacing.md) {
                    AvatarView(user: previewUser, size: 56)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(previewUser.displayName)
                            .font(.headline)
                        Text("@\(previewUser.handle)")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }

            Section("プロフィール画像") {
                HStack(spacing: AppSpacing.md) {
                    AvatarView(user: previewUser, size: 72)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("写真を選択", systemImage: "photo")
                        }

                        Button(role: .destructive) {
                            avatarDataURL = nil
                            selectedPhotoItem = nil
                            avatarProcessingError = nil
                        } label: {
                            Label("画像を削除", systemImage: "trash")
                        }
                        .disabled(avatarDataURL == nil)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, AppSpacing.xs)

                if let avatarProcessingError {
                    ValidationMessage(
                        text: avatarProcessingError,
                        color: .red,
                        systemImage: "exclamationmark.circle.fill"
                    )
                }
            }

            Section("プロフィール") {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    TextField("表示名", text: $displayName)
                        .onChange(of: displayName) { _, _ in
                            hasEditedDisplayName = true
                        }

                    if hasEditedDisplayName && trimmedDisplayName.isEmpty {
                        ValidationMessage(
                            text: "表示名を入力してください。",
                            color: .red,
                            systemImage: "exclamationmark.circle.fill"
                        )
                    }
                }
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    TextField("ユーザーID", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: handle) { _, _ in
                            hasEditedHandle = true
                        }

                    ValidationMessage(
                        text: handleValidationText,
                        color: handleValidationColor,
                        systemImage: handleValidationIcon
                    )
                }
                TextField("自己紹介", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle("プロフィール編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSavingProfile ? "保存中" : "保存") {
                    Task {
                        await save()
                    }
                }
                .disabled(!canSave || isSavingProfile)
            }
        }
        .onAppear {
            displayName = store.currentUser.displayName
            handle = store.currentUser.handle
            bio = store.currentUser.bio
            avatarDataURL = store.currentUser.avatarUrl
        }
        .task(id: selectedPhotoItem) {
            await loadSelectedPhoto()
        }
        .alert("保存できません", isPresented: $isShowingValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("表示名とユーザーIDを確認してください。")
        }
        .alert("保存できません", isPresented: Binding(
            get: { profileSaveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    profileSaveErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(profileSaveErrorMessage ?? "通信状態を確認して、もう一度お試しください。")
        }
    }

    private func save() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else {
            isShowingValidationError = true
            return
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            try await store.updateCurrentUser(displayName: trimmedName, handle: trimmedHandle, bio: bio, avatarUrl: avatarDataURL)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            profileSaveErrorMessage = "プロフィールを保存できませんでした。通信状態を確認して、もう一度お試しください。"
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }

        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let dataURL = ProfileAvatarEncoder.dataURL(from: image) else {
                avatarProcessingError = "画像を読み込めませんでした。別の写真を選択してください。"
                return
            }

            avatarDataURL = dataURL
            avatarProcessingError = nil
        } catch {
            avatarProcessingError = "画像を読み込めませんでした。別の写真を選択してください。"
        }
    }

    private var canSave: Bool {
        !trimmedDisplayName.isEmpty && ValidationUtil.isValidHandle(trimmedHandle)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var handleValidationResult: ValidationUtil.HandleValidationResult {
        return ValidationUtil.validateHandle(trimmedHandle)
    }

    private var handleValidationText: String {
        if let message = handleValidationResult.message, hasEditedHandle {
            return message
        }
        return "3〜20文字の英数字とアンダースコアのみ使えます。"
    }

    private var handleValidationColor: Color {
        handleValidationResult == .valid || !hasEditedHandle ? AppColor.textSecondary : .red
    }

    private var handleValidationIcon: String {
        handleValidationResult == .valid || !hasEditedHandle ? "info.circle" : "exclamationmark.circle.fill"
    }

    private var previewUser: AppUser {
        var user = store.currentUser
        let previewName = trimmedDisplayName.isEmpty ? displayName : trimmedDisplayName
        let previewHandle = trimmedHandle.isEmpty ? handle : trimmedHandle
        user.displayName = previewName.isEmpty ? store.currentUser.displayName : previewName
        user.handle = previewHandle.isEmpty ? store.currentUser.handle : previewHandle
        user.avatarUrl = avatarDataURL
        return user
    }
}

private enum ProfileAvatarEncoder {
    private static let targetSize = CGSize(width: 256, height: 256)

    static func dataURL(from image: UIImage) -> String? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let renderedImage = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2
            )

            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        for quality in stride(from: 0.72, through: 0.46, by: -0.08) {
            guard let data = renderedImage.jpegData(compressionQuality: quality) else { continue }
            if data.count <= 300_000 {
                return "data:image/jpeg;base64,\(data.base64EncodedString())"
            }
        }

        guard let data = renderedImage.jpegData(compressionQuality: 0.4) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}

private struct ValidationMessage: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)

            Text(text)
                .font(.footnote)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum UserManagementMode {
    case blocked
    case muted

    var title: String {
        switch self {
        case .blocked:
            return "ブロックしたユーザー"
        case .muted:
            return "ミュートしたユーザー"
        }
    }

    var emptyText: String {
        switch self {
        case .blocked:
            return "ブロック中のユーザーはいません。"
        case .muted:
            return "ミュート中のユーザーはいません。"
        }
    }

    var activeButtonTitle: String {
        switch self {
        case .blocked:
            return "解除"
        case .muted:
            return "解除"
        }
    }

    var candidateButtonTitle: String {
        switch self {
        case .blocked:
            return "ブロック"
        case .muted:
            return "ミュート"
        }
    }
}

private struct UserManagementListView: View {
    @EnvironmentObject private var store: AppDataStore
    let mode: UserManagementMode

    var body: some View {
        List {
            Section(mode.title) {
                if activeUsers.isEmpty {
                    Text(mode.emptyText)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(activeUsers) { user in
                        ManagedUserRow(user: user, buttonTitle: mode.activeButtonTitle) {
                            remove(user)
                        }
                    }
                }
            }

            Section("追加候補") {
                if candidateUsers.isEmpty {
                    Text("追加できるユーザーはいません。")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(candidateUsers) { user in
                        ManagedUserRow(user: user, buttonTitle: mode.candidateButtonTitle) {
                            add(user)
                        }
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeUsers: [AppUser] {
        switch mode {
        case .blocked:
            return store.blockedUsers()
        case .muted:
            return store.mutedUsers()
        }
    }

    private var candidateUsers: [AppUser] {
        store.users.filter { user in
            user.id != store.currentUser.id && !activeUsers.contains(where: { $0.id == user.id })
        }
    }

    private func add(_ user: AppUser) {
        switch mode {
        case .blocked:
            store.block(user.id)
        case .muted:
            store.mute(user.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func remove(_ user: AppUser) {
        switch mode {
        case .blocked:
            store.unblock(user.id)
        case .muted:
            store.unmute(user.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct ManagedUserRow: View {
    let user: AppUser
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(user: user, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("@\(user.handle)")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

private struct FeedControlSettingsView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        Form {
            Section("おすすめの調整") {
                if store.feedControls.isEmpty {
                    Text("フィード設定はありません。")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(store.feedControls.sorted { $0.updatedAt > $1.updatedAt }) { control in
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(control.targetID)")
                                    .font(.subheadline.weight(.semibold))

                                Label(control.preference.displayText, systemImage: control.preference.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }

                            Spacer()

                            Button {
                                store.clearFeedControl(topic: control.targetID)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                }
            }
        }
        .navigationTitle("フィード設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MutedWordsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var word = ""

    var body: some View {
        Form {
            Section("追加") {
                HStack(spacing: AppSpacing.sm) {
                    TextField("単語または短いフレーズ", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("追加") {
                        addWord()
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(!canAdd)
                }

                Text("投稿本文、トピック、コメント本文に含まれる内容を非表示にします。大文字小文字と全角半角は最小限そろえて判定します。")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Section("登録済み") {
                if store.mutedWords.isEmpty {
                    Text("ミュートワードはありません。")
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(store.mutedWords) { mutedWord in
                        HStack(spacing: AppSpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mutedWord.word)
                                    .font(.subheadline.weight(.semibold))
                                Text("判定: \(mutedWord.normalizedWord)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                store.removeMutedWord(mutedWord)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                }
            }
        }
        .navigationTitle("ミュートワード")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canAdd: Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = MutedWordNormalizer.normalize(trimmed)
        return !trimmed.isEmpty
            && !normalized.isEmpty
            && trimmed.count <= AppConstants.maxMutedWordLength
            && !store.mutedWords.contains { $0.normalizedWord == normalized }
    }

    private func addWord() {
        guard canAdd else { return }
        store.addMutedWord(word)
        word = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct ReportHistoryView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
            if store.reportHistory.isEmpty {
                ContentUnavailableView("通報履歴はありません", systemImage: "exclamationmark.bubble")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.reportHistory) { report in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(report.targetDescription)
                            .font(.subheadline.weight(.semibold))
                        Text("理由: \(report.reason)")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Text("\(DateFormatterUtil.relativeString(from: report.createdAt)) ・ \(report.status)")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .navigationTitle("通報履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminReportManagementView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
            if store.adminReports.isEmpty {
                ContentUnavailableView("未対応の通報はありません", systemImage: "checkmark.shield")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.adminReports) { report in
                    AdminReportRow(report: report)
                }
            }
        }
        .navigationTitle("通報管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadAdminReports()
        }
        .refreshable {
            await store.loadAdminReports()
        }
    }
}

private struct AdminReportRow: View {
    @EnvironmentObject private var store: AppDataStore
    let report: ReportRecord

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Label(report.targetType.displayText, systemImage: report.targetType.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                Spacer()
                Text(report.status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(report.status == "確認待ち" ? AppColor.warning : AppColor.textSecondary)
            }

            Text(report.targetDescription)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("理由: \(report.reason)")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)

            Text("通報: \(DateFormatterUtil.relativeString(from: report.createdAt))")
                .font(.caption2)
                .foregroundStyle(AppColor.textTertiary)

            if let adminNote = report.adminNote {
                Text("メモ: \(adminNote)")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(spacing: AppSpacing.sm) {
                if report.targetType == .post || report.targetType == .comment {
                    Button(role: .destructive) {
                        Task {
                            await store.hideReportedContent(report)
                        }
                    } label: {
                        Label("非表示", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }

                if report.targetType == .user || report.targetOwnerID != nil {
                    Button(role: .destructive) {
                        Task {
                            await store.suspendReportedUser(report)
                        }
                    } label: {
                        Label("停止", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }

                Button {
                    Task {
                        await store.resolveReport(report, status: "対応済み", adminNote: "確認のみ")
                    }
                } label: {
                    Label("対応済み", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

private extension ReportTargetType {
    var systemImage: String {
        switch self {
        case .post:    return "text.bubble"
        case .comment: return "bubble.right"
        case .user:    return "person.crop.circle"
        case .article: return "doc.text"
        case .other:   return "exclamationmark.bubble"
        }
    }
}

private struct LegalDocumentView: View {
    let title: String
    let bodyText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(title)
                    .font(AppFont.title)
                Text(bodyText)
                    .font(AppFont.body)
                    .lineSpacing(5)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PaperCanvas())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private let legalTermsText = """
HitoLogは、本人がアプリ内で入力した言葉を投稿するためのSNSです。

ユーザーは、自分が投稿またはコメントする内容について責任を持つものとします。第三者の権利を侵害する内容、誹謗中傷、違法または不適切な内容、スパム行為、サービスの運営を妨げる行為は禁止します。

HitoLogでは、投稿、コメント、いいね、ブロック、ミュート、通報などの機能を提供します。運営上必要な場合、不適切な投稿やアカウントの表示制限、削除、利用停止を行うことがあります。

アカウント削除は設定画面から実行できます。削除すると、アカウント情報、投稿、コメント、通知トークンなどのユーザーデータは削除または非表示化されます。安全確認や法令対応のため、通報記録など一部の情報を必要な期間保持する場合があります。
"""

private let communityGuidelinesText = """
HitoLogでは、本人が入力した言葉を安心して読める場にするため、以下の行為を禁止します。

・誹謗中傷、脅迫、嫌がらせ、差別的な表現
・性的、暴力的、違法、または他者に危害を与える内容
・個人情報、なりすまし、権利侵害、無断転載
・スパム、過度な連投、サービスの安全性を損なう行為

問題のある投稿、コメント、ユーザーは通報できます。運営は通報内容を確認し、必要に応じて投稿やコメントの非表示、アカウントの利用制限を行います。
"""

private let privacyPolicyText = """
HitoLogは、アカウント作成、投稿、コメント、通知、安全機能を提供するために必要な情報を扱います。

収集する情報には、Sign in with AppleおよびFirebase Authのアカウント識別子、プロフィール情報、投稿、コメント、いいね、ブロック、ミュート、通報、投稿時の入力時間や編集回数などの入力指標、通知を有効にした場合のFirebase Cloud Messagingトークンが含まれます。

これらの情報は、タイムラインやプロフィールの表示、安全機能の提供、通報対応、コメントといいねの通知配信、サービスの保護のために利用します。通知トークンはHitoLogの通知配信にのみ利用します。

HitoLogはFirebase Auth、Cloud Firestore、App Check、Cloud Messaging、Cloud Functionsを利用します。収集したデータを販売することはありません。

ユーザーはアプリ内の設定から通知をオフにできます。また、設定画面からアカウント削除を実行できます。
"""
