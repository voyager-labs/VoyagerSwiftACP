import type { FC } from "react"
import { DisclosureControl } from "../DisclosureControl"
import { SidebarNavItem } from "../SidebarNavItem"
import type { SidebarSectionProps } from "../types"

export const SidebarSection: FC<SidebarSectionProps> = ({ items, title, compact = false }) => {
  const sectionClass = ["sidebar-section", compact ? "compact" : ""].filter(Boolean).join(" ")

  return (
    <section className={sectionClass}>
      {title != null && (
        <header>
          <span>{title}</span>
          <DisclosureControl
            expanded
            onToggle={() => {}}
            aria-label={`Collapse ${title.toLowerCase()}`}
          >
            Collapse {title.toLowerCase()}
          </DisclosureControl>
        </header>
      )}
      {items.length > 0 && (
        <nav>
          {items.map((item) => (
            <SidebarNavItem key={item.id} item={item} />
          ))}
        </nav>
      )}
    </section>
  )
}

SidebarSection.displayName = "SidebarSection"
