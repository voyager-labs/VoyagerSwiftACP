# Onboarding Package (VoyagerPagesOnboarding)

SwiftPM package for the Voyager onboarding page layer. Hosts the onboarding feature reducer, step models, and permission/BetaAccess gateway APIs consumed during the onboarding flow.

## VOY-355 ONB Verification Map

Traceability matrix mapping every ONB feature spec interaction to its owning test suite, evidence target, and scope classification for VOY-355.

### ONB-001: Run User Onboarding (7 interactions)

| Spec ID | Interaction ID                         | Owner Test Class                      | Owner Test File                                                                                                       | Evidence Target                                                                                                  | Classification |
| ------- | -------------------------------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------- |
| ONB-001 | `ONB-001-start_onboarding_session`     | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-show_onboarding_step`         | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-update_onboarding_step_state` | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-advance_onboarding_step`      | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-go_back_onboarding_step`      | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-resume_onboarding_session`    | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |
| ONB-001 | `ONB-001-complete_onboarding_session`  | `ONB001RunUserOnboardingFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB001RunUserOnboardingFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests` | in-scope       |

### ONB-002: Present Access Unlock Step (3 interactions)

| Spec ID | Interaction ID                         | Owner Test Class                            | Owner Test File                                                                                                                   | Evidence Target                                                                                                           | Classification |
| ------- | -------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------- |
| ONB-002 | `ONB-002-show_access_unlock_status`    | `ONB002PresentAccessUnlockStepFeatureTests` | `apps/macos/Packages/04_Features/BetaAccess/Tests/VoyagerFeaturesBetaAccessTests/ONB002PresentAccessUnlockStepFeatureTests.swift` | `swift test --package-path apps/macos/Packages/04_Features/BetaAccess --filter ONB002PresentAccessUnlockStepFeatureTests` | in-scope       |
| ONB-002 | `ONB-002-apply_access_unlock_result`   | `ONB002PresentAccessUnlockStepFeatureTests` | `apps/macos/Packages/04_Features/BetaAccess/Tests/VoyagerFeaturesBetaAccessTests/ONB002PresentAccessUnlockStepFeatureTests.swift` | `swift test --package-path apps/macos/Packages/04_Features/BetaAccess --filter ONB002PresentAccessUnlockStepFeatureTests` | in-scope       |
| ONB-002 | `ONB-002-start_access_unlock_recovery` | `ONB002PresentAccessUnlockStepFeatureTests` | `apps/macos/Packages/04_Features/BetaAccess/Tests/VoyagerFeaturesBetaAccessTests/ONB002PresentAccessUnlockStepFeatureTests.swift` | `swift test --package-path apps/macos/Packages/04_Features/BetaAccess --filter ONB002PresentAccessUnlockStepFeatureTests` | in-scope       |

### ONB-002 Future Scope: Auth/Entitlement Migration

| Spec ID | Item                              | Owner                                                                                              | Evidence Target                            | Classification |
| ------- | --------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------ | -------------- |
| ONB-002 | Auth/Entitlement access migration | Linear project `$5 Core License 결제·권한·앱 unlock 실험` (`f946b2b9-0e41-4975-a55a-d5aacc11fcbd`) | Follow-up issue under Core License project | future-scope   |

### ONB-003: Configure Required Permissions During Onboarding (3 interactions)

| Spec ID | Interaction ID                                 | Owner Test Class                                 | Owner Test File                                                                                                                  | Evidence Target                                                                                                             | Classification |
| ------- | ---------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------- |
| ONB-003 | `ONB-003-show_onboarding_permission_status`    | `ONB003ConfigureRequiredPermissionsFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB003ConfigureRequiredPermissionsFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB003ConfigureRequiredPermissionsFeatureTests` | in-scope       |
| ONB-003 | `ONB-003-refresh_onboarding_permission_status` | `ONB003ConfigureRequiredPermissionsFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB003ConfigureRequiredPermissionsFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB003ConfigureRequiredPermissionsFeatureTests` | in-scope       |
| ONB-003 | `ONB-003-request_onboarding_permission_access` | `ONB003ConfigureRequiredPermissionsFeatureTests` | `apps/macos/Packages/02_Pages/Onboarding/Tests/VoyagerPagesOnboardingTests/ONB003ConfigureRequiredPermissionsFeatureTests.swift` | `swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB003ConfigureRequiredPermissionsFeatureTests` | in-scope       |

### ONB-004: Configure AI Provider During Onboarding (3 interactions, future scope)

| Spec ID | Interaction ID                                         | Owner                                                                                                | Evidence Target                           | Classification |
| ------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ----------------------------------------- | -------------- |
| ONB-004 | `ONB-004-show_onboarding_ai_provider_setup`            | Linear project `BYOK/구독 계정 연결 기반 AI 채팅 기능 도입` (`b21227bf-0854-428e-a9ed-ae4d8fd93bba`) | Follow-up issue under AI Provider project | future-scope   |
| ONB-004 | `ONB-004-start_ai_provider_connection_from_onboarding` | Linear project `BYOK/구독 계정 연결 기반 AI 채팅 기능 도입` (`b21227bf-0854-428e-a9ed-ae4d8fd93bba`) | Follow-up issue under AI Provider project | future-scope   |
| ONB-004 | `ONB-004-skip_ai_provider_setup_during_onboarding`     | Linear project `BYOK/구독 계정 연결 기반 AI 채팅 기능 도입` (`b21227bf-0854-428e-a9ed-ae4d8fd93bba`) | Follow-up issue under AI Provider project | future-scope   |

### Summary

| Feature                                | In-Scope Interactions | Future-Scope Rows              |
| -------------------------------------- | --------------------- | ------------------------------ |
| ONB-001 Run User Onboarding            | 7                     | 0                              |
| ONB-002 Present Access Unlock Step     | 3                     | 1 (auth/entitlement migration) |
| ONB-003 Configure Required Permissions | 3                     | 0                              |
| ONB-004 Configure AI Provider          | 0                     | 3 (all interactions)           |
| **Total**                              | **13**                | **4**                          |
