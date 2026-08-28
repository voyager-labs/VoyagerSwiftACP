package localfs

import (
	"io/fs"
	"reflect"
	"unicode/utf8"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

type LocalSourceNamespace struct {
	Namespace string
	Strength  entry.IdentityStrength
}

func (namespace LocalSourceNamespace) Validate() error {
	if !utf8.ValidString(namespace.Namespace) || len(namespace.Namespace) < 1 || len(namespace.Namespace) > 4096 {
		return source.ErrInvalidConfig
	}
	if namespace.Strength != entry.IdentityStrengthObjectLifetime && namespace.Strength != entry.IdentityStrengthStable {
		return source.ErrInvalidConfig
	}
	return nil
}

type LocalSourceNamespaceProvider interface {
	SourceNamespace(root string) (LocalSourceNamespace, error)
}

func normalizeSourceNamespaceProvider(provider LocalSourceNamespaceProvider) LocalSourceNamespaceProvider {
	if provider == nil {
		return nil
	}
	value := reflect.ValueOf(provider)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		if value.IsNil() {
			return nil
		}
	}
	return provider
}

type ObjectIdentity struct {
	ObjectKey string
	Strength  entry.IdentityStrength
}

func (identity ObjectIdentity) Validate() error {
	if !utf8.ValidString(identity.ObjectKey) || len(identity.ObjectKey) < 1 || len(identity.ObjectKey) > 4096 {
		return source.ErrAdapterFailure
	}
	switch identity.Strength {
	case entry.IdentityStrengthStable, entry.IdentityStrengthObjectLifetime, entry.IdentityStrengthLocator, entry.IdentityStrengthEphemeral:
		return nil
	default:
		return source.ErrAdapterFailure
	}
}

type ObjectIdentityProvider interface {
	Identify(relativePath string, info fs.FileInfo) (ObjectIdentity, error)
}

// genericPathIdentityProvider intentionally makes no restart, rename, move, or replacement guarantee.
type genericPathIdentityProvider struct{}

func (genericPathIdentityProvider) Identify(relativePath string, _ fs.FileInfo) (ObjectIdentity, error) {
	identity := ObjectIdentity{ObjectKey: relativePath, Strength: entry.IdentityStrengthLocator}
	if !source.ValidateRelativePath(relativePath) || relativePath == "" || identity.Validate() != nil {
		return ObjectIdentity{}, source.ErrAdapterFailure
	}
	return identity, nil
}

func normalizeIdentityProvider(provider ObjectIdentityProvider) ObjectIdentityProvider {
	if provider == nil {
		return genericPathIdentityProvider{}
	}
	value := reflect.ValueOf(provider)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		if value.IsNil() {
			return genericPathIdentityProvider{}
		}
	}
	return provider
}
