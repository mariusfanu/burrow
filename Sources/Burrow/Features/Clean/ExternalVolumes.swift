import Foundation

/// The writable external volumes `mo clean --external` can work on.
enum ExternalVolumes {
    static func mounted() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsReadOnlyKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  isWritableExternalVolume(
                    path: url.path,
                    resolvedPath: url.resolvingSymlinksInPath().path,
                    isInternal: values.volumeIsInternal,
                    isReadOnly: values.volumeIsReadOnly,
                    isLocal: values.volumeIsLocal
                  ) else {
                return nil
            }
            return url.path
        }
    }

    static func isWritableExternalVolume(
        path: String,
        resolvedPath: String,
        isInternal: Bool?,
        isReadOnly: Bool?,
        isLocal: Bool?
    ) -> Bool {
        path.hasPrefix("/Volumes/")
            && resolvedPath != "/"
            && isInternal == false
            && isReadOnly == false
            && isLocal == true
    }
}
