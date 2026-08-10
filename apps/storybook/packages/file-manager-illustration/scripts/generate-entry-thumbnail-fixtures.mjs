#!/usr/bin/env node

import { execSync } from "node:child_process"
import { createHash } from "node:crypto"
import { existsSync, readFileSync, writeFileSync } from "node:fs"
import { cp, mkdir, readdir, rm, writeFile } from "node:fs/promises"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const PACKAGE_ROOT = resolve(__dirname, "..")
const REPO_ROOT = resolve(PACKAGE_ROOT, "../../../..")
const OUTPUT_DIR = resolve(PACKAGE_ROOT, "src/assets/entry-thumbnails")
const FIXTURES_DIR = resolve(REPO_ROOT, "fixtures/fixtures")

const FIXTURES = [
  // --- PDF (5 variations) ---
  {
    key: "pdf",
    sourceRel: "documents/pdf/sample-local-pdf.pdf",
    mode: "icon",
    outputName: "pdf-sample",
  },
  {
    key: "pdf",
    sourceRel: "documents/pdf/pdf-test.pdf",
    mode: "icon",
    outputName: "pdf-test",
  },
  {
    key: "pdf",
    sourceRel: "documents/pdf/file-sample_150kB.pdf",
    mode: "icon",
    outputName: "pdf-150k",
  },
  {
    key: "pdf",
    sourceRel: "documents/pdf/file-example_PDF_1MB.pdf",
    mode: "icon",
    outputName: "pdf-1mb",
  },
  {
    key: "pdf",
    sourceRel: "documents/pdf/5 mB sample pdf file  .pdf",
    mode: "icon",
    outputName: "pdf-5mb",
  },

  // --- Image (5 variations: PNG×2, JPEG×2, GIF×1) ---
  { key: "image", sourceRel: "images/png/hopper.png", mode: "content", outputName: "image-hopper" },
  {
    key: "image",
    sourceRel: "images/png/transparent.png",
    mode: "content",
    outputName: "image-transparent",
  },
  { key: "image", sourceRel: "images/jpeg/hopper.jpg", mode: "content", outputName: "image-jpeg" },

  // --- GIF (1 — 다른 GIF 소스가 모두 손상됨) ---
  { key: "gif", sourceRel: "images/gif/hopper.gif", mode: "icon", outputName: "gif-hopper" },

  // --- Word/DOCX (4 variations) ---
  {
    key: "word",
    sourceRel: "documents/word/checkboxes.docx",
    mode: "icon",
    outputName: "office-word",
  },
  {
    key: "word",
    sourceRel: "documents/word/TestDocument.docx",
    mode: "icon",
    outputName: "office-word-test",
  },
  {
    key: "word",
    sourceRel: "documents/word/WithTabs.docx",
    mode: "icon",
    outputName: "office-word-tabs",
  },
  {
    key: "word",
    sourceRel: "documents/word/59378.docx",
    mode: "icon",
    outputName: "office-word-59378",
  },

  // --- Spreadsheet/XLSX (4 variations) ---
  {
    key: "workbook",
    sourceRel: "spreadsheets/excel/Booleans.xlsx",
    mode: "icon",
    outputName: "office-excel",
  },
  {
    key: "workbook",
    sourceRel: "spreadsheets/excel/simple-monthly-budget.xlsx",
    mode: "icon",
    outputName: "office-excel-budget",
  },
  {
    key: "workbook",
    sourceRel: "spreadsheets/excel/123233_charts.xlsx",
    mode: "icon",
    outputName: "office-excel-charts",
  },
  {
    key: "workbook",
    sourceRel: "spreadsheets/excel/46535.xlsx",
    mode: "icon",
    outputName: "office-excel-46535",
  },

  // --- Pages (2 variations — 유일한 소스) ---
  {
    key: "pages",
    sourceRel: "documents/pages/일반 리포트.pages",
    mode: "icon",
    outputName: "iwork-pages",
  },
  {
    key: "pages",
    sourceRel: "documents/pages/영상 리포트.pages",
    mode: "icon",
    outputName: "iwork-pages-video",
  },

  // --- Video (4 variations) ---
  {
    key: "video",
    sourceRel: "media/video/test-1s.mp4",
    mode: "content",
    outputName: "video-test-1s",
  },
  {
    key: "video",
    sourceRel: "media/video/movie_5.mp4",
    mode: "content",
    outputName: "video-movie5",
  },
  {
    key: "video",
    sourceRel: "media/video/counting.mp4",
    mode: "content",
    outputName: "video-counting",
  },
  // --- Text (4 variations — cupsfilter → PDF → qlmanage) ---
  {
    key: "text",
    sourceRel: "documents/word/SampleDoc.txt",
    mode: "content",
    outputName: "text-sample",
  },
  { key: "text", sourceRel: "texts/plain/259.txt", mode: "content", outputName: "text-short" },
  { key: "text", sourceRel: "texts/plain/3296.txt", mode: "content", outputName: "text-3296" },
  { key: "text", sourceRel: "texts/plain/1497.txt", mode: "content", outputName: "text-1497" },
]

function sha256Hex(filePath) {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex")
}

