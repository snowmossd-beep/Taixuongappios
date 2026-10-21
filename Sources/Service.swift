import Foundation
import ZIPFoundation

enum Service {
    static func ok(_ minOS: String, _ device: String) -> Bool {
        minOS.compare(device, options: .numeric) != .orderedDescending
    }

    static func parse(_ s: String) -> (country: String, id: String)? {
        guard let r = s.range(of: #"id(\d+)"#, options: .regularExpression) else { return nil }
        let id = String(s[r].dropFirst(2))
        var c = "us"
        if let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
           let f = u.pathComponents.dropFirst().first, f.count == 2 { c = f.lowercased() }
        return (c, id)
    }

    static func find(client: AppleClient, adam: String, device: String, log: @escaping (String) -> Void) async throws -> StoreItem {
        let latest = try await client.item(adam)
        let m0 = try await RemoteZip.minOS(latest.url)
        log("Mới nhất \(latest.shortVersion) yêu cầu iOS \(m0)")
        if ok(m0, device) { return latest }
        for id in latest.versionIDs.reversed().prefix(60) {
            let it = try await client.item(adam, version: id)
            let m = try await RemoteZip.minOS(it.url)
            log("Thử \(it.shortVersion) (iOS \(m))")
            if ok(m, device) { return it }
        }
        throw TErr.msg("Không có bản nào hợp iOS \(device)")
    }

    static func build(_ it: StoreItem, name: String) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ipa = dir.appendingPathComponent("\(name)-\(it.shortVersion).ipa")
        let (tmp, _) = try await URLSession.shared.download(from: it.url)
        try FileManager.default.moveItem(at: tmp, to: ipa)

        let a = try Archive(url: ipa, accessMode: .update)
        guard let info = a.first(where: { $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/Info.plist") && $0.path.split(separator: "/").count == 3 }) else { throw TErr.bad }
        let appDir = String(info.path.dropLast("Info.plist".count))

        var sinfPath = "SC_Info/\(appDir.split(separator: "/")[1].dropLast(4)).sinf"
        if let man = a["\(appDir)SC_Info/Manifest.plist"] {
            var d = Data()
            _ = try a.extract(man) { d.append($0) }
            if let pl = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
               let p = (pl["SinfPaths"] as? [String])?.first { sinfPath = p }
        }
        try add(a, appDir + sinfPath, it.sinf)
        let meta = try PropertyListSerialization.data(fromPropertyList: it.metadata, format: .xml, options: 0)
        try add(a, "iTunesMetadata.plist", meta)
        return ipa
    }

    private static func add(_ a: Archive, _ path: String, _ data: Data) throws {
        if let old = a[path] { try a.remove(old) }
        try a.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { pos, size in
            data.subdata(in: Int(pos)..<Int(pos) + size)
        }
    }
}
