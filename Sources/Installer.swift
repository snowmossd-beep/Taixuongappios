import Foundation

enum Installer {
    private typealias Fn = @convention(c) (CFString, CFDictionary?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32

    static func install(_ ipa: URL) async throws {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_NOW),
              let s = dlsym(h, "MobileInstallationInstall") else { throw TErr.msg("Không load được MobileInstallation") }
        let f = unsafeBitCast(s, to: Fn.self)
        let path = ipa.path
        let code = await Task.detached { f(path as CFString, ["PackageType": "Customer"] as CFDictionary, nil, nil) }.value
        if code != 0 { throw TErr.msg("Cài thất bại, mã \(code)") }
    }
}
