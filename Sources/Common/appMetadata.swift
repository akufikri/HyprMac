/// The only place where the bundle identifier is spelled out. Both the debug and the release
/// identifiers, the Unix socket path and the Accessibility (TCC) database key derive from it.
private let releaseAppId: String = "dev.hypermac.HyperMac"
public let hyperMacAppIdRelease: String = releaseAppId

#if DEBUG
    public let hyperMacAppId: String = releaseAppId + ".debug"
    public let hyperMacAppName: String = "HyperMac-Debug"
#else
    public let hyperMacAppId: String = releaseAppId
    public let hyperMacAppName: String = "HyperMac"
#endif
