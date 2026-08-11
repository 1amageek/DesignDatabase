public enum DesignDatabaseServiceWireTransportError:
  Error,
  Sendable,
  Equatable,
  Codable
{
  case closed
  case deadlineExceeded
  case invalidConfiguration(reason: String)
  case inputOutputFailure(reason: String)
  case invalidFrame(DesignDatabaseServiceWireCodecError)
  case protocolViolation(reason: String)
  case serializationFailure(reason: String)
}
