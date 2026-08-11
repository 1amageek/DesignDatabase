enum DesignDatabaseToken {
  static func validate(_ value: String, kind: String) throws(DesignDatabaseError) {
    guard !value.isEmpty else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value.first?.isWhitespace != true, value.last?.isWhitespace != true else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value.unicodeScalars.allSatisfy({
      $0.value >= 0x20 && !(0x7f...0x9f).contains($0.value)
    }) else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
    guard value.utf8.count <= 256 else {
      throw DesignDatabaseError.invalidToken(kind: kind, value: value)
    }
  }
}
