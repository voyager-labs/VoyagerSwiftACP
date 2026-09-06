package testfixture

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

const PlainText = "texts/plain/11.txt"

func CopyFile(t testing.TB, destinationPath, relativePath string) {
	t.Helper()
	_, sourceFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("locate shared fixture corpus")
	}
	sourcePath := filepath.Join(filepath.Dir(sourceFile), "..", "..", "..", "..", "fixtures", "fixtures", filepath.FromSlash(relativePath))
	content, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatalf("read shared fixture %q: %v; run git submodule update --init --recursive", sourcePath, err)
	}
	if err := os.WriteFile(destinationPath, content, 0o600); err != nil {
		t.Fatalf("copy shared fixture %q: %v", relativePath, err)
	}
}
