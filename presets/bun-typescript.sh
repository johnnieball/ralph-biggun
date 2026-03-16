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
