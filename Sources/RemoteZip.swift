import Foundation

private extension Data {
    func u16(_ o: Int) -> Int { Int(self[startIndex + o]) | Int(self[startIndex + o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
}

enum RemoteZip {
    private static func range(_ url: URL, _ a: Int, _ b: Int) async throws -> Data {
        var r = URLRequest(url: url)
        r.setValue("bytes=\(a)-\(b)", forHTTPHeaderField: "Range")
        let (d, _) = try await URLSession.shared.data(for: r)
        return d
    }

    private static func size(_ url: URL) async throws -> Int {
        var r = URLRequest(url: url)
        r.httpMethod = "HEAD"
        let (_, resp) = try await URLSession.shared.data(for: r)
        return Int(resp.expectedContentLength)
    }

    static func minOS(_ url: URL) async throws -> String {
        let total = try await size(url)
        let tailLen = min(65557, total)
        let tail = try await range(url, total - tailLen, total - 1)
        var e = -1
        var i = tail.count - 22
        while i >= 0 {
            if tail.u32(i) == 0x06054b50 { e = i; break }
            i -= 1
        }
        guard e >= 0 else { throw TErr.bad }
        let cdSize = tail.u32(e + 12)
        let cdOff = tail.u32(e + 16)
        let cd = try await range(url, cdOff, cdOff + cdSize - 1)
        var p = 0
        while p + 46 <= cd.count, cd.u32(p) == 0x02014b50 {
            let method = cd.u16(p + 10)
            let csize = cd.u32(p + 20)
            let nl = cd.u16(p + 28)
            let el = cd.u16(p + 30)
            let cl = cd.u16(p + 32)
            let lo = cd.u32(p + 42)
            let name = String(decoding: cd[(cd.startIndex + p + 46)..<(cd.startIndex + p + 46 + nl)], as: UTF8.self)
            if name.hasPrefix("Payload/"), name.hasSuffix(".app/Info.plist"), name.split(separator: "/").count == 3 {
                let lh = try await range(url, lo, lo + 29)
                let start = lo + 30 + lh.u16(26) + lh.u16(28)
                var data = try await range(url, start, start + csize - 1)
                if method == 8 { data = try (data as NSData).decompressed(using: .zlib) as Data }
                let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                return plist?["MinimumOSVersion"] as? String ?? "0"
            }
            p += 46 + nl + el + cl
        }
        throw TErr.bad
    }
}
