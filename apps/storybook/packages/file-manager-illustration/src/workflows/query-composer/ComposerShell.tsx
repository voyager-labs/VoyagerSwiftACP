import type { FC } from "react"
import { Button } from "../../Button"
import type { ComposerDraft } from "./types"

export interface ComposerShellProps {
  readonly draft: ComposerDraft
}

const phaseLabel: Record<ComposerDraft["phase"], string> = {
  idle: "Ready",
  draft: "Drafting",
  searching: "Searching",
  chipsAppliedPendingList: "Applying chips",
  listApplied: "List applied",
  failed: "Failed",
}

export const ComposerShell: FC<ComposerShellProps> = ({ draft }) => {
  return (
    <section className="vc-stage" data-file-manager-illustration-workflow="composer">
      <div className="composer-shell vc-window">
        <header className="composer-header">
          <div>
            <div className="vc-eyebrow">Composer</div>
            <h1>Build a file query</h1>
          </div>
          <div className="composer-header-actions">
            <span className={`vc-chip${draft.collectionMode ? " accent" : ""}`}>
              {draft.collectionMode ? "Collection" : "Search"}
            </span>
            <span className="vc-chip muted">{phaseLabel[draft.phase]}</span>
          </div>
        </header>

        <div className="composer-input-row">
          <input
            className="vc-form-field composer-input"
            defaultValue={draft.text}
            placeholder="Describe the files you want…"
            readOnly
          />
          <Button>Run</Button>
        </div>

        <section className="composer-scope vc-panel">
          <div>
            <div className="vc-eyebrow">Scope</div>
            <strong>{draft.scope.primary}</strong>
            <p>{draft.scope.secondary}</p>
          </div>
          {draft.scope.exceptions && (
            <span className="vc-chip accent">{draft.scope.exceptions}</span>
          )}
        </section>

        <section className="composer-chip-row" aria-label="Composer conditions">
          {draft.conditions.length === 0 ? (
            <span className="vc-chip muted">No conditions yet</span>
          ) : (
            draft.conditions.map((condition) => (
              <span key={condition.id} className="vc-chip">
                {condition.property} {condition.operator} {condition.value}
              </span>
            ))
          )}
        </section>

        <footer className="composer-footer">
          <div className="composer-toggles">
            <span className={`vc-chip${draft.includeSubfolders ? " accent" : ""}`}>Subfolders</span>
            <span className={`vc-chip${draft.includeDirectories ? " accent" : ""}`}>Folders</span>
          </div>
          <div className="composer-history">
            <Button pill disabled={!draft.canUndo}>
              Undo
            </Button>
            <Button pill disabled={!draft.canRedo}>
              Redo
            </Button>
          </div>
        </footer>

        {draft.feedback && (
          <div className={`composer-feedback ${draft.feedback.kind}`}>{draft.feedback.message}</div>
        )}
      </div>
    </section>
  )
}

ComposerShell.displayName = "ComposerShell"
