public enum StorageError: Error, Equatable {
    case notFound
    /// Optimistic concurrency control: the saved revision is not the one that was edited.
    case conflict
}
