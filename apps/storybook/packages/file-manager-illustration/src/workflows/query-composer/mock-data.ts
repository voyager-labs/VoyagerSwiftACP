import type { ComposerDraft } from "./types"

export const composerDrafts: readonly ComposerDraft[] = [
  {
    text: "",
    phase: "idle",
    scope: {
      mode: "rootOnly",
      primary: "This Mac",
      secondary: "Every indexed folder",
    },
    conditions: [],
    includeDirectories: false,
    includeSubfolders: true,
  },
  {
    text: "Find research PDFs updated this month",
    phase: "draft",
    scope: {
      mode: "singleExplicit",
      primary: "Voyager / Research",
      secondary: "~/Documents/Voyager/Research",
    },
    conditions: [
      { id: "kind", property: "Kind", operator: "is", value: "PDF" },
      { id: "modified", property: "Modified", operator: "within", value: "30 days" },
    ],
    canUndo: true,
    includeDirectories: false,
    includeSubfolders: true,
    collectionMode: true,
  },
  {
    text: "Brand files excluding exports",
    phase: "searching",
    scope: {
      mode: "exceptions",
      primary: "3 folders",
      secondary: "Desktop, Downloads, Brand Assets",
      exceptions: "2 exceptions",
    },
    conditions: [{ id: "tag", property: "Tag", operator: "contains", value: "Voyager" }],
    feedback: { kind: "delayed", message: "Scope change is still applying…" },
    canUndo: true,
    includeDirectories: true,
    includeSubfolders: false,
  },
  {
    text: "Contracts with invalid date range",
    phase: "failed",
    scope: {
      mode: "multiExplicit",
      primary: "2 folders",
      secondary: "Legal, Finance",
    },
    conditions: [{ id: "date", property: "Created", operator: "before", value: "tomorrow" }],
    feedback: {
      kind: "error",
      message: "The date value could not be converted into a file query.",
    },
    canUndo: true,
    canRedo: true,
  },
]

export const idleComposer = composerDrafts[0]
export const draftComposer = composerDrafts[1]
export const searchingComposer = composerDrafts[2]
export const failedComposer = composerDrafts[3]
