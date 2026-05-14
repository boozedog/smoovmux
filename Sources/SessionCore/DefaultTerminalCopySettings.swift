public struct DefaultTerminalCopySettings: Sendable {
  private let store: AppSettingsStore

  public init(store: AppSettingsStore = AppSettingsStore()) {
    self.store = store
  }

  public var cleanupEnabled: Bool {
    get {
      let settings = (try? store.load()) ?? AppSettings()
      return settings.cleanCopiedTerminalText
    }
    nonmutating set {
      var settings = (try? store.load()) ?? AppSettings()
      settings.cleanCopiedTerminalText = newValue
      try? store.save(settings)
    }
  }
}
