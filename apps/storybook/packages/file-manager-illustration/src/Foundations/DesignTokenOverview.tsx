import { useLayoutEffect, useRef, useState } from "react"
import type { FC } from "react"
import {
  accentTokens,
  colorTokens,
  materialTokens,
  radiusTokens,
  shadowTokens,
  spacingTokens,
  swiftUIColorTokens,
  tokenNames,
  typeTokens,
} from "./design-token-data"
import type { TokenSpec } from "./design-token-data"
import { swiftUIMaterialMetadata } from "./swiftui-material-metadata.generated"

type DesignTokenOverviewProps = {
  readonly baseline: string
  readonly colorScheme: string
}

type TokenMetaProps = {
  readonly token: TokenSpec
  readonly values: Readonly<Record<string, string>>
}

const TokenMeta: FC<TokenMetaProps> = ({ token, values }) => (
  <div className="design-token-meta">
    <strong>{token.label}</strong>
    <code>{token.name}</code>
    {token.source && <span>{token.source}</span>}
    <output aria-label={`Resolved value for ${token.name}`}>
      {values[token.name] || "Resolving"}
    </output>
  </div>
)

export const DesignTokenOverview: FC<DesignTokenOverviewProps> = ({ baseline, colorScheme }) => {
  const rootRef = useRef<HTMLElement | null>(null)
  const [values, setValues] = useState<Readonly<Record<string, string>>>({})

  useLayoutEffect(() => {
    const root = rootRef.current
    if (!root) return

    const computedStyle = getComputedStyle(root)
    const resolvedValues = Object.fromEntries(
      tokenNames.map((name) => [name, computedStyle.getPropertyValue(name).trim()]),
    )
    setValues((currentValues) =>
      tokenNames.every((name) => currentValues[name] === resolvedValues[name])
        ? currentValues
        : resolvedValues,
    )
  })

  return (
    <main ref={rootRef} className="design-token-overview">
      <header className="design-token-hero">
        <div>
          <span className="design-token-eyebrow">Voyager File Manager</span>
          <h1>Design Tokens</h1>
          <p>Resolved SwiftUI system colors and native styles used by the React illustration.</p>
        </div>
        <dl className="design-token-context" aria-label="Current visual context">
          <div>
            <dt>Baseline</dt>
            <dd>{baseline}</dd>
          </div>
          <div>
            <dt>Appearance</dt>
            <dd>{colorScheme}</dd>
          </div>
        </dl>
      </header>

      <div className="design-token-page">
        <section className="design-token-section" aria-labelledby="semantic-colors-heading">
          <div className="design-token-section-heading">
            <span>01</span>
            <div>
              <h2 id="semantic-colors-heading">Semantic colors</h2>
              <p>File Manager aliases resolve from the generated SwiftUI color baseline.</p>
            </div>
          </div>
          <div className="design-token-grid design-token-color-grid">
            {colorTokens.map((token) => (
              <article key={token.name} className="design-token-card">
                <div className="design-token-color" style={{ background: `var(${token.name})` }} />
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="swiftui-colors-heading">
          <div className="design-token-section-heading">
            <span>02</span>
            <div>
              <h2 id="swiftui-colors-heading">SwiftUI colors</h2>
              <p>Public Color values resolved for the selected appearance and OS baseline.</p>
            </div>
          </div>
          <div className="design-token-grid design-token-accent-grid">
            {swiftUIColorTokens.map((token) => (
              <article key={token.name} className="design-token-card">
                <div className="design-token-accent" style={{ background: `var(${token.name})` }} />
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="accents-heading">
          <div className="design-token-section-heading">
            <span>03</span>
            <div>
              <h2 id="accents-heading">System accents</h2>
              <p>Native accent colors reserved for selection, status, and file affordances.</p>
            </div>
          </div>
          <div className="design-token-grid design-token-accent-grid">
            {accentTokens.map((token) => (
              <article key={token.name} className="design-token-card">
                <div className="design-token-accent" style={{ background: `var(${token.name})` }} />
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="materials-heading">
          <div className="design-token-section-heading">
            <span>04</span>
            <div>
              <h2 id="materials-heading">Materials</h2>
              <p>
                SwiftUI Material and Tahoe Glass are contextual ShapeStyle values, not fixed RGBA
                colors.
              </p>
            </div>
          </div>
          <div className="design-token-grid">
            {swiftUIMaterialMetadata.legacyMaterials.map((material) => (
              <article key={material.expression} className="design-token-card">
                <div className="design-token-meta">
                  <strong>{material.name}</strong>
                  <code>{material.expression}</code>
                  <span>{material.availability}</span>
                  <output>{swiftUIMaterialMetadata.rgbaPolicy}</output>
                </div>
              </article>
            ))}
            {swiftUIMaterialMetadata.tahoeGlassStyles.map((glass) => (
              <article key={glass.expression} className="design-token-card">
                <div className="design-token-meta">
                  <strong>{glass.name}</strong>
                  <code>{glass.expression}</code>
                  <span>{glass.availability}</span>
                  <output>
                    {swiftUIMaterialMetadata.tahoeRuntimeMeasured
                      ? "Runtime measured"
                      : "Requires a macOS 26 runtime"}
                  </output>
                </div>
              </article>
            ))}
          </div>
          <div className="design-token-grid design-token-material-grid">
            {materialTokens.map((token) => (
              <article key={token.label} className="design-token-card">
                <div className="design-token-material">
                  <span style={{ background: `var(${token.name})` }} />
                </div>
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="typography-heading">
          <div className="design-token-section-heading">
            <span>05</span>
            <div>
              <h2 id="typography-heading">Typography</h2>
              <p>SF Pro Text keeps controls legible at compact macOS density.</p>
            </div>
          </div>
          <div className="design-token-type-list">
            {typeTokens.map((token) => (
              <article key={token.name} className="design-token-type-row">
                <span style={{ fontSize: `var(${token.name})` }}>Voyager File Manager</span>
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="geometry-heading">
          <div className="design-token-section-heading">
            <span>06</span>
            <div>
              <h2 id="geometry-heading">Radius and spacing</h2>
              <p>Compact geometry follows the 4px layout rhythm and current OS baseline.</p>
            </div>
          </div>
          <div className="design-token-geometry">
            <div className="design-token-grid">
              {radiusTokens.map((token) => (
                <article key={token.name} className="design-token-card">
                  <div
                    className="design-token-radius"
                    style={{ borderRadius: `var(${token.name})` }}
                  />
                  <TokenMeta token={token} values={values} />
                </article>
              ))}
            </div>
            <div className="design-token-spacing-list">
              {spacingTokens.map((token) => (
                <article key={token.name} className="design-token-spacing-row">
                  <div className="design-token-spacing-track">
                    <span style={{ width: `var(${token.name})` }} />
                  </div>
                  <TokenMeta token={token} values={values} />
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="design-token-section" aria-labelledby="elevation-heading">
          <div className="design-token-section-heading">
            <span>07</span>
            <div>
              <h2 id="elevation-heading">Elevation</h2>
              <p>
                Shadows distinguish paper, cards, and the native window without card-heavy styling.
              </p>
            </div>
          </div>
          <div className="design-token-grid design-token-shadow-grid">
            {shadowTokens.map((token) => (
              <article key={token.name} className="design-token-card">
                <div className="design-token-shadow" style={{ boxShadow: `var(${token.name})` }} />
                <TokenMeta token={token} values={values} />
              </article>
            ))}
          </div>
        </section>
      </div>
    </main>
  )
}

DesignTokenOverview.displayName = "DesignTokenOverview"
