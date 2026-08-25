import assert from "node:assert/strict"
import { existsSync, readFileSync, readdirSync } from "node:fs"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const distRoot = resolve(packageRoot, "dist")

function collectDeclarations(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name)
    return entry.isDirectory()
      ? collectDeclarations(path)
      : entry.name.endsWith(".d.ts")
        ? [path]
        : []
  })
}

const declarations = collectDeclarations(distRoot)
const packageJson = JSON.parse(readFileSync(resolve(packageRoot, "package.json"), "utf8"))
assert.ok(declarations.length > 0, "Missing generated declarations")
assert.equal(packageJson.exports["./styles.css"].types, "./dist/styles.d.ts")
assert.ok(
  declarations.some((path) => relative(packageRoot, path) === "dist/styles.d.ts"),
  "Missing CSS export declaration",
)

for (const path of declarations) {
  const declaration = readFileSync(path, "utf8")
  const displayPath = relative(packageRoot, path)
  assert.doesNotMatch(
    declaration,
    /["']@voyager-labs\/design-foundation(?:\/[^"']*)?["']/,
    `${displayPath} exposes the private design-foundation package`,
  )
  assert.doesNotMatch(
    declaration,
    /import\s+["'][^"']+\.css["']/,
    `${displayPath} exposes an unpublished CSS import`,
  )
}

const stylesheet = readFileSync(resolve(distRoot, "file-manager-illustration.css"), "utf8")
const bundle = readFileSync(resolve(distRoot, "index.js"), "utf8")
const inlineImages = bundle.match(/data:image\/png;base64,/g) ?? []

assert.equal(inlineImages.length, 6, "Published bundle must include all location icons")
assert.doesNotMatch(
  bundle,
  /["']\/[^"']+\.png["']/,
  "Published bundle uses consumer-root image URLs",
)
const fontUrls = [...stylesheet.matchAll(/url\((?:["']?)(\.\/fonts\/[^)"']+)/g)].map(
  ([, path]) => path,
)
assert.equal(fontUrls.length, 9, "Published stylesheet must reference all package fonts")
assert.doesNotMatch(
  stylesheet,
  /url\((?:["']?)\/fonts\//,
  "Published stylesheet uses root font URLs",
)
assert.doesNotMatch(stylesheet, /data:font\//, "Published stylesheet contains inline fonts")
for (const path of fontUrls) {
  assert.ok(existsSync(resolve(distRoot, path)), `Missing published font ${path}`)
}

// Verify controls.css selectors are present for self-contained deployment
const controlSelectors = [".vc-icon-button", ".vc-disclosure", ".traffic-lights"]
for (const selector of controlSelectors) {
  assert.ok(
    stylesheet.includes(selector),
    `Published stylesheet must include ${selector} from controls.css`,
  )
}

console.log(
  `package artifact: pass (${declarations.length} declarations, ${inlineImages.length} images, ${fontUrls.length} fonts)`,
)
