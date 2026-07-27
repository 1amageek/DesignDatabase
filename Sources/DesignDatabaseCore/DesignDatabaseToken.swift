import Foundation

enum DesignDatabaseToken {
  static func validate(_ value: String, kind: String) throws(DesignDatabaseError) {
    guard !value.isEmpty else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value.utf8.count <= 256 else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
  }
}
