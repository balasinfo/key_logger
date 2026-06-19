import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Identifies the Mac this build is running on, so reports from several machines
/// (e.g. emailed to the same address) can be told apart instead of being clubbed
/// together. Prefers the user-friendly computer name ("Devarsh's MacBook Pro"),
/// falling back to the network hostname with any `.local`/domain suffix trimmed.
public enum Machine {
    public static let name: String = {
        #if canImport(AppKit)
        if let n = Host.current().localizedName, !n.isEmpty { return n }
        #endif
        let h = ProcessInfo.processInfo.hostName
        return h.split(separator: ".").first.map(String.init) ?? h
    }()
}