function runQL(args, timeoutMs = 30_000) {
  const alarmSec = Math.ceil(timeoutMs / 1000)
  const escaped = args.map((a) => a.replace(/'/g, "'\\''")).join("' '")
  const cmd = `perl -e 'alarm ${alarmSec}; exec @ARGV' -- '${escaped}' 2>&1`
  try {
    const stdout = execSync(cmd, {
      encoding: "utf8",
      timeout: timeoutMs + 5000,
      stdio: ["ignore", "pipe", "pipe"],
    })
    return { ok: true, stdout, stderr: "" }
  } catch (e) {
    return {
      ok: false,
      stdout: e.stdout?.toString() ?? "",
      stderr: e.stderr?.toString() ?? "",
      error: e.message,
    }
  }
}

async function main() {
  console.log("=== Entry Thumbnail Fixture Generator ===\n")

  await mkdir(OUTPUT_DIR, { recursive: true })

  const swVers = execSync("sw_vers -productVersion", { encoding: "utf8" }).trim()
  const buildVers = execSync("sw_vers -buildVersion", { encoding: "utf8" }).trim()

  const provenance = []
  const results = []

  for (const fixture of FIXTURES) {
    const sourcePath = resolve(FIXTURES_DIR, fixture.sourceRel)
    const outputPath = resolve(OUTPUT_DIR, `${fixture.outputName}.png`)

    console.log(`\n[${fixture.key}]`)

    if (!existsSync(sourcePath)) {
      console.error(`  MISSING: ${fixture.sourceRel}`)
      process.exitCode = 1
      continue
    }

    const sourceBytes = readFileSync(sourcePath)
    const sourceSha = sha256Hex(sourcePath)
    console.log(`  source: ${fixture.sourceRel} (${sourceBytes.length} bytes)`)

    const tmpDir = execSync("mktemp -d", { encoding: "utf8" }).trim()

    const sourceRel = fixture.sourceRel
    const mode = fixture.mode
    let effectiveMode = mode
    let inputPath = sourcePath
    let qlOk = false

    // 전처리: cupsfilter로 TXT→PDF 변환, qlmanage가 읽을 수 있는 흰색 페이지 생성
    if (fixture.key === "text") {
      const pdfPath = join(tmpDir, "converted.pdf")
      const cupsBuffer = execSync(`/usr/sbin/cupsfilter -m application/pdf "${sourcePath}"`, {
        timeout: 30000,
        maxBuffer: 50 * 1024 * 1024,
      })
      writeFileSync(pdfPath, cupsBuffer)
      inputPath = pdfPath
      effectiveMode = "text-pdf-content"
      console.log(`  preprocessed: txt → pdf (${cupsBuffer.length} bytes)`)
    }

    try {
      const qlArgs = ["qlmanage", "-t", "-s", "256", "-f", "2"]
      if (effectiveMode === "icon") qlArgs.push("-i")
      qlArgs.push("-o", tmpDir)
      qlArgs.push(inputPath)

      const qlResult = runQL(qlArgs, 25_000)

      if (qlResult.ok && qlResult.stdout.includes("produced one thumbnail")) {
        qlOk = true
      } else {
        console.warn(`  qlmanage: ${qlResult.error ?? "unexpected output"}`)
        const snippet = `${qlResult.stdout} ${qlResult.stderr}`.slice(0, 200)
        if (snippet.trim()) console.warn(`  ${snippet}`)
      }
    } catch (err) {
      console.warn(`  qlmanage error: ${err.message}`)
    }

    let outputFile = null

    if (qlOk) {
      const entries = await readdir(tmpDir)
      const pngFile = entries.find((e) => e.endsWith(".png"))
      if (pngFile) {
        outputFile = join(tmpDir, pngFile)
      }
    }

    if (!outputFile || !existsSync(outputFile)) {
      console.error(`  FAILED: no output generated for ${fixture.key}`)
      process.exitCode = 1
      await rm(tmpDir, { recursive: true, force: true })
      continue
    }

    await cp(outputFile, outputPath)
    const outputSha = sha256Hex(outputPath)

    const fileInfo = execSync(`/usr/bin/file "${outputPath}"`, { encoding: "utf8" }).trim()
    const sipsInfo = execSync(
      `/usr/bin/sips --getProperty pixelWidth --getProperty pixelHeight --getProperty hasAlpha "${outputPath}" 2>/dev/null`,
      { encoding: "utf8" },
    ).trim()

    console.log(`  output: ${fixture.outputName}.png`)
    console.log(`  ${fileInfo}`)
    console.log(`  ${sipsInfo.replace(/\n/g, " | ")}`)

    provenance.push({
      fixture: fixture.key,
      source: sourceRel,
      mode: effectiveMode,
      output: `${fixture.outputName}.png`,
      sourceSha256: sourceSha,
      outputSha256: outputSha,
    })

    results.push({ key: fixture.key, outputName: `${fixture.outputName}.png` })

    await rm(tmpDir, { recursive: true, force: true })
  }

  const provenancePayload = {
    generator: "generate-entry-thumbnail-fixtures.mjs",
    macOS: {
      productVersion: swVers,
      buildVersion: buildVers,
    },
    assets: provenance,
  }

  const provenancePath = resolve(OUTPUT_DIR, "provenance.json")
  await writeFile(provenancePath, `${JSON.stringify(provenancePayload, null, 2)}\n`)
  console.log(`\n=== provenance.json written (${provenance.length} entries) ===`)

  console.log("\n=== Output Summary ===")
  for (const r of results) {
    const p = resolve(OUTPUT_DIR, r.outputName)
    const st = readFileSync(p)
    const dims = execSync(
      `/usr/bin/sips --getProperty pixelWidth --getProperty pixelHeight --getProperty hasAlpha "${p}" 2>/dev/null`,
      { encoding: "utf8" },
    ).trim()
    const lines = dims.split("\n")
    const w =
      lines
        .find((l) => l.includes("pixelWidth"))
        ?.split(":")[1]
        ?.trim() ?? "?"
    const h =
      lines
        .find((l) => l.includes("pixelHeight"))
        ?.split(":")[1]
        ?.trim() ?? "?"
    const a =
      lines
        .find((l) => l.includes("hasAlpha"))
        ?.split(":")[1]
        ?.trim() ?? "?"
    console.log(`  ${r.outputName}: ${w}x${h}, alpha=${a} (${st.length} bytes)`)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
