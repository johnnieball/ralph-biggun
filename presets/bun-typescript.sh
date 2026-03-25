# Ralph preset: Bun + TypeScript (Vitest)

TEST_CMD="bun run test"
TYPECHECK_CMD="bun run typecheck"
LINT_CMD="bun run lint"
EXTRA_PATH="$HOME/.bun/bin"
SNAPSHOT_SOURCE_DIR="src"
SNAPSHOT_FILE_EXTENSIONS="ts,tsx,js,jsx"
SNAPSHOT_TEST_PATTERNS="*.test.*,*.spec.*"
SNAPSHOT_PARSER="typescript"
TEST_COUNT_REGEX="Tests[[:space:]]+[0-9]+ passed"
ALLOWED_TOOLS="Write,Read,Edit,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git log *),Bash(git status),Bash(git status *),Bash(bun *),Bash(bunx *)"

# E2E testing (opt-in)
E2E_ENABLED=false
E2E_START_CMD=""
E2E_PORT=3000
E2E_SEED_CMD=""
E2E_MAX_FAILURES=5
E2E_TIMEOUT=900
E2E_REPAIR_MAX=3
