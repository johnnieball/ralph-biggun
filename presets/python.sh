# Ralph preset: Python (pytest + mypy + ruff)

TEST_CMD="pytest"
TYPECHECK_CMD="mypy ."
LINT_CMD="ruff check ."
EXTRA_PATH=""
SNAPSHOT_SOURCE_DIR="src"
SNAPSHOT_FILE_EXTENSIONS="py"
SNAPSHOT_TEST_PATTERNS="test_*,*_test.py"
SNAPSHOT_PARSER="python"
TEST_COUNT_REGEX="[0-9]+ passed"
ALLOWED_TOOLS="Write,Read,Edit,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git log *),Bash(git status),Bash(git status *),Bash(python *),Bash(pip *),Bash(pytest *),Bash(mypy *),Bash(ruff *)"
