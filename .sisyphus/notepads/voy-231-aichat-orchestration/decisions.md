- Kept the AiChat package scaffold to `Model/`, `Reducer/`, `Ui/`, and tests only. I omitted an `Api/AiChatExecutionClient.swift` file because the scaffold does not execute or persist anything yet, so the extra boundary would be empty noise.

- Chose handle-based selection (`selectedModelHandle` / `lockedModelHandle`) with derived display models instead of storing mutable view rows. That keeps provider data passive, makes same-model no-op checks trivial, and prevents next-request selection changes from mutating an in-flight lock.

- Kept the new execution/persistence boundary inside `apps/macos/Packages/04_Features/AiChat/Api/` as thin dependency clients rather than pushing policy into `VoyagerEntitiesAi`. That leaves the package ready for a later live integration without coupling the request gating rules to shared entity contracts.
