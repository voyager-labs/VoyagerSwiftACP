package schema

import domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"

func validCapabilitiesForAvailability(value Capabilities, availability string) bool {
	capabilities := domainentry.Capabilities{
		Readable:         value.Readable,
		Writable:         value.Writable,
		Searchable:       value.Searchable,
		Commentable:      value.Commentable,
		Movable:          value.Movable,
		Copyable:         value.Copyable,
		Deletable:        value.Deletable,
		Watchable:        value.Watchable,
		Streamable:       value.Streamable,
		RequiresApproval: value.RequiresApproval,
	}
	return capabilities.ValidateForAvailability(domainentry.AvailabilityState(availability)) == nil
}
