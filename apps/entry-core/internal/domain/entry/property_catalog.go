package entry

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"sort"
)

var (
	ErrInvalidSourcePropertyRef        = errors.New("invalid source property ref")
	ErrInvalidSourcePropertyDescriptor = errors.New("invalid source property descriptor")
	ErrInvalidPropertyBinding          = errors.New("invalid property binding")
	ErrInvalidWorkspacePropertyTerm    = errors.New("invalid workspace property term")
	ErrInvalidPropertyCatalogSnapshot  = errors.New("invalid property catalog snapshot")
)

// PropertyOrigin classifies how a Workspace Property definition was created.
// It is deliberately not used to infer the identity scheme: future curated
// presets may be Voyager-issued even when their origin is built-in.
type PropertyOrigin string

const (
	PropertyOriginBuiltIn     PropertyOrigin = "built_in"
	PropertyOriginUserDefined PropertyOrigin = "user_defined"
)

func (origin PropertyOrigin) valid() bool {
	switch origin {
	case PropertyOriginBuiltIn, PropertyOriginUserDefined:
		return true
	default:
		return false
	}
}

// AuthorityKind classifies the authority that owns a native Source Property.
// system and provider are kept separate so authority class is never conflated
// with a concrete provider identity.
type AuthorityKind string

const (
	AuthorityKindSystem   AuthorityKind = "system"
	AuthorityKindProvider AuthorityKind = "provider"
)

func (authority AuthorityKind) valid() bool {
	switch authority {
	case AuthorityKindSystem, AuthorityKindProvider:
		return true
	default:
		return false
	}
}

// SourceScopeKind classifies the scope that a Source Property is scoped to.
type SourceScopeKind string

const (
	SourceScopeKindSystem     SourceScopeKind = "system"
	SourceScopeKindWorkspace  SourceScopeKind = "workspace"
	SourceScopeKindRepository SourceScopeKind = "repository"
)

func (scope SourceScopeKind) valid() bool {
	switch scope {
	case SourceScopeKindSystem, SourceScopeKindWorkspace, SourceScopeKindRepository:
		return true
	default:
		return false
	}
}

// PropertyLifecycleState tracks the durable lifecycle of a catalog record.
// tombstoned preserves natural identity/history and forbids automatic retarget.
type PropertyLifecycleState string

const (
	PropertyLifecycleActive     PropertyLifecycleState = "active"
	PropertyLifecycleTombstoned PropertyLifecycleState = "tombstoned"
)

func (state PropertyLifecycleState) valid() bool {
	switch state {
	case PropertyLifecycleActive, PropertyLifecycleTombstoned:
		return true
	default:
		return false
	}
}

// SourcePropertyRef is a typed natural reference to a source/provider-owned
// native property. It is not a surrogate ID and never replaces a Workspace
// PropertyID. source_instance_id is the canonical src: identity.
type SourcePropertyRef struct {
	ProviderID         string
	SourceInstanceID   string
	ScopeKind          SourceScopeKind
	ScopeExternalID    string
	ExternalPropertyID string
}

func (ref SourcePropertyRef) Validate() error {
	if !validASCIIBytes(ref.ProviderID, 1, 64) || !isValidSourceID(ref.SourceInstanceID) ||
		!ref.ScopeKind.valid() || !validUTF8Bytes(ref.ScopeExternalID, 1, 128) ||
		!validUTF8Bytes(ref.ExternalPropertyID, 1, 256) {
		return ErrInvalidSourcePropertyRef
	}
	return nil
}

// logicalKey returns the deterministic sort key for the natural reference.
func (ref SourcePropertyRef) logicalKey() string {
	return ref.ProviderID + "\x00" + ref.SourceInstanceID + "\x00" + string(ref.ScopeKind) + "\x00" + ref.ScopeExternalID + "\x00" + ref.ExternalPropertyID
}

// SourcePropertyDescriptor declares a native source property and its source
// capability. Source declaration is not effective Voyager capability.
type SourcePropertyDescriptor struct {
	Ref               SourcePropertyRef
	NativeKey         string
	NativeType        string
	NativeCardinality PropertyCardinality
	Authority         AuthorityKind
	SourceReadable    bool
	SourceQueryable   bool
	SourceWritable    bool
	Lifecycle         PropertyLifecycleState
}

func (descriptor SourcePropertyDescriptor) Validate() error {
	if descriptor.Ref.Validate() != nil || !validUTF8Bytes(descriptor.NativeKey, 1, 256) ||
		!validUTF8Bytes(descriptor.NativeType, 1, 64) || !descriptor.NativeCardinality.valid() ||
		!descriptor.Authority.valid() || !descriptor.Lifecycle.valid() {
		return ErrInvalidSourcePropertyDescriptor
	}
	return nil
}

// PropertyBinding links a Workspace Property to a source natural reference and
// owns transform, precedence, and effective capability.
type PropertyBinding struct {
	PropertyID            PropertyID
	SourceRef             SourcePropertyRef
	BindingOrdinal        int
	ReadTransform         string
	Direction             string
	EffectiveReadable     bool
	EffectiveQueryable    bool
	EffectiveWritable     bool
	QueryProfile          string
	MappingVersion        int
	ValueContractRevision int
	Provenance            string
	ApprovalState         string
	Lossiness             string
	Lifecycle             PropertyLifecycleState
}

