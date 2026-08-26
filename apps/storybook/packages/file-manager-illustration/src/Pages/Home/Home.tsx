import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { homeFavorites, homeLocations, homeRecentChats } from "../../data/home-data"
import type { HomeChat, HomeFavorite, HomeLocation } from "../../model/home"

export interface HomeProps {
  readonly favorites?: readonly HomeFavorite[]
  readonly locations?: readonly HomeLocation[]
  readonly recentChats?: readonly HomeChat[]
  readonly compact?: boolean
  readonly standalone?: boolean
  readonly onFavoriteSelect?: (favorite: HomeFavorite) => void
  readonly onLocationSelect?: (location: HomeLocation) => void
  readonly onNewChat?: () => void
  readonly onChatSelect?: (chat: HomeChat) => void
}

export const Home: FC<HomeProps> = ({
  favorites = homeFavorites,
  locations = homeLocations,
  recentChats = homeRecentChats,
  compact = false,
  standalone = false,
  onFavoriteSelect,
  onLocationSelect,
  onNewChat,
  onChatSelect,
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
          <div className="home-nav-grid">
            {favorites.map((favorite) => (
              <button
                key={favorite.id}
                className="home-nav-tile"
                type="button"
                aria-label={`Open favorite ${favorite.label}`}
                onClick={() => onFavoriteSelect?.(favorite)}
              >
                <span className="home-nav-tile-icon" aria-hidden="true">
                  {favorite.glyph}
                </span>
                <span className="home-nav-tile-label">{favorite.label}</span>
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
          <div className="home-nav-grid">
            {locations.map((location) => (
              <button
                key={location.id}
                className="home-nav-tile"
                type="button"
                aria-label={`Open location ${location.label}`}
                onClick={() => onLocationSelect?.(location)}
              >
                <span className="home-nav-tile-icon" aria-hidden="true">
                  {location.glyph}
                </span>
                <span className="home-nav-tile-label">{location.label}</span>
              </button>
            ))}
          </div>
        </section>
      )}

      {/* Recent Chats — native recentChatsSection, trailing New Chat pill */}
      <section className="home-section" aria-labelledby="recent-chats-heading">
        <div className="home-section-heading">
          <h2 id="recent-chats-heading">Recent Chats</h2>
          <button
            className="home-new-chat"
            type="button"
            aria-label="Start New Chat"
            onClick={() => onNewChat?.()}
          >
            New Chat
          </button>
        </div>
        {recentChats.length > 0 ? (
          <ul className="home-chat-list">
            {recentChats.map((chat) => (
              <li key={chat.id}>
                <button
                  className="home-chat-row"
                  type="button"
                  aria-label={`Open chat ${chat.title}`}
                  onClick={() => onChatSelect?.(chat)}
                >
                  <span className="home-chat-glyph" aria-hidden="true">
                    <SFSymbol name="bubble.right" size={16} weight={600} />
                  </span>
                  <span className="home-chat-text">
                    <span className="home-chat-title">{chat.title}</span>
                    {chat.detail ? <span className="home-chat-detail">{chat.detail}</span> : null}
                  </span>
                  <span className="home-chat-time">{chat.relativeTime}</span>
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="home-empty">No recent chats</p>
        )}
      </section>
    </section>
  )
}

Home.displayName = "Home"
