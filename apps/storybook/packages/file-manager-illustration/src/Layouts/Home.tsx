import type { FC } from "react"
import { homeFavorites, homeLocations } from "../data/home-data"
import type { HomeFavorite, HomeLocation } from "../model/home"

export interface HomeProps {
  readonly favorites?: readonly HomeFavorite[]
  readonly locations?: readonly HomeLocation[]
  readonly compact?: boolean
  readonly standalone?: boolean
  readonly onFavoriteSelect?: (favorite: HomeFavorite) => void
  readonly onLocationSelect?: (location: HomeLocation) => void
}

export const Home: FC<HomeProps> = ({
  favorites = homeFavorites,
  locations = homeLocations,
  compact = false,
  standalone = false,
  onFavoriteSelect,
  onLocationSelect,
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

    </section>
  )
}

Home.displayName = "Home"
