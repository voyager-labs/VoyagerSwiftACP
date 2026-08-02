import React from "react"
import "@voyager-labs/file-manager-illustration/styles.css"
import type { Preview, ReactRenderer } from "@storybook/react-vite"

const colorSchemeAttribute = "data-voyager-color-scheme"
const visualBaselineAttribute = "data-voyager-visual-baseline"

const preview: Preview = {
  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
  },
  globalTypes: {
    visualBaseline: {
      description: "Voyager macOS visual baseline",
      toolbar: {
        title: "macOS baseline",
        icon: "browser",
        items: [
          { value: "tahoe", title: "Tahoe" },
          { value: "sequoia", title: "Sequoia" },
        ],
        dynamicTitle: true,
      },
    },
    colorScheme: {
      description: "Voyager color scheme",
      toolbar: {
        title: "Color scheme",
        icon: "circlehollow",
        items: [
          { value: "system", title: "System" },
          { value: "light", title: "Light" },
          { value: "dark", title: "Dark" },
        ],
        dynamicTitle: true,
      },
    },
  },
  initialGlobals: {
    visualBaseline: "tahoe",
    colorScheme: "system",
  },
  decorators: [
    (Story, context) => {
      if (typeof document !== "undefined") {
        const visualBaseline = context.globals.visualBaseline
        const colorScheme = context.globals.colorScheme

        if (visualBaseline === "sequoia") {
          document.documentElement.setAttribute(visualBaselineAttribute, "sequoia")
        } else {
          document.documentElement.setAttribute(visualBaselineAttribute, "tahoe")
        }

        if (colorScheme === "light" || colorScheme === "dark") {
          document.documentElement.setAttribute(colorSchemeAttribute, colorScheme)
        } else {
          document.documentElement.removeAttribute(colorSchemeAttribute)
        }
      }

      return (
        <div data-file-manager-illustration>
          <Story />
        </div>
      )
    },
  ] satisfies Preview["decorators"],
}

export default preview
