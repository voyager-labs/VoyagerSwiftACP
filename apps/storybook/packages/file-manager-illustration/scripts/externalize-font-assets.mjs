import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const sourceRoot = resolve(packageRoot, "../design-foundation/src/assets/fonts")
const outputRoot = resolve(packageRoot, "dist/fonts")
const cssPath = resolve(packageRoot, "dist/file-manager-illustration.css")
const digest = (value) => createHash("sha256").update(value).digest("hex")

const fonts = new Map(
  readdirSync(sourceRoot)
    .filter((name) => name.endsWith(".otf"))
    .map((name) => [digest(readFileSync(resolve(sourceRoot, name))), name]),
)
const emitted = new Set()
const css = readFileSync(cssPath, "utf8").replace(
  /data:font\/otf;base64,([A-Za-z0-9+/=]+)/g,
  (_, encoded) => {
    const name = fonts.get(digest(Buffer.from(encoded, "base64")))
    assert.ok(name, "Built CSS contains an unknown inline font")
    emitted.add(name)
    return `./fonts/${name}`
  },
)

assert.equal(emitted.size, fonts.size, "Built CSS did not include every package font")
mkdirSync(outputRoot, { recursive: true })
for (const name of emitted) {
  copyFileSync(resolve(sourceRoot, name), resolve(outputRoot, name))
}
writeFileSync(cssPath, css)

console.log(`package fonts: externalized (${emitted.size} files)`)
