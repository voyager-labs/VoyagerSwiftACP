---
name: skill-standardization
description: Validate and standardize Agent Skills against the Agent Skills specification. Use when creating SKILL.md files, auditing existing skills, converting legacy skill formats, improving trigger descriptions, adding eval scaffolds, or batch-checking skill directories.
---

# Skill Standardization

Use this skill as the preflight spec gate before authoring, publishing, or adopting Agent Skills.

## When to use this skill

- Creating a new `SKILL.md` file from scratch
- Auditing existing skills for Agent Skills specification compliance
- Converting legacy skill formats to the standard structure
- Improving skill descriptions to trigger more reliably
- Adding evaluation test cases in `evals/evals.json`
- Batch-validating all skills in a directory for consistency

## Agent Skills specification reference

### Frontmatter fields

| Field           | Required | Constraints                                                                                                                |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------------------- |
| `name`          | Yes      | 1-64 chars, lowercase alphanumeric plus hyphens, no leading/trailing/consecutive hyphens, must match parent directory name |
| `description`   | Yes      | 1-1024 chars, must describe what the skill does and when to trigger                                                        |
| `allowed-tools` | No       | Space-delimited list of pre-approved tools                                                                                 |
| `compatibility` | No       | Max 500 chars, environment requirements                                                                                    |
| `license`       | No       | License name or reference to bundled file                                                                                  |
| `metadata`      | No       | Arbitrary key-value map for additional fields                                                                              |

### Standard directory structure

```text
skill-name/
├── SKILL.md
├── scripts/
├── references/
├── assets/
└── evals/
    └── evals.json
```

Only `SKILL.md` is required. Add other directories only when they serve the skill.

### Progressive disclosure tiers

| Tier         | Loaded                               | When          | Budget                    |
| ------------ | ------------------------------------ | ------------- | ------------------------- |
| Catalog      | `name` and `description`             | Session start | ~100 tokens per skill     |
| Instructions | Full `SKILL.md` body                 | On activation | Under 500 lines preferred |
| Resources    | `scripts/`, `references/`, `assets/` | On demand     | Varies                    |

## Instructions

### Step 1: Validate an existing skill

Run the bundled validator on a skill directory:

```bash
bash scripts/validate_skill.sh path/to/skill-directory
```

Validate all direct child skills in a directory:

```bash
bash scripts/validate_skill.sh --all .agents/skills
```

The validator checks:

- Required frontmatter fields (`name`, `description`)
- `name` format and directory match
- `description` length
- `allowed-tools` scalar formatting
- Recommended sections
- SKILL.md length warnings

### Step 2: Write an effective description

The `description` field determines whether the skill is ever loaded. Include:

1. What the skill does
2. When it should trigger
3. Keywords or synonyms users might say
4. Near-overlap contexts if false positives are likely

Template:

```yaml
description: [What the skill does]. Use when [trigger conditions]. Triggers on: [keyword list].
```

### Step 3: Create or normalize `SKILL.md`

Use this minimal structure unless the skill has stronger local conventions:

```markdown
---
name: skill-name
description: What it does. Use when specific trigger conditions apply.
---

# Skill Title

## When to use this skill

- Scenario 1
- Scenario 2

## Instructions

1. First action
2. Second action

## Examples

- Input: ...
- Output: ...

## Best practices

- Practice 1
- Practice 2
```

### Step 4: Add evaluation scaffolding

Create `evals/evals.json` with realistic prompts and verifiable assertions:

```json
{
    "skill_name": "your-skill-name",
    "evals": [
        {
            "id": 1,
            "prompt": "Realistic user message that should trigger this skill",
            "expected_output": "Description of what success looks like",
            "assertions": ["Specific verifiable claim", "Another specific claim"]
        }
    ]
}
```

Good assertions are observable: file exists, JSON is valid, chart has labels, command exits zero, report includes required sections. Avoid vague assertions like "output is good".

## Best practices

- Keep `SKILL.md` under 500 lines; move details to `references/`.
- Pin script dependencies and avoid interactive prompts.
- Prefer structured script output (`json`, `csv`) over free-form logs.
- Put triggering guidance in frontmatter, not only in the body.
- Add evals before publishing or replacing an existing skill.