func (binding PropertyBinding) Validate() error {
	if !binding.PropertyID.valid() || binding.SourceRef.Validate() != nil ||
		binding.BindingOrdinal < 0 ||
		!validUTF8Bytes(binding.ReadTransform, 0, 128) || !validUTF8Bytes(binding.Direction, 0, 64) ||
		!validUTF8Bytes(binding.QueryProfile, 0, 64) || !validUTF8Bytes(binding.Provenance, 0, 128) ||
		!validUTF8Bytes(binding.ApprovalState, 0, 64) || !validUTF8Bytes(binding.Lossiness, 0, 64) ||
		binding.MappingVersion < 0 || binding.ValueContractRevision < 0 || !binding.Lifecycle.valid() {
		return ErrInvalidPropertyBinding
	}
	return nil
}

// logicalKey returns the deterministic sort key for the binding.
func (binding PropertyBinding) logicalKey() string {
	return binding.PropertyID.String() + "\x00" + binding.SourceRef.logicalKey()
}

// WorkspacePropertyTerm stores an ordered search/legacy alias for a Workspace
// Property. Native source keys are not terms; they live in SourcePropertyRef.
type WorkspacePropertyTerm struct {
	PropertyID PropertyID
	TermKind   string
	Ordinal    int
	TermValue  string
}

func (term WorkspacePropertyTerm) Validate() error {
	if !term.PropertyID.valid() || !validASCIIBytes(term.TermKind, 1, 64) ||
		term.Ordinal < 0 || !validUTF8Bytes(term.TermValue, 1, 256) {
		return ErrInvalidWorkspacePropertyTerm
	}
	return nil
}

// logicalKey returns the deterministic sort key for the term.
func (term WorkspacePropertyTerm) logicalKey() string {
	return term.PropertyID.String() + "\x00" + term.TermKind + "\x00" + string(rune(term.Ordinal))
}

// WorkspacePropertyDefinition is the catalog-level definition record carrying
// the stable seed-owned fields that participate in the dataset digest. It is a
// separate catalog value from the domain PropertyDefinition because the digest
// excludes runtime workspace_id/timestamps and includes origin/scheme.
type WorkspacePropertyDefinition struct {
	PropertyID     PropertyID
	Origin         PropertyOrigin
	IdentityScheme PropertyIdentityScheme
	Namespace      string
	CanonicalKey   string
	DisplayName    string
	ValueType      PropertyType
	Cardinality    PropertyCardinality
	Editable       bool
	Provenance     PropertyProvenance
	Unit           *string
	Lifecycle      PropertyLifecycleState
}

func (definition WorkspacePropertyDefinition) Validate() error {
	if !definition.PropertyID.valid() || !definition.Origin.valid() || !definition.IdentityScheme.valid() ||
		!validUTF8Bytes(definition.Namespace, 1, 128) || !validUTF8Bytes(definition.CanonicalKey, 1, 128) ||
		!validUTF8Bytes(definition.DisplayName, 1, 256) || !canonicalPropertyType(definition.ValueType) ||
		!definition.Cardinality.valid() || !definition.Provenance.valid() || !definition.Lifecycle.valid() {
		return ErrInvalidPropertyCatalogSnapshot
	}
	if definition.Unit != nil && !validUTF8Bytes(*definition.Unit, 1, 64) {
		return ErrInvalidPropertyCatalogSnapshot
	}
	return nil
}

// logicalKey returns the deterministic sort key for the definition.
func (definition WorkspacePropertyDefinition) logicalKey() string {
	return definition.PropertyID.String()
}

// PropertyCatalogSnapshot is the exact active-set seed snapshot whose stable
// fields are framed and hashed by Digest. It intentionally excludes runtime
// workspace_id, timestamps, and tombstoned history so every Workspace and every
// seed version yields the same digest for the same logical dataset.
type PropertyCatalogSnapshot struct {
	Definitions []WorkspacePropertyDefinition
	Descriptors []SourcePropertyDescriptor
	Bindings    []PropertyBinding
	Terms       []WorkspacePropertyTerm
}

func (snapshot PropertyCatalogSnapshot) Validate() error {
	seen := make(map[string]struct{})
	for _, definition := range snapshot.Definitions {
		if definition.Validate() != nil {
			return ErrInvalidPropertyCatalogSnapshot
		}
		key := "d:" + definition.logicalKey()
		if _, exists := seen[key]; exists {
			return ErrInvalidPropertyCatalogSnapshot
		}
		seen[key] = struct{}{}
	}
	for _, descriptor := range snapshot.Descriptors {
		if descriptor.Validate() != nil {
			return ErrInvalidPropertyCatalogSnapshot
		}
		key := "s:" + descriptor.Ref.logicalKey()
		if _, exists := seen[key]; exists {
			return ErrInvalidPropertyCatalogSnapshot
		}
		seen[key] = struct{}{}
	}
	for _, binding := range snapshot.Bindings {
		if binding.Validate() != nil {
			return ErrInvalidPropertyCatalogSnapshot
		}
		key := "b:" + binding.logicalKey()
		if _, exists := seen[key]; exists {
			return ErrInvalidPropertyCatalogSnapshot
		}
		seen[key] = struct{}{}
	}
	for _, term := range snapshot.Terms {
		if term.Validate() != nil {
			return ErrInvalidPropertyCatalogSnapshot
		}
		key := "t:" + term.logicalKey()
		if _, exists := seen[key]; exists {
			return ErrInvalidPropertyCatalogSnapshot
		}
		seen[key] = struct{}{}
	}
	return nil
}

