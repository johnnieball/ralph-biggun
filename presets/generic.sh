# Ralph preset: Generic (edit these commands for your stack)

TEST_CMD="echo 'TODO: configure TEST_CMD in .ralph/config.sh'"
TYPECHECK_CMD="echo 'TODO: configure TYPECHECK_CMD in .ralph/config.sh'"
LINT_CMD="echo 'TODO: configure LINT_CMD in .ralph/config.sh'"
EXTRA_PATH=""
SNAPSHOT_SOURCE_DIR="src"
SNAPSHOT_FILE_EXTENSIONS="*"
SNAPSHOT_TEST_PATTERNS="*.test.*,*.spec.*,test_*"
SNAPSHOT_PARSER="generic"
TEST_COUNT_REGEX="[0-9]+ passed"
ALLOWED_TOOLS="Write,Read,Edit,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git log *),Bash(git status),Bash(git status *)"

# E2E testing (opt-in)
E2E_ENABLED=false
E2E_START_CMD=""
E2E_PORT=3000
E2E_SEED_CMD=""
E2E_MAX_FAILURES=5
E2E_TIMEOUT=900
E2E_REPAIR_MAX=3
