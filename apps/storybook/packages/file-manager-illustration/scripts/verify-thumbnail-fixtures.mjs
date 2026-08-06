import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { existsSync, readFileSync } from "node:fs"
import { resolve } from "node:path"

// qlmanage가 생성한 PNG 목록 (provenance.json과 1:1 대응)
const qlmanageThumbnailPngs = [
  "pdf-sample.png",
  "pdf-test.png",
  "pdf-150k.png",
  "pdf-1mb.png",
  "pdf-5mb.png",
  "image-hopper.png",
  "image-transparent.png",
  "image-jpeg.png",
  "gif-hopper.png",
  "office-word.png",
  "office-word-test.png",
  "office-word-tabs.png",
  "office-word-59378.png",
  "office-excel.png",
  "office-excel-budget.png",
  "office-excel-charts.png",
  "office-excel-46535.png",
  "iwork-pages.png",
  "iwork-pages-video.png",
  "video-test-1s.png",
  "video-movie5.png",
  "video-counting.png",
  "text-sample.png",
  "text-short.png",
  "text-3296.png",
  "text-1497.png",
]

// NSWorkspace가 별도 생성한 시스템 아이콘 (provenance에 포함되지 않음)
const systemIconPngs = ["archive-system.png", "folder-system.png"]

const expectedThumbnailPngs = [...qlmanageThumbnailPngs, ...systemIconPngs]

export function verifyThumbnailFixtures(packageRoot, thumbnailMarkup) {
  /* 1. thumbnail이 있는 non-folder가 entry-thumbnail-image를 렌더링하는지 확인 */
  assert.match(
    thumbnailMarkup,
    /class="[^"]*\bentry-thumbnail-image\b[^"]*"/,
    "image entry should render entry-thumbnail-image",
  )
  assert.match(
    thumbnailMarkup,
    /src="https:\/\/example\.com\/photo\.png"/,
    "image entry should carry expected thumbnail src",
  )

  /* 2. folder는 thumbnailSrc가 없으면 SVG 아이콘을 렌더링 */
  assert.match(
    thumbnailMarkup,
    /entry-svg-icon--folder/,
    "folder without thumbnail should render folder SVG icon",
  )

  /* 3. thumbnail 없는 PDF는 SVG 아이콘을 렌더링 */
  assert.match(
    thumbnailMarkup,
    /entry-svg-icon--pdf/,
    "PDF without thumbnail should render PDF SVG icon",
  )

  /* 4. thumbnail 없는 doc은 SVG 아이콘을 렌더링 */
  assert.match(
    thumbnailMarkup,
    /entry-svg-icon--doc/,
    "doc without thumbnail should render doc SVG icon",
  )

  /* ── 썸네일 에셋 픽스처 계약 ─────────────────────────────────────── */

  const thumbnailDir = resolve(packageRoot, "src/assets/entry-thumbnails")

  // 1. 예상 PNG 파일이 모두 디스크에 존재하는지 확인
  for (const name of expectedThumbnailPngs) {
    const p = resolve(thumbnailDir, name)
    assert.ok(existsSync(p), `Missing thumbnail asset: ${name}`)
  }

  const provenancePath = resolve(thumbnailDir, "provenance.json")
  assert.ok(existsSync(provenancePath), "Missing provenance.json")
  const provenance = JSON.parse(readFileSync(provenancePath, "utf8"))
  assert.equal(
    provenance.assets.length,
    26,
    "provenance must have exactly 26 qlmanage asset entries",
  )

  // 2. provenance output 이름이 qlmanage 세트와 정확히 일치하는지 확인
  const outputNames = provenance.assets.map((a) => a.output)
  assert.equal(
    new Set(outputNames).size,
    outputNames.length,
    "duplicate output names in provenance",
  )
  assert.deepEqual(
    [...outputNames].sort(),
    [...qlmanageThumbnailPngs].sort(),
    "provenance output names must exactly match qlmanage-generated set",
  )

  // 3. 소스 경로가 상대 경로이고 부모 참조가 없는지 확인
  for (const asset of provenance.assets) {
    assert.ok(
      !asset.source.startsWith("/"),
      `source path must be relative, got absolute: ${asset.source}`,
    )
    assert.ok(
      !asset.source.includes(".."),
      `source path must not contain parent traversal: ${asset.source}`,
    )
  }

  // 4. Output SHA-256이 provenance 기록과 일치하는지 확인
  for (const asset of provenance.assets) {
    const outputPath = resolve(thumbnailDir, asset.output)
    const actualSha = createHash("sha256").update(readFileSync(outputPath)).digest("hex")
    assert.equal(
      actualSha,
      asset.outputSha256,
      `SHA-256 mismatch for ${asset.output}: expected ${asset.outputSha256}, got ${actualSha}`,
    )
  }

  // 5. Provenance에 필요한 메타데이터 필드가 있는지 확인
  assert.ok(provenance.generator, "provenance missing generator")
  assert.ok(provenance.macOS?.productVersion, "provenance missing macOS productVersion")
  assert.ok(provenance.macOS?.buildVersion, "provenance missing macOS buildVersion")

  // 6. text fixture는 text-pdf-content 파이프라인 모드를 사용
  const textAssets = provenance.assets.filter((a) => a.fixture === "text")
  assert.ok(textAssets.length >= 1, "provenance missing text asset")
  for (const asset of textAssets) {
    assert.equal(
      asset.mode,
      "text-pdf-content",
      `text fixture ${asset.output} mode should be text-pdf-content, got ${asset.mode}`,
    )
  }

  // 7. text 외 asset은 icon, content, nsworkspace-icon 모드 유지(text-pdf-content 누출 방지)
  const nonTextAssets = provenance.assets.filter((a) => a.fixture !== "text")
  for (const asset of nonTextAssets) {
    assert.ok(
      asset.mode === "icon" || asset.mode === "content" || asset.mode === "nsworkspace-icon",
      `asset ${asset.output} has unexpected mode: ${asset.mode}`,
    )
  }

  console.log(
    `thumbnail fixtures: pass (${expectedThumbnailPngs.length}/${expectedThumbnailPngs.length} PNGs, ${qlmanageThumbnailPngs.length} provenance, ${systemIconPngs.length} system icons)`,
  )
}
