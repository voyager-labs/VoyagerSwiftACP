// Command property-catalog is a development/CI-only generator for the System
// Property Registry SQL seed and the compiled Condition Registry Go catalog.
// It is never linked into the daemon binary.
package main

import (
	"os"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/tools/property-catalog"
)

func main() {
	os.Exit(propertycatalog.Run(os.Args[1:]))
}
