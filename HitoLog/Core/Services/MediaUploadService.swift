import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct ComposeMediaItem: Identifiable {
    let id: String
    let type: PostMediaType
    let imageData: Data?
    let videoURL: URL?
    let thumbnailData: Data?
    let previewImage: UIImage?
    let width: Int
    let height: Int
    let durationMs: Int?
    let sizeBytes: Int64

    static func load(from pickerItem: PhotosPickerItem) async throws -> ComposeMediaItem {
        if pickerItem.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
            return try await loadVideo(from: pickerItem)
        }

        return try await loadImage(from: pickerItem)
    }

    private static func loadImage(from pickerItem: PhotosPickerItem) async throws -> ComposeMediaItem {
        guard let data = try await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            throw MediaUploadError.unsupportedMedia
        }

        let renderedImage = image.resizedForPostMedia(maxDimension: AppConstants.maxPostImageDimension)
        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.82) else {
            throw MediaUploadError.invalidImage
        }

        return ComposeMediaItem(
            id: UUID().uuidString,
            type: .image,
            imageData: jpegData,
            videoURL: nil,
            thumbnailData: nil,
            previewImage: renderedImage,
            width: Int(renderedImage.size.width),
            height: Int(renderedImage.size.height),
            durationMs: nil,
            sizeBytes: Int64(jpegData.count)
        )
    }

    private static func loadVideo(from pickerItem: PhotosPickerItem) async throws -> ComposeMediaItem {
        guard let pickedVideo = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
            throw MediaUploadError.unsupportedMedia
        }

        let resourceValues = try pickedVideo.url.resourceValues(forKeys: [.fileSizeKey])
        let sizeBytes = Int64(resourceValues.fileSize ?? 0)
        guard sizeBytes <= AppConstants.maxPostVideoSizeBytes else {
            throw MediaUploadError.videoTooLarge
        }

        let asset = AVURLAsset(url: pickedVideo.url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds <= AppConstants.maxPostVideoDurationSeconds else {
            throw MediaUploadError.videoTooLong
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks.first?.load(.naturalSize) ?? .zero
        let transform = try await tracks.first?.load(.preferredTransform) ?? .identity
        let transformedSize = size.applying(transform)
        let width = Int(abs(transformedSize.width))
        let height = Int(abs(transformedSize.height))
        let thumbnail = try asset.thumbnailImage()
        let thumbnailData = thumbnail.jpegData(compressionQuality: 0.78)

        return ComposeMediaItem(
            id: UUID().uuidString,
            type: .video,
            imageData: nil,
            videoURL: pickedVideo.url,
            thumbnailData: thumbnailData,
            previewImage: thumbnail,
            width: width,
            height: height,
            durationMs: Int(durationSeconds * 1_000),
            sizeBytes: sizeBytes
        )
    }
}

struct MediaUploadService {
    var isAvailable: Bool {
        #if canImport(FirebaseStorage)
        FirebaseBootstrap.isConfigured
        #else
        false
        #endif
    }

    func upload(_ items: [ComposeMediaItem], userID: String, postID: String) async throws -> [PostMedia] {
        guard items.count <= AppConstants.maxPostMediaItems else {
            throw MediaUploadError.tooManyItems
        }

        #if canImport(FirebaseStorage)
        guard isAvailable else {
            throw MediaUploadError.storageUnavailable
        }

        var uploadedPaths: [String] = []

        do {
            var mediaItems: [PostMedia] = []
            for (index, item) in items.enumerated() {
                let mediaID = item.id
                let storagePath = "postMedia/\(userID)/\(postID)/\(mediaID).\(item.fileExtension)"
                let reference = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = item.contentType

                switch item.type {
                case .image:
                    guard let imageData = item.imageData else {
                        throw MediaUploadError.invalidImage
                    }
                    _ = try await reference.putDataAsync(imageData, metadata: metadata)
                case .video:
                    guard let videoURL = item.videoURL else {
                        throw MediaUploadError.unsupportedMedia
                    }
                    _ = try await reference.putFileAsync(from: videoURL, metadata: metadata)
                }

                uploadedPaths.append(storagePath)
                let downloadURL = try await stableDownloadURL(for: reference)
                let thumbnailURL = try await uploadThumbnailIfNeeded(
                    item: item,
                    userID: userID,
                    postID: postID,
                    mediaID: mediaID,
                    uploadedPaths: &uploadedPaths
                )

                mediaItems.append(
                    PostMedia(
                        id: mediaID,
                        type: item.type,
                        storagePath: storagePath,
                        downloadURL: downloadURL.absoluteString,
                        thumbnailURL: thumbnailURL?.absoluteString,
                        width: item.width,
                        height: item.height,
                        durationMs: item.durationMs,
                        sizeBytes: item.sizeBytes,
                        sortOrder: index
                    )
                )
            }

            return mediaItems
        } catch {
            await deleteUploadedFiles(paths: uploadedPaths)
            if let mediaError = error as? MediaUploadError {
                throw mediaError
            }
            throw storageUploadError(from: error)
        }
        #else
        throw MediaUploadError.storageUnavailable
        #endif
    }

