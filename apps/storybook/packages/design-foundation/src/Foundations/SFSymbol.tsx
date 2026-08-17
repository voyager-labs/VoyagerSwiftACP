import type { CSSProperties, FC } from "react"
import { symbols as SF_SYMBOLS } from "symbolist"

/**
 * SF Symbol 폰트 기반 렌더링 컴포넌트.
 *
 * symbolist 패키지가 제공하는 name → Unicode character 매핑으로
 * SF Pro Symbols 폰트에서 glyph를 직접 렌더링한다.
 * macOS에서는 local(".SF Symbols")이 시스템 폰트로 연결되고,
 * non-macOS에서는 번들된 SF-Pro-Symbols.otf가 사용된다.
 * currentColor를 상속받아 light/dark 모드에 자동 대응한다.
 */
export interface SFSymbolProps {
  readonly name: string
  readonly size?: number
  readonly weight?: number
}

export const SFSymbol: FC<SFSymbolProps> = ({ name, size = 18, weight = 400 }) => {
  const char = (SF_SYMBOLS as Record<string, string>)[name]
  if (!char) {
    return null
  }

  const style: CSSProperties = {
    fontFamily: '"Voyager SF Pro Symbols", ".SF Symbols", "SF Pro Symbols"',
    fontSize: `${size}px`,
    fontWeight: weight,
    lineHeight: 1,
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    width: `${size}px`,
    height: `${size}px`,
  }
  return (
    <span className="sf-symbol" style={style} aria-hidden="true">
      {char}
    </span>
  )
}

SFSymbol.displayName = "SFSymbol"
