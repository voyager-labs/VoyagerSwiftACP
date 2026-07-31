package schema

import (
	"bytes"
	"fmt"
	"unicode/utf16"
	"unicode/utf8"
)

const maxJSONDepth = 512

type jsonKind uint8

const (
	jsonInvalid jsonKind = iota
	jsonObject
	jsonArray
	jsonString
	jsonNumber
	jsonBool
	jsonNull
)

type jsonMember struct {
	name  string
	value jsonValue
}

type jsonValue struct {
	kind    jsonKind
	members []jsonMember
	items   []jsonValue
	text    string
	boolean bool
}

type jsonParser struct {
	data  []byte
	index int
}

func parseJSON(data []byte) (jsonValue, error) {
	parser := jsonParser{data: data}
	parser.skipWhitespace()
	value, err := parser.parseValue(0)
	if err != nil {
		return jsonValue{}, err
	}
	parser.skipWhitespace()
	if parser.index != len(data) {
		return jsonValue{}, fmt.Errorf("unexpected data after JSON value")
	}
	return value, nil
}

func (parser *jsonParser) parseValue(depth int) (jsonValue, error) {
	if depth > maxJSONDepth {
		return jsonValue{}, fmt.Errorf("JSON nesting is too deep")
	}
	if parser.index >= len(parser.data) {
		return jsonValue{}, fmt.Errorf("unexpected end of JSON")
	}

	switch parser.data[parser.index] {
	case '{':
		return parser.parseObject(depth)
	case '[':
		return parser.parseArray(depth)
	case '"':
		text, err := parser.parseString()
		return jsonValue{kind: jsonString, text: text}, err
	case 't':
		if parser.consumeLiteral("true") {
			return jsonValue{kind: jsonBool, boolean: true}, nil
		}
	case 'f':
		if parser.consumeLiteral("false") {
			return jsonValue{kind: jsonBool}, nil
		}
	case 'n':
		if parser.consumeLiteral("null") {
			return jsonValue{kind: jsonNull}, nil
		}
	default:
		if parser.data[parser.index] == '-' || isDigit(parser.data[parser.index]) {
			return parser.parseNumber()
		}
	}
	return jsonValue{}, fmt.Errorf("invalid JSON value")
}

func (parser *jsonParser) parseObject(depth int) (jsonValue, error) {
	parser.index++
	parser.skipWhitespace()
	value := jsonValue{kind: jsonObject}
	if parser.consumeByte('}') {
		return value, nil
	}

	for {
		if parser.index >= len(parser.data) || parser.data[parser.index] != '"' {
			return jsonValue{}, fmt.Errorf("object key must be a string")
		}
		name, err := parser.parseString()
		if err != nil {
			return jsonValue{}, err
		}
		parser.skipWhitespace()
		if !parser.consumeByte(':') {
			return jsonValue{}, fmt.Errorf("object key is missing a value")
		}
		parser.skipWhitespace()
		memberValue, err := parser.parseValue(depth + 1)
		if err != nil {
			return jsonValue{}, err
		}
		value.members = append(value.members, jsonMember{name: name, value: memberValue})
		parser.skipWhitespace()
		if parser.consumeByte('}') {
			return value, nil
		}
		if !parser.consumeByte(',') {
			return jsonValue{}, fmt.Errorf("object members must be comma-separated")
		}
		parser.skipWhitespace()
	}
}

func (parser *jsonParser) parseArray(depth int) (jsonValue, error) {
	parser.index++
	parser.skipWhitespace()
	value := jsonValue{kind: jsonArray}
	if parser.consumeByte(']') {
		return value, nil
	}

	for {
		item, err := parser.parseValue(depth + 1)
		if err != nil {
			return jsonValue{}, err
		}
		value.items = append(value.items, item)
		parser.skipWhitespace()
		if parser.consumeByte(']') {
			return value, nil
		}
		if !parser.consumeByte(',') {
			return jsonValue{}, fmt.Errorf("array items must be comma-separated")
		}
		parser.skipWhitespace()
	}
}

func (parser *jsonParser) parseString() (string, error) {
	parser.index++
	var decoded bytes.Buffer

	for parser.index < len(parser.data) {
		current := parser.data[parser.index]
		switch {
		case current == '"':
			parser.index++
			return decoded.String(), nil
		case current == '\\':
			parser.index++
			if err := parser.parseEscape(&decoded); err != nil {
				return "", err
			}
		case current < 0x20:
			return "", fmt.Errorf("unescaped control character in string")
		case current < utf8.RuneSelf:
			decoded.WriteByte(current)
			parser.index++
		default:
			runeValue, size := utf8.DecodeRune(parser.data[parser.index:])
			if runeValue == utf8.RuneError && size == 1 {
				return "", fmt.Errorf("invalid UTF-8 in string")
			}
			decoded.Write(parser.data[parser.index : parser.index+size])
			parser.index += size
		}
	}
	return "", fmt.Errorf("unterminated string")
}

