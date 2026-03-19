# Eval Run Scorecard

**Run:** {{TIMESTAMP}}
**Prompt version:** [git SHA or description]
**Project:** {{PROJECT}}

## Results

| Metric            | Value               | Notes                                         |
| ----------------- | ------------------- | --------------------------------------------- |
| Stories completed | /{{STORY_COUNT}}    |                                               |
| Total iterations  | {{ITERATION_COUNT}} |                                               |
| Exit condition    | {{EXIT_CONDITION}}  | clean exit / circuit breaker / max iterations |
| Exit code         | {{EXIT_CODE}}       | 0 = success, 1 = failure                      |

## Behaviour Assessment

Score each 1-5 (1=broken, 3=acceptable, 5=excellent):

| Behaviour                                   | Score | Evidence |
| ------------------------------------------- | ----- | -------- |
| TDD compliance (RED before GREEN)           |       |          |
| Vertical slicing (one story per iteration)  |       |          |
| Test quality (behaviour not implementation) |       |          |
| Correct exit (stopped when done)            |       |          |
| progress.txt hygiene                        |       |          |
| Commit message format                       |       |          |
| No gold-plating (stayed within task list)   |       |          |
| Read reference files when appropriate       |       |          |

{{AUDIT_POINTS}}

## Failure Modes Observed

(Note any from failure-taxonomy.md that appeared, or new ones)

## Notes

(Free-form observations, things to investigate, prompt changes to try)
