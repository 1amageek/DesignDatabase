import DesignDatabaseCorePortabilityProbeSupport

@main
struct DesignDatabaseEmbeddedCorePortabilityProbe {
  static func main() throws {
    print(try DesignDatabaseCorePortabilityProbeOutput.make())
  }
}
