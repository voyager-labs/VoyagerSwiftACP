import type { StorybookConfig } from "@storybook/react-vite"
import { activeMaterializedSurfaces } from "../surface-registry.js"

const config: StorybookConfig = {
  stories: [
    ...activeMaterializedSurfaces.map(({ story }) => ({
      directory: story.directory,
      titlePrefix: story.titlePrefix,
      files: story.files,
    })),
  ],
  addons: ["@storybook/addon-docs", "@storybook/addon-mcp"],
  framework: "@storybook/react-vite",
}
export default config
