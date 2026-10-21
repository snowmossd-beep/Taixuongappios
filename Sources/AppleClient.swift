import Foundation

enum TErr: Error, LocalizedError {
    case bad
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .bad: return "Phản hồi không hợp lệ"
        case .msg(let m): return m
        }
    }
}

struct StoreItem {
    let url: URL
    let sinf: Data
    let metadata: [String: Any]
    let versionIDs: [Int]
    let shortVersion: String
}

final class AppleClient {
    private var dsid = ""
    private let guid: String

    init() {
        if let g = UserDefaults.standard.string(forKey: "guid") {
            guid = g
        } else {
            let g = (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined()
            UserDefaults.standard.set(g, forKey: "guid")
            guid = g
        }
    }

    private func post(_ url: URL, _ body: [String: Any], headers: [String: String] = [:]) async throws -> [String: Any] {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.httpBody = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0618.3.11.11.5", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let o = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { throw TErr.bad }
        return o
    }

    func login(_ id: String, _ password: String, _ code: String) async throws {
        let url = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast?guid=\(guid)")!
        let o = try await post(url, [
            "appleId": id,
            "attempt": code.isEmpty ? "4" : "2",
            "createSession": "true",
            "guid": guid,
            "password": password + code,
            "rmp": "0",
            "why": "signIn"
        ])
        guard let ds = o["dsPersonId"] as? String else {
            throw TErr.msg(o["customerMessage"] as? String ?? "Đăng nhập thất bại (nếu có 2FA: nhập mã rồi thử lại)")
        }
        dsid = ds
    }

    func lookup(id: String, country: String) async throws -> (bundle: String, name: String) {
        let u = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=\(country)")!
        let (d, _) = try await URLSession.shared.data(from: u)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (j["results"] as? [[String: Any]])?.first,
              let b = r["bundleId"] as? String else { throw TErr.msg("Không tìm thấy app") }
        return (b, r["trackName"] as? String ?? b)
    }

    func item(_ adam: String, version: Int? = nil) async throws -> StoreItem {
        let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(guid)")!
        var b: [String: Any] = ["creditDisplay": "", "guid": guid, "salableAdamId": adam]
        if let v = version { b["externalVersionId"] = String(v) }
        let o = try await post(url, b, headers: ["X-Dsid": dsid, "iCloud-DSID": dsid])
        guard let s = (o["songList"] as? [[String: Any]])?.first,
              let u = (s["URL"] as? String).flatMap(URL.init(string:)),
              let sinf = (s["sinfs"] as? [[String: Any]])?.first?["sinf"] as? Data,
              let m = s["metadata"] as? [String: Any] else {
            throw TErr.msg(o["customerMessage"] as? String ?? "Không lấy được link (app chưa có trong tài khoản?)")
        }
        let ids = (m["softwareVersionExternalIdentifiers"] as? [Any])?.compactMap { ($0 as? Int) ?? Int("\($0)") } ?? []
        return StoreItem(url: u, sinf: sinf, metadata: m, versionIDs: ids, shortVersion: m["bundleShortVersionString"] as? String ?? "")
    }
}
