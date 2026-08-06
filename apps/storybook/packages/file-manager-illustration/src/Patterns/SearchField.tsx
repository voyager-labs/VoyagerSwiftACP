import type { FC } from "react"
import type { SearchFieldProps } from "../model/types"

export const SearchField: FC<SearchFieldProps> = ({
  value = "",
  placeholder = "Search",
  resultCount,
}) => {
  return (
    <label className="fm-search-field">
      <span className="fm-search-field-icon" aria-hidden="true">
        ⌕
      </span>
      <input value={value} placeholder={placeholder} spellCheck={false} readOnly />
      {resultCount !== undefined && <small>{resultCount}</small>}
    </label>
  )
}

SearchField.displayName = "SearchField"
