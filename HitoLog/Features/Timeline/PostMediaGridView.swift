import AVKit
import SwiftUI
import UIKit

struct PostMediaGridView: View {
    let mediaItems: [PostMedia]
    var isDetail = false
    @State private var playingMedia: PostMedia?
    @State private var viewerMedia: PostMedia?

    var body: some View {
        let orderedItems = mediaItems.sorted { $0.sortOrder < $1.sortOrder }
        let imageItems = orderedItems.filter { $0.type == .image }

        LazyVGrid(columns: columns(for: orderedItems.count), spacing: AppSpacing.sm) {
            ForEach(orderedItems) { item in
                PostMediaTile(media: item) {
                    if item.type == .video {
                        playingMedia = item
                    } else {
                        viewerMedia = item
                    }
                }
                .aspectRatio(aspectRatio(for: orderedItems.count), contentMode: .fit)
            }
        }
        .sheet(item: $playingMedia) { media in
            PostVideoPlayerSheet(media: media)
        }
        .fullScreenCover(item: $viewerMedia) { media in
            PostImageViewer(images: imageItems, initialMedia: media)
        }
    }

    private func columns(for count: Int) -> [GridItem] {
        if count == 1 {
            return [GridItem(.flexible(), spacing: AppSpacing.sm)]
        }

        return [
            GridItem(.flexible(), spacing: AppSpacing.sm),
            GridItem(.flexible(), spacing: AppSpacing.sm)
        ]
    }

    private func aspectRatio(for count: Int) -> CGFloat {
        count == 1 ? (isDetail ? 4 / 3 : 16 / 10) : 1
    }
}

private struct PostMediaTile: View {
    let media: PostMedia
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            tileContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.type == .video ? "動画を再生" : "写真を拡大")
    }

    private var tileContent: some View {
        ZStack {
            PostMediaImage(media: media)

            if media.type == .video {
                VStack {
                    Spacer()
                    HStack {
                        Label(durationText, systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(.black.opacity(0.58), in: Capsule())
                        Spacer()
                    }
                }
                .padding(AppSpacing.sm)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private var durationText: String {
        guard let durationMs = media.durationMs else { return "0:00" }
        let seconds = max(durationMs / 1_000, 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct PostMediaImage: View {
    let media: PostMedia
    @State private var remoteImage: UIImage?
    @State private var isLoadingRemoteImage = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppColor.surface

                if let image = imageFromDataURL(media.imageURLString) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if isLoadingRemoteImage {
                    ProgressView()
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: media.imageURLString) {
            await loadRemoteImageIfNeeded()
        }
    }

    private var placeholder: some View {
        Image(systemName: media.type == .video ? "film" : "photo")
            .font(.title3)
            .foregroundStyle(AppColor.textSecondary)
    }

    private func imageFromDataURL(_ value: String) -> UIImage? {
        PostImageLoading.imageFromDataURL(value)
    }

    @MainActor
    private func loadRemoteImageIfNeeded() async {
        guard remoteImage == nil, !isLoadingRemoteImage else { return }

        isLoadingRemoteImage = true
        defer { isLoadingRemoteImage = false }
        remoteImage = await PostImageLoading.loadImage(from: media.imageURLString)
    }
}

/// 画像のデコード／リモート取得を、グリッド表示と全画面ビューアで共有するためのヘルパー。
enum PostImageLoading {
    static func imageFromDataURL(_ value: String) -> UIImage? {
        guard value.hasPrefix("data:image"),
              let base64 = value.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(base64)) else {
            return nil
        }

        return UIImage(data: data)
    }

    /// data URL ならその場でデコードし、http(s) ならリトライ付きで取得する。
    static func loadImage(from value: String) async -> UIImage? {
        if let image = imageFromDataURL(value) {
            return image
        }

        guard let url = URL(string: value),
              url.scheme == "http" || url.scheme == "https" else {
            return nil
        }

        let retryDelays: [UInt64] = [250_000_000, 700_000_000]
        for attempt in 0...retryDelays.count {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }
                guard let image = UIImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return image
            } catch {
                guard attempt < retryDelays.count else { return nil }
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }
        return nil
    }
}

private struct PostVideoPlayerSheet: View {
    let media: PostMedia
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("動画を再生できません", systemImage: "film")
                }
            }
            .background(Color.black)
            .navigationTitle("動画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard let url = URL(string: media.downloadURL) else { return }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

/// 写真をタップしたときに開く全画面ビューア。複数枚はスワイプでページングできる。
private struct PostImageViewer: View {
    let images: [PostMedia]
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String

    init(images: [PostMedia], initialMedia: PostMedia) {
        self.images = images
        _selection = State(initialValue: initialMedia.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(images) { media in
                    ZoomableImage(media: media)
                        .tag(media.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(AppSpacing.md)
            .accessibilityLabel("閉じる")

            if images.count > 1, let index = images.firstIndex(where: { $0.id == selection }) {
                VStack {
                    Text("\(index + 1) / \(images.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.top, AppSpacing.md)
                    Spacer()
                }
            }
        }
        .statusBarHidden()
    }
}

/// ピンチでズーム、ダブルタップで拡大/縮小できる単一画像ビュー。
private struct ZoomableImage: View {
    let media: PostMedia
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnification(in: proxy.size))
                        .simultaneousGesture(scale > 1 ? dragGesture(in: proxy.size) : nil)
                        .onTapGesture(count: 2) {
                            toggleZoom()
                        }
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: media.id) {
            guard image == nil, !isLoading else { return }
            isLoading = true
            image = await PostImageLoading.loadImage(from: media.imageURLString)
            isLoading = false
        }
    }

    private func magnification(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale {
                    resetZoom()
                } else {
                    offset = clampedOffset(offset, in: size)
                    lastOffset = offset
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                offset = clampedOffset(offset, in: size)
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.snappy) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        withAnimation(.snappy) {
            scale = minScale
            lastScale = minScale
            offset = .zero
            lastOffset = .zero
        }
    }

    /// ズーム時に画像が画面外へ行き過ぎないよう移動量を制限する。
    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = max((size.width * scale - size.width) / 2, 0)
        let maxY = max((size.height * scale - size.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

/// 一覧カードなどで使う、固定サイズの正方形メディアサムネイル。
/// 写真・動画どちらも先頭フレーム／画像を読み込み、動画には再生バッジを重ねる。
struct MediaThumbnailView: View {
    let media: PostMedia
    var size: CGFloat = 72
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            AppColor.surface

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: media.type == .video ? "film" : "photo")
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
            }

            if media.type == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .task(id: media.imageURLString) {
            if image == nil {
                image = await PostImageLoading.loadImage(from: media.imageURLString)
            }
        }
    }
}

private extension PostMedia {
    var imageURLString: String {
        switch type {
        case .image:
            return downloadURL
        case .video:
            return thumbnailURL ?? downloadURL
        }
    }
}
