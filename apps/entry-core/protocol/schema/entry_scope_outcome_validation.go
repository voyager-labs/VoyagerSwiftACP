package schema

func validSourceOutcome(availability SourceAvailability, freshness SourceFreshness, warnings []Warning) bool {
	switch availability.State {
	case "available", "read_only":
		return freshness.State != "stale"
	case "stale":
		if freshness.State != "stale" {
			return false
		}
		for _, warning := range warnings {
			if warning.SourceInstanceID == availability.SourceInstanceID && warning.MountID == availability.MountID && (warning.Code == "stale_snapshot" || warning.Code == "source_offline") {
				return true
			}
		}
		return false
	case "loading", "offline", "permission_denied", "source_deleted", "unmounted", "error":
		return freshness.State == "unknown"
	default:
		return false
	}
}
