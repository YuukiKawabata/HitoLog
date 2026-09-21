import Foundation

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct CircleMediaUploadService {
    func uploadImage(_ item: ComposeMediaItem, circleID: String, userID: String) async throws -> CircleMedia {
        guard item.type == .image, let data = item.imageData else { throw MediaUploadError.invalidImage }
        guard Int64(data.count) <= AppConstants.maxCircleImageBytes else { throw MediaUploadError.imageTooLarge }
        #if canImport(FirebaseStorage)
        guard FirebaseBootstrap.isConfigured else { throw MediaUploadError.storageUnavailable }
        let mediaID = item.id
        let path = "circleMedia/\(circleID)/drafts/\(userID)/\(mediaID)-\(UUID().uuidString).jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
        return CircleMedia(id: mediaID, type: .image, storagePath: path, width: item.width, height: item.height, durationMs: nil, sizeBytes: Int64(data.count))
        #else
        throw MediaUploadError.storageUnavailable
        #endif
    }

    func deleteDraft(_ media: CircleMedia) async {
        #if canImport(FirebaseStorage)
        guard FirebaseBootstrap.isConfigured, media.storagePath.contains("/drafts/") else { return }
        try? await Storage.storage().reference(withPath: media.storagePath).delete()
        #endif
    }

    func imageData(path: String, maxSize: Int64 = AppConstants.maxCircleImageBytes) async throws -> Data {
        #if canImport(FirebaseStorage)
        guard FirebaseBootstrap.isConfigured else { throw MediaUploadError.storageUnavailable }
        return try await Storage.storage().reference(withPath: path).data(maxSize: maxSize)
        #else
        throw MediaUploadError.storageUnavailable
        #endif
    }
}
