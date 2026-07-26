import type { FC } from "react"
import { homeFavorites, homeLocations, homeRecentChats } from "./home-data"

export type HomeFavorite = {
  readonly id: string
  readonly label: string
  readonly glyph: string
  readonly destinationTabId: "directory" | "collection"
  readonly pageAnchor: string
}

export type HomeLocation = {
  readonly id: string
  readonly label: string
  readonly glyph: string
  readonly destinationTabId: "directory"
  readonly path: string
}

export type HomeRecentChat = {
  readonly id: string
  readonly sessionId: string
  readonly title: string
  readonly detail?: string
  readonly updatedLabel: string
  readonly destinationTabId: "ai-chat"
}

export interface HomeProps {
  readonly favorites?: readonly HomeFavorite[]
  readonly locations?: readonly HomeLocation[]
  readonly recentChats?: readonly HomeRecentChat[]
  readonly compact?: boolean
  readonly standalone?: boolean
  readonly onFavoriteSelect?: (favorite: HomeFavorite) => void
  readonly onLocationSelect?: (location: HomeLocation) => void
  readonly onRecentChatSelect?: (chat: HomeRecentChat) => void
  readonly onNewChat?: () => void
}

export const Home: FC<HomeProps> = ({
  favorites = homeFavorites,
  locations = homeLocations,
  recentChats = homeRecentChats,
  compact = false,
  standalone = false,
  onFavoriteSelect,
  onLocationSelect,
  onRecentChatSelect,
  onNewChat,
}) => {
  const classes = ["file-manager-home", compact ? "compact" : "", standalone ? "standalone" : ""]
    .filter(Boolean)
    .join(" ")

  return (
    <section className={classes} aria-label="Home">
      {/* Favorites */}
      <section className="home-section" aria-labelledby="favorites-heading">
        <h2 id="favorites-heading">Favorites</h2>
        {favorites.length > 0 ? (
          <div className="home-card-grid">
            {favorites.map((favorite) => (
              <button
                key={favorite.id}
                className="home-card"
                type="button"
                aria-label={`Open favorite ${favorite.label}`}
                onClick={() => onFavoriteSelect?.(favorite)}
              >
                <span className="home-card-icon" aria-hidden="true">
                  {favorite.glyph}
                </span>
                <span>{favorite.label}</span>
              </button>
            ))}
          </div>
        ) : (
          <p className="home-empty">No pinned favorites</p>
        )}
      </section>

      {/* Locations */}
      {locations.length > 0 && (
        <section className="home-section" aria-labelledby="locations-heading">
          <h2 id="locations-heading">Locations</h2>
          <div className="home-card-grid">
            {locations.map((location) => (
              <button
                key={location.id}
                className="home-card"
                type="button"
                aria-label={`Open location ${location.label}`}
                onClick={() => onLocationSelect?.(location)}
              >
                <span className="home-card-icon" aria-hidden="true">
                  {location.glyph}
                </span>
                <span>{location.label}</span>
              </button>
            ))}
          </div>
        </section>
      )}

      {/* Recent Chats */}
      <section className="home-section" aria-labelledby="recent-chats-heading">
        <div className="home-section-heading">
          <h2 id="recent-chats-heading">Recent Chats</h2>
          <button className="home-new-chat" type="button" onClick={onNewChat}>
            New Chat
          </button>
        </div>
        {recentChats.length > 0 ? (
          <div className="home-chat-list">
            {recentChats.map((chat) => (
              <button
                key={chat.id}
                className="home-chat-row"
                type="button"
                aria-label={`Open chat ${chat.title}`}
                onClick={() => onRecentChatSelect?.(chat)}
              >
                <span className="home-chat-icon" aria-hidden="true">
                  ✦
                </span>
                <span className="home-chat-copy">
                  <strong>{chat.title}</strong>
                  {chat.detail && <span>{chat.detail}</span>}
                </span>
                <span className="home-chat-timestamp">{chat.updatedLabel}</span>
              </button>
            ))}
          </div>
        ) : (
          <p className="home-empty">No recent chats</p>
        )}
      </section>
    </section>
  )
}

Home.displayName = "Home"
