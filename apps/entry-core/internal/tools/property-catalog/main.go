package propertycatalog

import (
	"flag"
	"fmt"
	"go/format"
	"os"
	"path/filepath"
)

// Options carries the explicit generator paths and mode.
type Options struct {
	SystemRegistryPath    string
	ConditionRegistryPath string
	SeedsDir              string
	ConditionOutPath      string
	Write                 bool
	Check                 bool
}

// Run executes the generator with the given arguments. It returns 0 on
// success, 1 on a mismatch under --check, and 2 on usage/validation errors.
func Run(args []string) int {
	var options Options
	flags := flag.NewFlagSet("property-catalog", flag.ContinueOnError)
	flags.StringVar(&options.SystemRegistryPath, "system-registry", "", "path to shared/system_property_registry.json")
	flags.StringVar(&options.ConditionRegistryPath, "condition-registry", "", "path to shared/property_condition_registry.json")
	flags.StringVar(&options.SeedsDir, "seeds-dir", "", "output directory for SQL seed and catalog_gen.go")
	flags.StringVar(&options.ConditionOutPath, "condition-out", "", "output path for property_condition_catalog_gen.go")
	flags.BoolVar(&options.Write, "write", false, "write generated outputs")
	flags.BoolVar(&options.Check, "check", false, "verify generated outputs without writing")
	if err := flags.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, "usage: property-catalog [--write|--check] --system-registry <path> --condition-registry <path> --seeds-dir <dir> --condition-out <path>")
		return 2
	}
	if err := options.Validate(); err != nil {
		fmt.Fprintln(os.Stderr, "property-catalog:", err)
		return 2
	}
	if options.Write && options.Check {
		fmt.Fprintln(os.Stderr, "property-catalog: --write and --check are mutually exclusive")
		return 2
	}
	// Default mode is side-effect-free check.
	write := options.Write
	if err := generate(options, write); err != nil {
		fmt.Fprintln(os.Stderr, "property-catalog:", err)
		return 1
	}
	return 0
}

// Validate checks that every explicit path is provided.
func (options Options) Validate() error {
	if options.SystemRegistryPath == "" {
		return fmt.Errorf("--system-registry is required")
	}
	if options.ConditionRegistryPath == "" {
		return fmt.Errorf("--condition-registry is required")
	}
	if options.SeedsDir == "" {
		return fmt.Errorf("--seeds-dir is required")
	}
	if options.ConditionOutPath == "" {
		return fmt.Errorf("--condition-out is required")
	}
	return nil
}

// Outputs is the set of generated artifacts.
type Outputs struct {
	SQLBody          string
	SQLPath          string
	CatalogGenBody   string
	CatalogGenPath   string
	ConditionGenBody string
	ConditionGenPath string
}

func generate(options Options, write bool) error {
	systemRegistry, err := LoadSystemRegistry(options.SystemRegistryPath)
	if err != nil {
		return err
	}
	projection, err := ProjectSystemRegistry(systemRegistry)
	if err != nil {
		return err
	}
	sqlBody, err := RenderSQL(projection)
	if err != nil {
		return err
	}

	conditionRegistry, err := LoadConditionRegistry(options.ConditionRegistryPath)
	if err != nil {
		return err
	}
	if err := validateConditionCounts(conditionRegistry); err != nil {
		return err
	}
	conditionBody, err := renderConditionCatalog(conditionRegistry)
	if err != nil {
		return err
	}
	conditionBody, err = formatGo(conditionBody)
	if err != nil {
		return err
	}
	catalogGenBody, err := renderCatalogGen(projection, sqlBody, systemRegistry)
	if err != nil {
		return err
	}
	catalogGenBody, err = formatGo(catalogGenBody)
	if err != nil {
		return err
	}

	outputs := Outputs{
		SQLBody:          sqlBody,
		SQLPath:          filepath.Join(options.SeedsDir, "0001_system_property_catalog_v2_4_1.sql"),
		CatalogGenBody:   catalogGenBody,
		CatalogGenPath:   filepath.Join(options.SeedsDir, "catalog_gen.go"),
		ConditionGenBody: conditionBody,
		ConditionGenPath: options.ConditionOutPath,
	}

	if write {
		return writeOutputs(outputs)
	}
	return checkOutputs(outputs)
}

func writeOutputs(outputs Outputs) error {
	if err := os.MkdirAll(filepath.Dir(outputs.SQLPath), 0o755); err != nil {
		return fmt.Errorf("create seeds dir: %w", err)
	}
	for _, file := range []struct {
		path string
		body string
	}{
		{outputs.SQLPath, outputs.SQLBody},
		{outputs.CatalogGenPath, outputs.CatalogGenBody},
		{outputs.ConditionGenPath, outputs.ConditionGenBody},
	} {
		if err := os.WriteFile(file.path, []byte(file.body), 0o644); err != nil {
			return fmt.Errorf("write %s: %w", file.path, err)
		}
	}
	return nil
}

func checkOutputs(outputs Outputs) error {
	for _, file := range []struct {
		path string
		body string
	}{
		{outputs.SQLPath, outputs.SQLBody},
		{outputs.CatalogGenPath, outputs.CatalogGenBody},
		{outputs.ConditionGenPath, outputs.ConditionGenBody},
	} {
		existing, err := os.ReadFile(file.path)
		if err != nil {
			return fmt.Errorf("missing output %s: %w (run --write)", file.path, err)
		}
		if string(existing) != file.body {
			return fmt.Errorf("stale output %s (run --write to regenerate)", file.path)
		}
	}
	return nil
}

// formatGo normalizes generated Go source so the committed file is gofmt-clean
// and byte-reproducible.
func formatGo(source string) (string, error) {
	formatted, err := format.Source([]byte(source))
	if err != nil {
		return "", fmt.Errorf("format generated Go: %w", err)
	}
	return string(formatted), nil
}