func (parser *jsonParser) parseEscape(decoded *bytes.Buffer) error {
	if parser.index >= len(parser.data) {
		return fmt.Errorf("unterminated string escape")
	}

	escaped := parser.data[parser.index]
	parser.index++
	switch escaped {
	case '"', '\\', '/':
		decoded.WriteByte(escaped)
	case 'b':
		decoded.WriteByte('\b')
	case 'f':
		decoded.WriteByte('\f')
	case 'n':
		decoded.WriteByte('\n')
	case 'r':
		decoded.WriteByte('\r')
	case 't':
		decoded.WriteByte('\t')
	case 'u':
		first, err := parser.parseHexRune()
		if err != nil {
			return err
		}
		switch {
		case utf16.IsSurrogate(first) && first >= 0xD800 && first <= 0xDBFF:
			if parser.index+2 > len(parser.data) || parser.data[parser.index] != '\\' || parser.data[parser.index+1] != 'u' {
				return fmt.Errorf("high surrogate is not paired")
			}
			parser.index += 2
			second, secondErr := parser.parseHexRune()
			if secondErr != nil || second < 0xDC00 || second > 0xDFFF {
				return fmt.Errorf("high surrogate is not followed by low surrogate")
			}
			decoded.WriteRune(utf16.DecodeRune(first, second))
		case utf16.IsSurrogate(first):
			return fmt.Errorf("unpaired low surrogate")
		default:
			decoded.WriteRune(first)
		}
	default:
		return fmt.Errorf("invalid string escape")
	}
	return nil
}

func (parser *jsonParser) parseHexRune() (rune, error) {
	if parser.index+4 > len(parser.data) {
		return 0, fmt.Errorf("incomplete Unicode escape")
	}
	var value rune
	for range 4 {
		digit, ok := hexValue(parser.data[parser.index])
		if !ok {
			return 0, fmt.Errorf("invalid Unicode escape")
		}
		value = value*16 + rune(digit)
		parser.index++
	}
	return value, nil
}

func (parser *jsonParser) parseNumber() (jsonValue, error) {
	start := parser.index
	parser.consumeByte('-')
	if parser.index >= len(parser.data) {
		return jsonValue{}, fmt.Errorf("incomplete number")
	}

	if parser.consumeByte('0') {
		if parser.index < len(parser.data) && isDigit(parser.data[parser.index]) {
			return jsonValue{}, fmt.Errorf("number has a leading zero")
		}
	} else {
		if !isDigitOneToNine(parser.data[parser.index]) {
			return jsonValue{}, fmt.Errorf("invalid number")
		}
		for parser.index < len(parser.data) && isDigit(parser.data[parser.index]) {
			parser.index++
		}
	}

	if parser.consumeByte('.') {
		if parser.index >= len(parser.data) || !isDigit(parser.data[parser.index]) {
			return jsonValue{}, fmt.Errorf("fraction has no digits")
		}
		for parser.index < len(parser.data) && isDigit(parser.data[parser.index]) {
			parser.index++
		}
	}

	if parser.index < len(parser.data) && (parser.data[parser.index] == 'e' || parser.data[parser.index] == 'E') {
		parser.index++
		if parser.index < len(parser.data) && (parser.data[parser.index] == '+' || parser.data[parser.index] == '-') {
			parser.index++
		}
		if parser.index >= len(parser.data) || !isDigit(parser.data[parser.index]) {
			return jsonValue{}, fmt.Errorf("exponent has no digits")
		}
		for parser.index < len(parser.data) && isDigit(parser.data[parser.index]) {
			parser.index++
		}
	}

	return jsonValue{kind: jsonNumber, text: string(parser.data[start:parser.index])}, nil
}

func (parser *jsonParser) skipWhitespace() {
	for parser.index < len(parser.data) {
		switch parser.data[parser.index] {
		case ' ', '\t', '\n', '\r':
			parser.index++
		default:
			return
		}
	}
}

func (parser *jsonParser) consumeByte(want byte) bool {
	if parser.index < len(parser.data) && parser.data[parser.index] == want {
		parser.index++
		return true
	}
	return false
}

func (parser *jsonParser) consumeLiteral(literal string) bool {
	if len(parser.data)-parser.index < len(literal) || string(parser.data[parser.index:parser.index+len(literal)]) != literal {
		return false
	}
	parser.index += len(literal)
	return true
}

func (value jsonValue) memberValues(name string) []jsonValue {
	var values []jsonValue
	for _, member := range value.members {
		if member.name == name {
			values = append(values, member.value)
		}
	}
	return values
}

func (value jsonValue) hasDuplicateObjectKey() bool {
	if value.kind == jsonObject {
		seen := make(map[string]struct{}, len(value.members))
		for _, member := range value.members {
			if _, exists := seen[member.name]; exists {
				return true
			}
			seen[member.name] = struct{}{}
			if member.value.hasDuplicateObjectKey() {
				return true
			}
		}
	}
	for _, item := range value.items {
		if item.hasDuplicateObjectKey() {
			return true
		}
	}
	return false
}

func objectFields(value jsonValue, names ...string) (map[string]jsonValue, bool) {
	if value.kind != jsonObject || value.hasDuplicateObjectKey() || len(value.members) != len(names) {
		return nil, false
	}
	allowed := make(map[string]struct{}, len(names))
	for _, name := range names {
		allowed[name] = struct{}{}
	}
	fields := make(map[string]jsonValue, len(names))
	for _, member := range value.members {
		if _, ok := allowed[member.name]; !ok {
			return nil, false
		}
		fields[member.name] = member.value
	}
	if len(fields) != len(names) {
		return nil, false
	}
	return fields, true
}

func isDigit(value byte) bool {
	return value >= '0' && value <= '9'
}

func isDigitOneToNine(value byte) bool {
	return value >= '1' && value <= '9'
}

func hexValue(value byte) (byte, bool) {
	switch {
	case value >= '0' && value <= '9':
		return value - '0', true
	case value >= 'a' && value <= 'f':
		return value - 'a' + 10, true
	case value >= 'A' && value <= 'F':
		return value - 'A' + 10, true
	default:
		return 0, false
	}
}
