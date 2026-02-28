# PR Body Quality Gate Checklist

Complete PR body updates only when all items below are satisfied.

## 1) Commit consistency

- [ ] Commit list in `origin/<base>..HEAD` matches PR body 1:1.
- [ ] No missing or duplicate commit hash/subject entries.

## 2) Title consistency

- [ ] Title follows `[Issue] Summary` format.
- [ ] Title intent does not conflict with body scope.

## 3) Module detail density

- [ ] Every module section includes exact file paths.
- [ ] Change type (`add|modify|delete|migrate`) is explicit.
- [ ] Behavior difference and intent/impact are both described.
- [ ] Risk/compatibility impact is documented.

## 4) Verification records

- [ ] Only actually executed commands are recorded.
- [ ] Failed commands include cause/impact/follow-up.
- [ ] Non-executed checks are marked as skipped with reason.

## 5) Linear integration

- [ ] Linear issue link appears near the top.
- [ ] Body text is based on actual diff, not copied issue text.
- [ ] Requirement/implementation mismatches are split into current scope vs follow-up track.
