import { createContext, useContext } from "react"
import type { FC, ReactNode } from "react"

export const designVersionIDs = {
  current: "current",
} as const

export const designVersionToolbarItems = [
  { value: designVersionIDs.current, title: "Current" },
] as const

export type DesignVersion = (typeof designVersionIDs)[keyof typeof designVersionIDs]

const DesignVersionContext = createContext<DesignVersion>(designVersionIDs.current)

export const DesignVersionProvider: FC<{
  readonly value: DesignVersion
  readonly children: ReactNode
}> = ({ value, children }) => (
  <DesignVersionContext.Provider value={value}>{children}</DesignVersionContext.Provider>
)

export function useDesignVersion(): DesignVersion {
  return useContext(DesignVersionContext)
}
