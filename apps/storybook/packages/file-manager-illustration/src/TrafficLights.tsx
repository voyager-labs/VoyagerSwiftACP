import type { FC } from "react"
import type { TrafficLightsProps } from "./types"

export const TrafficLights: FC<TrafficLightsProps> = () => {
  return (
    <div className="traffic-lights" aria-hidden="true">
      <span className="red" />
      <span className="yellow" />
      <span className="green" />
    </div>
  )
}

TrafficLights.displayName = "TrafficLights"
