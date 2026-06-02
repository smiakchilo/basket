# Model Configuration

Shared model roles for skills that use two-tier model routing. Any skill can read this file via `../../model-config.md` (relative to the skill's directory) and map its own phases to these generic tiers.

## Roles

| Role       | Model                          |
|------------|--------------------------------|
| **worker** | `Claude Haiku 4.5 (copilot)`   |
| **expert** | `Claude Opus 4.6 (copilot)`    |

### worker

Fast, cheap model for bulk operations that don't require deep reasoning: data collection, filtering, extraction, formatting, running scripts and returning structured output.

### expert

Powerful model for tasks that require deep reasoning: analysis, pattern detection, anomaly identification, root-cause diagnosis, architectural recommendations, and complex multi-step inference.
