// Package seeds는 커밋된 System Property Registry SQL seed와 typed metadata를
// 소유한다. SQL body는 (embed.go)로 embed되고 fresh-row count/digest metadata는
// (catalog_gen.go)로 생성된다. 이 파일은 daemon과 persistence가 startup에서
// 소비하는 typed SeedMetadata record와 Current() accessor를 정의한다. Runtime은
// Registry JSON을 읽지 않는다.
package seeds

import "crypto/sha256"

// SeedMetadata는 커밋된 full-state seed의 불변 metadata이다.
type SeedMetadata struct {
	// SeedOrdinal은 불변 seed ordinal(첫 full-state seed는 1)이다.
	SeedOrdinal int
	// SystemRegistryVersion은 seed가 투영된 System Registry version이다.
	SystemRegistryVersion string
	// SQLSHA256은 raw SQL body의 SHA-256이다.
	SQLSHA256 string
	// DatasetSHA256은 canonical workspace-independent dataset digest이다.
	DatasetSHA256 string
	// DefinitionCount / DescriptorCount / BindingCount / TermCount는 fresh-row count이다.
	DefinitionCount int
	DescriptorCount int
	BindingCount    int
	TermCount       int
	// SQLBody는 embedded seed SQL body이다.
	SQLBody string
}

// Current는 생성 상수와 embedded SQL body를 합친 seed metadata를 반환한다. SQL
// SHA-256은 embedded body에서 다시 계산하므로 runtime에서 항상 자기 일관적이다.
func Current() SeedMetadata {
	metadata := generatedSeedMetadata
	metadata.SQLBody = sqlBody
	metadata.SQLSHA256 = sha256Hex(sqlBody)
	return metadata
}

func sha256Hex(value string) string {
	sum := sha256.Sum256([]byte(value))
	const hexDigits = "0123456789abcdef"
	out := make([]byte, 64)
	for index, b := range sum {
		out[index*2] = hexDigits[b>>4]
		out[index*2+1] = hexDigits[b&0x0f]
	}
	return string(out)
}
