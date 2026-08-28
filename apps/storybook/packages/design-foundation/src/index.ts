/* Design Foundation 공용 진입점.
 * macOS 토큰/폰트 + 공용 UI 키트(Controls/Display/Feedback/Navigation/Overlays) 배럴.
 */

/* 스타일 — UI kit이 자체 로드되도록 진입점에서 import한다. */
import "./styles/ui-kit.css"
import "./styles/atoms.css"
import "./styles/controls.css"
import "./styles/form-controls.css"
import "./styles/menu-controls.css"
import "./styles/feedback.css"
import "./styles/overlays.css"

export { SFSymbol } from "./Foundations/SFSymbol"
export type { SFSymbolProps } from "./Foundations/SFSymbol"

export { TabView } from "./UI/Navigation/TabView"
export type { TabItem, TabViewProps } from "./UI/Navigation/TabView"
export { TabViewItem } from "./UI/Navigation/TabViewItem"
export type { TabViewItemProps } from "./UI/Navigation/TabViewItem"

/* ── UI kit: Controls ── */
export { Button } from "./UI/Controls/Button"
export type { ButtonProps } from "./UI/Controls/Button"
export { ComboBox } from "./UI/Controls/ComboBox"
export type { ComboBoxProps } from "./UI/Controls/ComboBox"
export type { ControlOption } from "./UI/Controls/ControlOption"
export { IconButton } from "./UI/Controls/IconButton"
export type { IconButtonProps } from "./UI/Controls/IconButton"
export { MenuItem } from "./UI/Controls/MenuItem"
export type { MenuItemProps } from "./UI/Controls/MenuItem"
export { Menu, MenuSeparator } from "./UI/Controls/Menu"
export type { MenuProps } from "./UI/Controls/Menu"
export { PopUpButton } from "./UI/Controls/PopUpButton"
export type { PopUpButtonProps } from "./UI/Controls/PopUpButton"
export { PullDownButton } from "./UI/Controls/PullDownButton"
export type { PullDownButtonProps } from "./UI/Controls/PullDownButton"
export { TextField } from "./UI/Controls/TextField"
export type { TextFieldProps, TextFieldSize, TextFieldVariant } from "./UI/Controls/TextField"
export { Toggle } from "./UI/Controls/Toggle"
export type { ToggleProps } from "./UI/Controls/Toggle"
export { Tooltip } from "./UI/Controls/Tooltip"
export type { TooltipProps } from "./UI/Controls/Tooltip"

/* ── UI kit: Display ── */
export { TrafficLights } from "./UI/Display/TrafficLights"

/* ── UI kit: Feedback ── */
export { Alert } from "./UI/Feedback/Alert"
export type { AlertProps } from "./UI/Feedback/Alert"

/* ── UI kit: Navigation ── */
export { DisclosureControl } from "./UI/Navigation/DisclosureControl"
export type { DisclosureControlProps } from "./UI/Navigation/DisclosureControl"
export { SegmentedControl } from "./UI/Navigation/SegmentedControl"
export type { SegmentedControlProps, SegmentedOption } from "./UI/Navigation/SegmentedControl"
export { SidebarIcon } from "./UI/Navigation/SidebarIcon"
export { SidebarNavItem } from "./UI/Navigation/SidebarNavItem"

/* ── UI kit: Overlays ── */
export { Dialog } from "./UI/Overlays/Dialog"
export type { DialogProps } from "./UI/Overlays/Dialog"
export { Popover } from "./UI/Overlays/Popover"
export type { PopoverProps, PopoverPlacement } from "./UI/Overlays/Popover"
export { Sheet } from "./UI/Overlays/Sheet"
export type { SheetProps } from "./UI/Overlays/Sheet"

/* ── UI kit: 공용 모델 타입 ── */
export type {
  BreadcrumbSegment,
  SidebarIconKind,
  SidebarIconProps,
  SidebarNavItemProps,
  SidebarTabAction,
  SidebarTabItem,
  TrafficLightsProps,
} from "./model/ui-types"
