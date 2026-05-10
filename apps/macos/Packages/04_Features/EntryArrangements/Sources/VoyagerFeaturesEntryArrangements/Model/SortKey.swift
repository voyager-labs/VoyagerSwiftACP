// Re-export only SortKey and SortOrder from VoyagerShared for backward compatibility.
// Other VoyagerShared symbols are NOT re-exported — consumers must import VoyagerShared directly.
import VoyagerShared

public typealias SortKey = VoyagerShared.SortKey
public typealias SortOrder = VoyagerShared.SortOrder
