import { SFSymbol as DesignFoundationSFSymbol } from "@voyager-labs/design-foundation"
import type { FC } from "react"

export type SFSymbolProps = {
  readonly name: string
  readonly size?: number
  readonly weight?: number
}

export const SFSymbol: FC<SFSymbolProps> = (props) => <DesignFoundationSFSymbol {...props} />
