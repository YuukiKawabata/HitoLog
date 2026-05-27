import AVKit
import SwiftUI
import UIKit

struct PostMediaGridView: View {
    let mediaItems: [PostMedia]
    var isDetail = false
    @State private var playingMedia: PostMedia?

    var body: some View {
        let orderedItems = mediaItems.sorted { $0.sortOrder < $1.sortOrder }

        LazyVGrid(columns: columns(for: orderedItems.count), spacing: AppSpacing.sm) {
            ForEach(orderedItems) { item in
                PostMediaTile(media: item) {
                    if item.type == .video {
                        playingMedia = item
                    }
                }
                .aspectRatio(aspectRatio(for: orderedItems.count), contentMode: .fit)
            }
        }
        .sheet(item: $playingMedia) { media in
            PostVideoPlayerSheet(media: media)
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
        if media.type == .video {
            Button(action: onTap) {
                tileContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("動画を再生")
        } else {
            tileContent
                .accessibilityLabel("写真")
        }
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
        guard value.hasPrefix("data:image"),
              let base64 = value.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(base64)) else {
            return nil
        }

        return UIImage(data: data)
    }

    @MainActor
    private func loadRemoteImageIfNeeded() async {
        guard remoteImage == nil,
              !isLoadingRemoteImage,
              imageFromDataURL(media.imageURLString) == nil,
              let url = URL(string: media.imageURLString),
              url.scheme == "http" || url.scheme == "https" else {
            return
        }

        isLoadingRemoteImage = true
        defer { isLoadingRemoteImage = false }

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
                remoteImage = image
                return
            } catch {
                guard attempt < retryDelays.count else {
                    return
                }
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }
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
