import Foundation

/// The writable external volumes `mo clean --external` can work on.
enum ExternalVolumes {
    static func mounted() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard url.path.hasPrefix("/Volumes/"),
                  values?.volumeIsInternal != true,
                  values?.volumeIsReadOnly != true else {
                return nil
            }
            return url.path
        }
    }
}
