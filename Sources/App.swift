import SwiftUI

@main
struct TipaGetApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct Found {
    let item: StoreItem
    let name: String
    let adam: String
}

struct ContentView: View {
    @AppStorage("apple") private var apple = ""
    @State private var pass = ""
    @State private var code = ""
    @State private var link = ""
    @State private var device = UIDevice.current.systemVersion
    @State private var found: Found?
    @State private var logs = ""
    @State private var busy = false
    @State private var loggedIn = false
    private let client = AppleClient()

    var body: some View {
        Form {
            if !loggedIn {
                Section("Apple ID") {
                    TextField("Email", text: $apple).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Mật khẩu", text: $pass)
                    TextField("Mã 2FA (nếu có)", text: $code).keyboardType(.numberPad)
                }
            }
            Section("Link App Store") {
                TextField("https://apps.apple.com/...", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Dán") { link = UIPasteboard.general.string ?? "" }
                Button(busy ? "Đang tìm..." : "Tìm bản hợp iOS \(device)") { search() }.disabled(busy || link.isEmpty)
            }
            if let f = found {
                Section(f.name) {
                    Text("Phiên bản \(f.item.shortVersion)")
                    HStack {
                        Button("Hủy", role: .cancel) { found = nil; logs = "" }
                        Spacer()
                        Button("Cài đặt") { install(f) }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text(logs).font(.footnote.monospaced())
        }
    }

    private func search() {
        guard let p = Service.parse(link) else { logs = "Link không hợp lệ"; return }
        busy = true
        logs = ""
        found = nil
        Task {
            do {
                if !loggedIn {
                    try await client.login(apple, pass, code)
                    loggedIn = true
                }
                let info = try await client.lookup(id: p.id, country: p.country)
                let it = try await Service.find(client: client, adam: p.id, device: device) { logs += $0 + "\n" }
                found = Found(item: it, name: info.name, adam: p.id)
            } catch {
                logs += error.localizedDescription
            }
            busy = false
        }
    }

    private func install(_ f: Found) {
        busy = true
        Task {
            do {
                logs += "Đang tải...\n"
                let ipa = try await Service.build(f.item, name: f.adam)
                logs += "Đang cài...\n"
                try await Installer.install(ipa)
                logs += "Xong"
                found = nil
            } catch {
                logs += error.localizedDescription
            }
            busy = false
        }
    }
}