// family tags for the digest framing.
const (
	digestFamilyDefinitions = 0x01
	digestFamilyDescriptors = 0x02
	digestFamilyBindings    = 0x03
	digestFamilyTerms       = 0x04
)

// frameField appends a uint64 big-endian length prefix followed by the bytes.
func frameField(buf *bytes.Buffer, value []byte) {
	var length [8]byte
	binary.BigEndian.PutUint64(length[:], uint64(len(value)))
	buf.Write(length[:])
	buf.Write(value)
}

func frameString(buf *bytes.Buffer, value string) { frameField(buf, []byte(value)) }

// Digest computes the canonical SHA-256 over every family sorted by logical
// key. Each family is introduced by a one-byte tag, then every record frames
// its stable fields in a fixed order as uint64 big-endian length+bytes. This
// is the single digest implementation; generator and persistence both call it.
func (snapshot PropertyCatalogSnapshot) Digest() ([32]byte, error) {
	if err := snapshot.Validate(); err != nil {
		return [32]byte{}, err
	}
	var buf bytes.Buffer
	hash := sha256.New()
	frameFamily := func(tag byte, fields ...[]byte) {
		buf.Reset()
		buf.WriteByte(tag)
		for _, field := range fields {
			frameField(&buf, field)
		}
		hash.Write(buf.Bytes())
	}
	definitions := append([]WorkspacePropertyDefinition(nil), snapshot.Definitions...)
	sort.Slice(definitions, func(i, j int) bool { return definitions[i].logicalKey() < definitions[j].logicalKey() })
	for _, definition := range definitions {
		unit := ""
		if definition.Unit != nil {
			unit = *definition.Unit
		}
		frameFamily(digestFamilyDefinitions,
			[]byte(definition.PropertyID.String()), []byte(definition.Origin), []byte(definition.IdentityScheme),
			[]byte(definition.Namespace), []byte(definition.CanonicalKey), []byte(definition.DisplayName),
			[]byte(definition.ValueType), []byte(definition.Cardinality), boolByte(definition.Editable),
			[]byte(definition.Provenance), []byte(unit), []byte(definition.Lifecycle),
		)
	}
	descriptors := append([]SourcePropertyDescriptor(nil), snapshot.Descriptors...)
	sort.Slice(descriptors, func(i, j int) bool { return descriptors[i].Ref.logicalKey() < descriptors[j].Ref.logicalKey() })
	for _, descriptor := range descriptors {
		frameFamily(digestFamilyDescriptors,
			[]byte(descriptor.Ref.logicalKey()), []byte(descriptor.NativeKey), []byte(descriptor.NativeType),
			[]byte(descriptor.NativeCardinality), []byte(descriptor.Authority),
			boolByte(descriptor.SourceReadable), boolByte(descriptor.SourceQueryable), boolByte(descriptor.SourceWritable),
			[]byte(descriptor.Lifecycle),
		)
	}
	bindings := append([]PropertyBinding(nil), snapshot.Bindings...)
	sort.Slice(bindings, func(i, j int) bool { return bindings[i].logicalKey() < bindings[j].logicalKey() })
	for _, binding := range bindings {
		frameFamily(digestFamilyBindings,
			[]byte(binding.logicalKey()), []byte(binding.ReadTransform), []byte(binding.Direction),
			boolByte(binding.EffectiveReadable), boolByte(binding.EffectiveQueryable), boolByte(binding.EffectiveWritable),
			[]byte(binding.QueryProfile), uint64Bytes(binding.MappingVersion), uint64Bytes(binding.ValueContractRevision),
			[]byte(binding.Provenance), []byte(binding.ApprovalState), []byte(binding.Lossiness), []byte(binding.Lifecycle),
		)
	}
	terms := append([]WorkspacePropertyTerm(nil), snapshot.Terms...)
	sort.Slice(terms, func(i, j int) bool { return terms[i].logicalKey() < terms[j].logicalKey() })
	for _, term := range terms {
		frameFamily(digestFamilyTerms,
			[]byte(term.logicalKey()), []byte(term.TermValue),
		)
	}
	var digest [32]byte
	copy(digest[:], hash.Sum(nil))
	return digest, nil
}

func boolByte(value bool) []byte {
	if value {
		return []byte{1}
	}
	return []byte{0}
}

func uint64Bytes(value int) []byte {
	var out [8]byte
	binary.BigEndian.PutUint64(out[:], uint64(value))
	return out[:]
}
