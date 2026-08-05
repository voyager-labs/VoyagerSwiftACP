/** 단일 컨트롤 옵션(select, menu, combobox 등)의 공유 타입 */
export interface ControlOption<Value = string> {
  readonly value: Value
  readonly label: string
  readonly detail?: string
  readonly disabled?: boolean
}