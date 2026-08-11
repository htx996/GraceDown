import Foundation

#if canImport(IOKit)
import IOKit.ps
#endif

public protocol PowerSourceProviding: Sendable {
    func snapshots() throws -> [PowerSourceSnapshot]
}

public struct IOKitPowerSourceProvider: PowerSourceProviding, Sendable {
    public init() {}

    public func snapshots() throws -> [PowerSourceSnapshot] {
        #if canImport(IOKit)
        let powerSourcesInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue() as NSArray

        return powerSources.compactMap { source in
            guard
                let sourceDescription = IOPSGetPowerSourceDescription(powerSourcesInfo, source as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any]
            else {
                return nil
            }

            return PowerSourceSnapshot(dictionary: sourceDescription)
        }
        #else
        return []
        #endif
    }
}