    func localMediaItems(from items: [ComposeMediaItem]) throws -> [PostMedia] {
        guard items.count <= AppConstants.maxPostMediaItems else {
            throw MediaUploadError.tooManyItems
        }

        return try items.enumerated().map { index, item in
            let urlString: String
            let thumbnailURL: String?
            switch item.type {
            case .image:
                guard let imageData = item.imageData else {
                    throw MediaUploadError.invalidImage
                }
                urlString = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                thumbnailURL = nil
            case .video:
                guard let videoURL = item.videoURL else {
                    throw MediaUploadError.unsupportedMedia
                }
                urlString = videoURL.absoluteString
                if let thumbnailData = item.thumbnailData {
                    thumbnailURL = "data:image/jpeg;base64,\(thumbnailData.base64EncodedString())"
                } else {
                    thumbnailURL = nil
                }
            }

            return PostMedia(
                id: item.id,
                type: item.type,
                storagePath: "",
                downloadURL: urlString,
                thumbnailURL: thumbnailURL,
                width: item.width,
                height: item.height,
                durationMs: item.durationMs,
                sizeBytes: item.sizeBytes,
                sortOrder: index
            )
        }
    }
}

enum MediaUploadError: LocalizedError {
    case tooManyItems
    case unsupportedMedia
    case invalidImage
    case videoTooLarge
    case videoTooLong
    case storageUnavailable
    case storageBucketNotReady
    case storageUnauthenticated
    case storagePermissionDenied
    case storageQuotaExceeded
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .tooManyItems:
            return "写真と動画は最大\(AppConstants.maxPostMediaItems)件まで添付できます。"
        case .unsupportedMedia:
            return "このメディア形式は投稿できません。"
        case .invalidImage:
            return "画像を読み込めませんでした。別の写真を選んでください。"
        case .videoTooLarge:
            return "動画は100MB以下にしてください。"
        case .videoTooLong:
            return "動画は60秒以内にしてください。"
        case .storageUnavailable:
            return "メディア保存の準備ができていません。Firebase Storageの設定を確認してください。"
        case .storageBucketNotReady:
            return "Firebase Storageがまだセットアップされていません。Storageを有効化してからもう一度お試しください。"
        case .storageUnauthenticated:
            return "ログイン状態を確認できなかったため、写真/動画をアップロードできませんでした。再ログインしてください。"
        case .storagePermissionDenied:
            return "写真/動画を保存する権限がありません。Firebase StorageルールまたはApp Check設定を確認してください。"
        case .storageQuotaExceeded:
            return "Firebase Storageの容量または課金上限に達したため、写真/動画をアップロードできませんでした。"
        case .uploadFailed:
            return "写真/動画のアップロードに失敗しました。通信状態を確認してもう一度お試しください。"
        }
    }
}

private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return PickedVideo(url: copyURL)
        }
    }
}

private extension ComposeMediaItem {
    var fileExtension: String {
        switch type {
        case .image:
            return "jpg"
        case .video:
            return videoURL?.pathExtension.nonEmpty ?? "mov"
        }
    }

    var contentType: String {
        switch type {
        case .image:
            return "image/jpeg"
        case .video:
            guard let pathExtension = videoURL?.pathExtension,
                  let mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType else {
                return "video/quicktime"
            }
            return mimeType
        }
    }
}

private extension MediaUploadService {
    #if canImport(FirebaseStorage)
    func uploadThumbnailIfNeeded(
        item: ComposeMediaItem,
        userID: String,
        postID: String,
        mediaID: String,
        uploadedPaths: inout [String]
    ) async throws -> URL? {
        guard item.type == .video, let thumbnailData = item.thumbnailData else {
            return nil
        }

        let thumbnailPath = "postMedia/\(userID)/\(postID)/thumbs/\(mediaID).jpg"
        let reference = Storage.storage().reference(withPath: thumbnailPath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await reference.putDataAsync(thumbnailData, metadata: metadata)
        uploadedPaths.append(thumbnailPath)
        return try await stableDownloadURL(for: reference)
    }

    func stableDownloadURL(for reference: StorageReference) async throws -> URL {
        let retryDelays: [UInt64] = [
            150_000_000,
            300_000_000,
            600_000_000
        ]

        var lastError: Error?
        for attempt in 0...retryDelays.count {
            do {
                return try await reference.downloadURL()
            } catch {
                lastError = error
                guard attempt < retryDelays.count else { break }
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }

        throw lastError ?? MediaUploadError.uploadFailed
    }

    func deleteUploadedFiles(paths: [String]) async {
        for path in paths {
            let reference = Storage.storage().reference(withPath: path)
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                reference.delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func storageUploadError(from error: Error) -> MediaUploadError {
        let nsError = error as NSError
        #if DEBUG
        print("Media upload failed: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        #endif

        guard nsError.domain == StorageErrorDomain,
              let code = StorageErrorCode(rawValue: nsError.code) else {
            return .uploadFailed
        }

        switch code {
        case .bucketNotFound, .projectNotFound, .bucketMismatch:
            return .storageBucketNotReady
        case .unauthenticated:
            return .storageUnauthenticated
        case .unauthorized:
            return .storagePermissionDenied
        case .quotaExceeded:
            return .storageQuotaExceeded
        default:
            return .uploadFailed
        }
    }
    #endif
}

private extension AVURLAsset {
    func thumbnailImage() throws -> UIImage {
        let generator = AVAssetImageGenerator(asset: self)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cgImage)
    }
}

private extension UIImage {
    func resizedForPostMedia(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
