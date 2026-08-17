import React from "react"
import "../packages/file-manager-illustration/src/styles/macos-tokens.css"
import "../packages/file-manager-illustration/src/styles/file-manager.css"
import "../packages/file-manager-illustration/src/styles/atoms.css"
import "../packages/file-manager-illustration/src/styles/form-controls.css"
import "../packages/file-manager-illustration/src/styles/menu-controls.css"
import "../packages/file-manager-illustration/src/styles/feedback.css"
import "../packages/file-manager-illustration/src/styles/overlays.css"
import "../packages/file-manager-illustration/src/styles/inspector.css"
import "../packages/file-manager-illustration/src/styles/sidebar.css"
import "../packages/file-manager-illustration/src/styles/window-shell.css"
import type { Preview, ReactRenderer } from "@storybook/react-vite"
import {
  DesignVersionProvider,
  designVersionIDs,
  designVersionToolbarItems,
} from "../packages/file-manager-illustration/src/Foundations/DesignVersion"

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
    designVersion: {
      description: "Voyager design version",
      toolbar: {
        title: "Design version",
        icon: "paintbrush",
        items: designVersionToolbarItems,
        dynamicTitle: true,
      },
    },
  },
  initialGlobals: {
    visualBaseline: "tahoe",
    colorScheme: "system",
    designVersion: designVersionIDs.current,
  },
  decorators: [
    (Story, context) => {
      const designVersion = designVersionIDs.current

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
        <DesignVersionProvider value={designVersion}>
          <div data-file-manager-illustration data-design-version={designVersion}>
            <Story />
          </div>
        </DesignVersionProvider>
      )
    },
  ] satisfies Preview["decorators"],
}

export default preview
