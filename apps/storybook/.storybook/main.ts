import type { StorybookConfig } from "@storybook/react-vite"

const config: StorybookConfig = {
  stories: [
    "../src/**/*.mdx",
    "../src/**/*.stories.@(js|jsx|mjs|ts|tsx)",
    {
      directory: "../packages/file-manager-illustration/src",
      titlePrefix: "File Manager",
      files: "**/*.stories.tsx",
    },
    {
      directory: "../packages/settings-illustration/src",
      titlePrefix: "Settings",
      files: "**/*.stories.tsx",
    },
    {
      directory: "../packages/design-foundation/src",
      titlePrefix: "Design Foundation",
      files: "**/*.stories.tsx",
    },
  ],
  addons: ["@storybook/addon-docs", "@storybook/addon-mcp"],
  framework: "@storybook/react-vite",
}
export default config
