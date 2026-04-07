---
title: "LACI Updater Tool — Implementation Plan"
date: 2026-04-07
status: draft
category: plan
tags:
  - laci
  - automation
  - implementation
  - tooling
related:
  - "[[2026-04-07-laci-updater-tool-design|laci-updater-spec]]"
---

# LACI Updater Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file, stdlib-only Python tool that ingests LACI zip drops into any LACI-derivative git repo, preserves consumer customizations via 3-way git merge, and validates the deployed stack via LACI's own shipped test scripts.

**Architecture:** One `laci-update.py` script in `tools/laci-updater/` with four subcommands (`bootstrap`, `absorb`, `status`, `validate`). Uses only Python 3.11+ stdlib plus the `git` and `docker` CLIs on PATH. Development inside Basalt; distribution via zip drop to other workgroup consumers (Basalt, SAIL, SAFE-AI). Tests use `unittest` with synthetic LACI zip fixtures built in `setUp()`; manual integration verification against `D:/BASALT/Basalt-Architecture/laci-24mar/`.

**Tech Stack:** Python 3.11+ stdlib (`argparse`, `zipfile`, `pathlib`, `subprocess`, `json`, `shutil`, `datetime`, `re`, `sys`, `tempfile`, `unittest`). External CLI tools: `git`, `docker`. No pip dependencies.

---

## File Structure

```
tools/laci-updater/
├── laci-update.py              ← single-file shipped tool
├── README.md                   ← end-user docs (ships with tool)
├── CHANGELOG.md                ← version history (ships with tool)
├── build.sh                    ← produces distributable zip (dev-only)
└── tests/
    ├── __init__.py
    ├── fixtures.py             ← synthetic LACI zip builder
    ├── test_helpers.py         ← tests for version detection, classify, git wrapper
    ├── test_bootstrap.py       ← tests for bootstrap subcommand
    ├── test_status.py          ← tests for status subcommand
    ├── test_absorb.py          ← tests for absorb subcommand
    └── test_validate.py        ← tests for validate subcommand
```

**File responsibilities:**

- `laci-update.py` — single script containing all subcommands, helpers, and the `__main__` entry point. ~450 lines target. Every function has a one-line docstring. No OOP unless structurally necessary.
- `tests/fixtures.py` — helpers that build small, realistic LACI-shaped zip files in `tempfile` directories for unit tests.
- `tests/test_*.py` — one file per subcommand + one for shared helpers. Each uses `unittest.TestCase` subclasses.
- `README.md` — one page, mirroring LACI's README style. Usage examples, not philosophy.
- `CHANGELOG.md` — starts at `v0.1.0`.
- `build.sh` — dev-only; invokes `zip` to produce `laci-updater-v0.1.0.zip` containing `laci-update.py`, `README.md`, `CHANGELOG.md` (no tests).

---

## Task Decomposition (Dependency Order)

**Phase 0 — Scaffold**
- Task 1: Create directory structure and empty files
- Task 2: Set up test infrastructure + synthetic zip fixture

**Phase 1 — Shared helpers (tested first)**
- Task 3: `extract_zip()` helper
- Task 4: `detect_laci_version()` helper
- Task 5: `classify_file_action()` helper
- Task 6: `git_*()` subprocess wrappers

**Phase 2 — Bootstrap subcommand**
- Task 7: `argparse` CLI skeleton
- Task 8: `cmd_bootstrap()` implementation

**Phase 3 — Status subcommand**
- Task 9: `cmd_status()` implementation

**Phase 4 — Absorb subcommand**
- Task 10: `compute_file_plan()` helper
- Task 11: `apply_file_plan()` helper
- Task 12: `compute_three_way_diff()` helper
- Task 13: `generate_diff_report()` helper
- Task 14: `cmd_absorb()` wiring

**Phase 5 — Validate subcommand (capstone)**
- Task 15: `discover_compose_stacks()` helper
- Task 16: `check_container_health()` helper
- Task 17: `run_laci_test_scripts()` helper
- Task 18: `cmd_validate()` wiring

**Phase 6 — Packaging and manual verification**
- Task 19: Write README.md
- Task 20: Write build.sh distribution script
- Task 21: Manual integration verification against laci-24mar

---

## Phase 0 — Scaffold

### Task 1: Create directory structure and empty files

**Files:**
- Create: `tools/laci-updater/laci-update.py`
- Create: `tools/laci-updater/README.md`
- Create: `tools/laci-updater/CHANGELOG.md`
- Create: `tools/laci-updater/build.sh`
- Create: `tools/laci-updater/tests/__init__.py`

- [ ] **Step 1: Create the `tools/laci-updater/` directory tree**

Run: `mkdir -p tools/laci-updater/tests`
Expected: directory created (no output)

- [ ] **Step 2: Create the empty script skeleton**

Write `tools/laci-updater/laci-update.py` with initial content:

```python
#!/usr/bin/env python3
"""LACI Updater Tool — absorb LACI zip drops into downstream git repos.

Single-file, stdlib-only. Requires Python 3.11+, git, and docker on PATH.
"""

VERSION = "0.1.0"


def main() -> int:
    """CLI entry point. Returns exit code."""
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
```

- [ ] **Step 3: Create empty CHANGELOG.md**

Write `tools/laci-updater/CHANGELOG.md`:

```markdown
# Changelog

## v0.1.0 (unreleased)

- Initial release
```

- [ ] **Step 4: Create empty README.md placeholder**

Write `tools/laci-updater/README.md`:

```markdown
# LACI Updater

One-line description — full content added in Task 19.
```

- [ ] **Step 5: Create empty build.sh placeholder**

Write `tools/laci-updater/build.sh`:

```bash
#!/usr/bin/env bash
# build.sh — produces the distributable zip. Full content added in Task 20.
set -euo pipefail
echo "TODO: implement in Task 20"
exit 1
```

- [ ] **Step 6: Create empty tests/__init__.py**

Write `tools/laci-updater/tests/__init__.py` with an empty string content (zero-byte file).

- [ ] **Step 7: Verify the script runs**

Run: `python tools/laci-updater/laci-update.py`
Expected: exit 0, no output

- [ ] **Step 8: Commit**

```bash
git add tools/laci-updater/
git commit -m "feat(laci-updater): scaffold directory structure"
```

---

### Task 2: Set up test infrastructure and synthetic zip fixture

**Files:**
- Create: `tools/laci-updater/tests/fixtures.py`
- Create: `tools/laci-updater/tests/test_fixtures.py` (meta-test — verifies the fixture works)

- [ ] **Step 1: Write the failing test for the fixture**

Write `tools/laci-updater/tests/test_fixtures.py`:

```python
"""Meta-tests for the synthetic LACI zip fixture."""
import unittest
import zipfile
from pathlib import Path

from tests.fixtures import build_synthetic_laci_zip


class TestSyntheticLaciZip(unittest.TestCase):
    def test_build_returns_zip_path(self):
        zip_path = build_synthetic_laci_zip(version="v1.0")
        self.assertTrue(zip_path.exists())
        self.assertTrue(zip_path.suffix == ".zip")

    def test_zip_contains_expected_laci_layout(self):
        zip_path = build_synthetic_laci_zip(version="v1.0")
        with zipfile.ZipFile(zip_path) as zf:
            names = set(zf.namelist())
        self.assertIn("laci-stack-v1.0/README", names)
        self.assertIn("laci-stack-v1.0/inference/vllm/docker-compose.yaml", names)
        self.assertIn("laci-stack-v1.0/inference/vllm/.env.example", names)
        self.assertIn("laci-stack-v1.0/inference/vllm/test-vllm.sh", names)
        self.assertIn("laci-stack-v1.0/inference/litellm/docker-compose.yaml", names)
        self.assertIn("laci-stack-v1.0/inference/litellm/test-litellm.sh", names)
        self.assertIn("laci-stack-v1.0/inference/langfuse/docker-compose.yaml", names)
        self.assertIn("laci-stack-v1.0/web/authentik/docker-compose.yaml", names)
        self.assertIn("laci-stack-v1.0/web/open-webui/docker-compose.yaml", names)
        self.assertIn("laci-stack-v1.0/web/onyx/docker-compose.yaml", names)

    def test_version_is_reflected_in_directory_name(self):
        zip_path = build_synthetic_laci_zip(version="v2.5")
        with zipfile.ZipFile(zip_path) as zf:
            names = zf.namelist()
        self.assertTrue(any(n.startswith("laci-stack-v2.5/") for n in names))
        self.assertFalse(any(n.startswith("laci-stack-v1.0/") for n in names))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_fixtures -v`
Expected: `ModuleNotFoundError: No module named 'tests.fixtures'` or `ImportError`

- [ ] **Step 3: Implement the fixture**

Write `tools/laci-updater/tests/fixtures.py`:

```python
"""Build synthetic LACI-shaped zip files for unit testing."""
import tempfile
import zipfile
from pathlib import Path


SYNTHETIC_LACI_FILES = {
    "README": "# LACI Stack\n\nSynthetic fixture for unit tests.\n",
    "inference/vllm/docker-compose.yaml": (
        "services:\n  vllm:\n    image: laci-docker-io/vllm/vllm-openai:v0.17.1\n"
    ),
    "inference/vllm/.env.example": "MODEL_PATH=/models/example\n",
    "inference/vllm/test-vllm.sh": "#!/usr/bin/env bash\necho vllm test\nexit 0\n",
    "inference/litellm/docker-compose.yaml": (
        "services:\n  litellm:\n    image: laci-ghcr-io/berriai/litellm-database:v1.82.0\n"
    ),
    "inference/litellm/.env.example": "LITELLM_MASTER_KEY=\n",
    "inference/litellm/litellm-config.yaml": "model_list: []\n",
    "inference/litellm/test-litellm.sh": "#!/usr/bin/env bash\necho litellm test\nexit 0\n",
    "inference/langfuse/docker-compose.yaml": (
        "services:\n  langfuse:\n    image: laci-docker-io/langfuse/langfuse:v3.0.0\n"
    ),
    "inference/langfuse/.env.example": "TELEMETRY_ENABLED=false\n",
    "web/authentik/docker-compose.yaml": (
        "services:\n  authentik:\n    image: laci-ghcr-io/goauthentik/server:2026.2.1\n"
    ),
    "web/authentik/.env.example": "AUTHENTIK_SECRET_KEY=\n",
    "web/open-webui/docker-compose.yaml": (
        "services:\n  open-webui:\n    image: laci-docker/laci/open-webui:v0.8.10\n"
    ),
    "web/open-webui/.env.example": "WEBUI_AUTH=true\n",
    "web/onyx/docker-compose.yaml": (
        "services:\n  onyx:\n    image: laci-docker/laci/onyx/onyx-backend:v2.0.3\n"
    ),
    "web/onyx/.env.example": "AUTH_TYPE=disabled\n",
    "utils/create-tarball.sh": "#!/usr/bin/env bash\necho create tarball\n",
}


def build_synthetic_laci_zip(version: str = "v1.0", extra_files: dict | None = None) -> Path:
    """Build a synthetic LACI zip file in a temp directory.

    Returns the path to the created zip. Caller is responsible for cleanup.
    """
    tmp_dir = Path(tempfile.mkdtemp(prefix="laci-fixture-"))
    zip_path = tmp_dir / f"laci-stack-{version}.zip"
    top_dir = f"laci-stack-{version}"
    files = dict(SYNTHETIC_LACI_FILES)
    if extra_files:
        files.update(extra_files)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel_path, content in files.items():
            zf.writestr(f"{top_dir}/{rel_path}", content)
    return zip_path
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_fixtures -v`
Expected: 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/tests/fixtures.py tools/laci-updater/tests/test_fixtures.py
git commit -m "test(laci-updater): add synthetic LACI zip fixture"
```

---

## Phase 1 — Shared Helpers

### Task 3: `extract_zip()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py` (add helper function)
- Create: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Write `tools/laci-updater/tests/test_helpers.py`:

```python
"""Tests for shared helper functions in laci-update.py."""
import sys
import tempfile
import unittest
from pathlib import Path

# Import the script as a module by adding the parent dir to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)

from tests.fixtures import build_synthetic_laci_zip


class TestExtractZip(unittest.TestCase):
    def test_extract_returns_top_level_directory(self):
        zip_path = build_synthetic_laci_zip(version="v1.0")
        with tempfile.TemporaryDirectory() as dest:
            dest_path = Path(dest)
            extracted = laci_update.extract_zip(zip_path, dest_path)
            self.assertEqual(extracted.name, "laci-stack-v1.0")
            self.assertTrue(extracted.is_dir())

    def test_extract_contents_match_zip(self):
        zip_path = build_synthetic_laci_zip(version="v1.0")
        with tempfile.TemporaryDirectory() as dest:
            dest_path = Path(dest)
            extracted = laci_update.extract_zip(zip_path, dest_path)
            self.assertTrue((extracted / "README").exists())
            self.assertTrue((extracted / "inference/vllm/docker-compose.yaml").exists())
            self.assertTrue((extracted / "web/authentik/docker-compose.yaml").exists())

    def test_extract_rejects_zip_with_multiple_top_level_dirs(self):
        import zipfile
        tmp_dir = Path(tempfile.mkdtemp())
        bad_zip = tmp_dir / "bad.zip"
        with zipfile.ZipFile(bad_zip, "w") as zf:
            zf.writestr("dir_a/file.txt", "a")
            zf.writestr("dir_b/file.txt", "b")
        with tempfile.TemporaryDirectory() as dest:
            with self.assertRaises(ValueError):
                laci_update.extract_zip(bad_zip, Path(dest))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestExtractZip -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'extract_zip'`

- [ ] **Step 3: Implement `extract_zip()`**

Edit `tools/laci-updater/laci-update.py` — add after the `VERSION` constant:

```python
import zipfile
from pathlib import Path


def extract_zip(zip_path: Path, dest_dir: Path) -> Path:
    """Extract a LACI zip into dest_dir and return the path to its single top-level directory.

    Raises ValueError if the zip contains more than one top-level directory or is empty.
    """
    with zipfile.ZipFile(zip_path) as zf:
        members = zf.namelist()
        top_dirs = {name.split("/", 1)[0] for name in members if "/" in name}
        # Also capture top-level files (no slash) — those shouldn't exist in LACI zips
        top_files = {name for name in members if "/" not in name}
        if len(top_dirs) != 1 or top_files:
            raise ValueError(
                f"Expected exactly one top-level directory in zip, got "
                f"dirs={sorted(top_dirs)} files={sorted(top_files)}"
            )
        zf.extractall(dest_dir)
    return dest_dir / next(iter(top_dirs))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestExtractZip -v`
Expected: 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add extract_zip helper"
```

---

### Task 4: `detect_laci_version()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py` (add helper)
- Modify: `tools/laci-updater/tests/test_helpers.py` (add test class)

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py` (before `if __name__`):

```python
class TestDetectLaciVersion(unittest.TestCase):
    def test_version_from_directory_name(self):
        # Simulate an already-extracted laci directory
        tmp = Path(tempfile.mkdtemp())
        laci_dir = tmp / "laci-stack-v1.1"
        laci_dir.mkdir()
        (laci_dir / "README").write_text("# LACI Stack\n")
        self.assertEqual(laci_update.detect_laci_version(laci_dir), "v1.1")

    def test_version_with_patch_number(self):
        tmp = Path(tempfile.mkdtemp())
        laci_dir = tmp / "laci-stack-v2.3.4"
        laci_dir.mkdir()
        self.assertEqual(laci_update.detect_laci_version(laci_dir), "v2.3.4")

    def test_malformed_directory_name_raises(self):
        tmp = Path(tempfile.mkdtemp())
        bad_dir = tmp / "not-a-laci-dir"
        bad_dir.mkdir()
        with self.assertRaises(ValueError):
            laci_update.detect_laci_version(bad_dir)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestDetectLaciVersion -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'detect_laci_version'`

- [ ] **Step 3: Implement `detect_laci_version()`**

Edit `tools/laci-updater/laci-update.py` — add after `extract_zip`:

```python
import re


_LACI_DIR_PATTERN = re.compile(r"^laci-stack-(v\d+(?:\.\d+)*)$")


def detect_laci_version(laci_dir: Path) -> str:
    """Parse the LACI version string from the extracted directory name.

    Expects a directory named `laci-stack-vX.Y` or `laci-stack-vX.Y.Z`.
    Raises ValueError on malformed names.
    """
    match = _LACI_DIR_PATTERN.match(laci_dir.name)
    if not match:
        raise ValueError(
            f"Cannot detect LACI version from directory name: {laci_dir.name!r}. "
            f"Expected format: laci-stack-vX.Y or laci-stack-vX.Y.Z"
        )
    return match.group(1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestDetectLaciVersion -v`
Expected: 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add detect_laci_version helper"
```

---

### Task 5: `classify_file_action()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestClassifyFileAction(unittest.TestCase):
    def test_env_file_is_skipped(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("inference/vllm/.env")),
            "SKIP",
        )

    def test_env_example_is_updated(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("inference/vllm/.env.example")),
            "UPDATE",
        )

    def test_readme_is_archived(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("README")),
            "ARCHIVE",
        )

    def test_pdf_is_archived(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("LACI_Deployment.pdf")),
            "ARCHIVE",
        )

    def test_xlsx_is_archived(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("LACI_SBOM.xlsx")),
            "ARCHIVE",
        )

    def test_pptx_is_archived(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("LACI_Overview.pptx")),
            "ARCHIVE",
        )

    def test_docker_compose_is_updated(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("inference/vllm/docker-compose.yaml")),
            "UPDATE",
        )

    def test_utils_script_is_updated(self):
        self.assertEqual(
            laci_update.classify_file_action(Path("utils/create-tarball.sh")),
            "UPDATE",
        )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestClassifyFileAction -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'classify_file_action'`

- [ ] **Step 3: Implement `classify_file_action()`**

Edit `tools/laci-updater/laci-update.py` — add after `detect_laci_version`:

```python
_ARCHIVE_EXTENSIONS = {".pdf", ".xlsx", ".pptx"}


def classify_file_action(rel_path: Path) -> str:
    """Classify a file by its path to one of: SKIP, UPDATE, ARCHIVE.

    SKIP   — never touch (e.g., .env files with secrets)
    UPDATE — overlay the new content into the working tree
    ARCHIVE — move to docs/laci/<version>/ instead of overwriting
    """
    name = rel_path.name
    if name == ".env":
        return "SKIP"
    if name == "README":
        return "ARCHIVE"
    if rel_path.suffix in _ARCHIVE_EXTENSIONS:
        return "ARCHIVE"
    return "UPDATE"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestClassifyFileAction -v`
Expected: 8 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add classify_file_action helper"
```

---

### Task 6: Git subprocess wrappers

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
import subprocess


class TestGitWrappers(unittest.TestCase):
    def setUp(self):
        self.repo_dir = Path(tempfile.mkdtemp(prefix="laci-git-test-"))
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@test.local"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.repo_dir, check=True)
        (self.repo_dir / "README.md").write_text("initial\n")
        subprocess.run(["git", "add", "."], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=self.repo_dir, check=True)

    def test_git_current_branch(self):
        self.assertEqual(laci_update.git_current_branch(self.repo_dir), "main")

    def test_git_is_clean_true_on_fresh_repo(self):
        self.assertTrue(laci_update.git_is_clean(self.repo_dir))

    def test_git_is_clean_false_with_modification(self):
        (self.repo_dir / "README.md").write_text("changed\n")
        self.assertFalse(laci_update.git_is_clean(self.repo_dir))

    def test_git_is_clean_false_with_untracked(self):
        (self.repo_dir / "newfile.txt").write_text("new\n")
        self.assertFalse(laci_update.git_is_clean(self.repo_dir))

    def test_git_create_branch(self):
        laci_update.git_create_branch(self.repo_dir, "feature/test")
        self.assertEqual(laci_update.git_current_branch(self.repo_dir), "feature/test")

    def test_git_add_and_commit(self):
        laci_update.git_create_branch(self.repo_dir, "feature/commit-test")
        (self.repo_dir / "newfile.txt").write_text("hello\n")
        laci_update.git_add_all(self.repo_dir)
        laci_update.git_commit(self.repo_dir, "test commit")
        # Verify the commit exists
        log = subprocess.run(
            ["git", "log", "--oneline", "-1"],
            cwd=self.repo_dir, capture_output=True, text=True, check=True,
        ).stdout
        self.assertIn("test commit", log)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestGitWrappers -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'git_current_branch'`

- [ ] **Step 3: Implement git wrappers**

Edit `tools/laci-updater/laci-update.py` — add after `classify_file_action`:

```python
import subprocess


def _git(repo_dir: Path, *args: str, capture: bool = True) -> subprocess.CompletedProcess:
    """Run a git subcommand inside repo_dir and return the CompletedProcess."""
    return subprocess.run(
        ["git", *args],
        cwd=repo_dir,
        capture_output=capture,
        text=True,
        check=True,
    )


def git_current_branch(repo_dir: Path) -> str:
    """Return the current branch name."""
    result = _git(repo_dir, "rev-parse", "--abbrev-ref", "HEAD")
    return result.stdout.strip()


def git_is_clean(repo_dir: Path) -> bool:
    """Return True if the working tree has no modified or untracked files."""
    result = _git(repo_dir, "status", "--porcelain")
    return result.stdout.strip() == ""


def git_create_branch(repo_dir: Path, branch_name: str) -> None:
    """Create and switch to a new branch from current HEAD."""
    _git(repo_dir, "checkout", "-b", branch_name)


def git_add_all(repo_dir: Path) -> None:
    """Stage all changes (tracked + untracked) in the working tree."""
    _git(repo_dir, "add", "-A")


def git_commit(repo_dir: Path, message: str) -> None:
    """Create a commit with the given message."""
    _git(repo_dir, "commit", "-m", message)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestGitWrappers -v`
Expected: 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add git subprocess wrappers"
```

---

## Phase 2 — Bootstrap Subcommand

### Task 7: argparse CLI skeleton

**Files:**
- Modify: `tools/laci-updater/laci-update.py`

- [ ] **Step 1: Write the failing test**

Create `tools/laci-updater/tests/test_cli.py`:

```python
"""Tests for the argparse CLI router."""
import sys
import unittest
from pathlib import Path
import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)


class TestCliRouter(unittest.TestCase):
    def test_no_args_shows_help_and_exits_nonzero(self):
        self.assertNotEqual(laci_update.main([]), 0)

    def test_version_flag(self):
        # --version should exit 0 and print the version
        with self.assertRaises(SystemExit) as ctx:
            laci_update.main(["--version"])
        self.assertEqual(ctx.exception.code, 0)

    def test_unknown_subcommand_errors(self):
        with self.assertRaises(SystemExit):
            laci_update.main(["nosuchcommand"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_cli -v`
Expected: tests fail because `main()` takes no args

- [ ] **Step 3: Implement the CLI skeleton**

Edit `tools/laci-updater/laci-update.py` — replace the existing `main()` function with:

```python
import argparse


def build_parser() -> argparse.ArgumentParser:
    """Build the top-level argparse parser with all subcommands."""
    parser = argparse.ArgumentParser(
        prog="laci-update",
        description="Absorb LACI zip drops into downstream git repos.",
    )
    parser.add_argument(
        "--version", action="version", version=f"laci-update {VERSION}"
    )
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    bootstrap = subparsers.add_parser(
        "bootstrap",
        help="Establish a LACI baseline from a zip (one-time per project).",
    )
    bootstrap.add_argument("zip_path", type=Path, help="Path to a LACI zip file.")

    absorb = subparsers.add_parser(
        "absorb",
        help="Absorb a new LACI zip into the current repo on a new branch.",
    )
    absorb.add_argument("zip_path", type=Path, help="Path to a LACI zip file.")

    subparsers.add_parser(
        "status", help="Show the current LACI baseline and customization state."
    )

    subparsers.add_parser(
        "validate", help="Verify the deployed LACI stack is running correctly."
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        return 1
    # Command dispatch stubs — each replaced in later tasks
    if args.command == "bootstrap":
        return cmd_bootstrap(args)
    if args.command == "absorb":
        return cmd_absorb(args)
    if args.command == "status":
        return cmd_status(args)
    if args.command == "validate":
        return cmd_validate(args)
    return 2


def cmd_bootstrap(args: argparse.Namespace) -> int:
    """Bootstrap subcommand — implemented in Task 8."""
    print("bootstrap: not yet implemented", file=__import__("sys").stderr)
    return 2


def cmd_absorb(args: argparse.Namespace) -> int:
    """Absorb subcommand — implemented in Task 14."""
    print("absorb: not yet implemented", file=__import__("sys").stderr)
    return 2


def cmd_status(args: argparse.Namespace) -> int:
    """Status subcommand — implemented in Task 9."""
    print("status: not yet implemented", file=__import__("sys").stderr)
    return 2


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate subcommand — implemented in Task 18."""
    print("validate: not yet implemented", file=__import__("sys").stderr)
    return 2


if __name__ == "__main__":
    import sys
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_cli -v`
Expected: 3 tests pass

- [ ] **Step 5: Verify help output manually**

Run: `python tools/laci-updater/laci-update.py --help`
Expected: help text listing `bootstrap`, `absorb`, `status`, `validate` subcommands

- [ ] **Step 6: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_cli.py
git commit -m "feat(laci-updater): add argparse CLI skeleton with subcommand stubs"
```

---

### Task 8: `cmd_bootstrap()` implementation

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Create: `tools/laci-updater/tests/test_bootstrap.py`

- [ ] **Step 1: Write the failing test**

Write `tools/laci-updater/tests/test_bootstrap.py`:

```python
"""Tests for the bootstrap subcommand."""
import argparse
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)

from tests.fixtures import build_synthetic_laci_zip


class TestBootstrap(unittest.TestCase):
    def setUp(self):
        self.repo_dir = Path(tempfile.mkdtemp(prefix="laci-bootstrap-test-"))
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@test.local"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.repo_dir, check=True)
        (self.repo_dir / "README.md").write_text("initial\n")
        subprocess.run(["git", "add", "."], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=self.repo_dir, check=True)
        self.zip_path = build_synthetic_laci_zip(version="v1.0")
        # Change CWD to the repo for the duration of the test
        self._old_cwd = Path.cwd()
        import os
        os.chdir(self.repo_dir)

    def tearDown(self):
        import os
        os.chdir(self._old_cwd)

    def test_bootstrap_creates_baseline_directory(self):
        args = argparse.Namespace(command="bootstrap", zip_path=self.zip_path)
        rc = laci_update.cmd_bootstrap(args)
        self.assertEqual(rc, 0)
        self.assertTrue((self.repo_dir / ".laci-baseline").is_dir())
        self.assertTrue((self.repo_dir / ".laci-baseline" / "v1.0").is_dir())

    def test_bootstrap_writes_version_file(self):
        args = argparse.Namespace(command="bootstrap", zip_path=self.zip_path)
        laci_update.cmd_bootstrap(args)
        version_file = self.repo_dir / ".laci-baseline" / "VERSION"
        self.assertTrue(version_file.exists())
        self.assertEqual(version_file.read_text().strip(), "v1.0")

    def test_bootstrap_writes_bootstrap_date_file(self):
        args = argparse.Namespace(command="bootstrap", zip_path=self.zip_path)
        laci_update.cmd_bootstrap(args)
        date_file = self.repo_dir / ".laci-baseline" / "BOOTSTRAP_DATE"
        self.assertTrue(date_file.exists())
        # Format: YYYY-MM-DD
        content = date_file.read_text().strip()
        self.assertRegex(content, r"^\d{4}-\d{2}-\d{2}$")

    def test_bootstrap_copies_laci_files_to_baseline(self):
        args = argparse.Namespace(command="bootstrap", zip_path=self.zip_path)
        laci_update.cmd_bootstrap(args)
        baseline = self.repo_dir / ".laci-baseline" / "v1.0"
        self.assertTrue((baseline / "inference/vllm/docker-compose.yaml").exists())
        self.assertTrue((baseline / "web/authentik/docker-compose.yaml").exists())
        self.assertTrue((baseline / "README").exists())

    def test_bootstrap_refuses_when_baseline_already_exists(self):
        args = argparse.Namespace(command="bootstrap", zip_path=self.zip_path)
        laci_update.cmd_bootstrap(args)
        rc = laci_update.cmd_bootstrap(args)
        self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_bootstrap -v`
Expected: tests fail with exit code 2 (stub not implemented)

- [ ] **Step 3: Implement `cmd_bootstrap()`**

Edit `tools/laci-updater/laci-update.py` — replace the `cmd_bootstrap` stub with:

```python
import shutil
import tempfile
from datetime import date


BASELINE_DIR = ".laci-baseline"


def cmd_bootstrap(args: argparse.Namespace) -> int:
    """Establish a LACI baseline from a zip file (one-time per project)."""
    import sys
    zip_path = args.zip_path.resolve()
    if not zip_path.exists():
        print(f"error: zip not found: {zip_path}", file=sys.stderr)
        return 2

    repo_root = Path.cwd()
    baseline_root = repo_root / BASELINE_DIR
    if baseline_root.exists():
        print(
            f"error: baseline already exists at {baseline_root}. "
            f"Delete it manually if you want to re-bootstrap.",
            file=sys.stderr,
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="laci-bootstrap-") as tmp:
        tmp_path = Path(tmp)
        laci_dir = extract_zip(zip_path, tmp_path)
        version = detect_laci_version(laci_dir)
        baseline_root.mkdir(parents=True)
        version_target = baseline_root / version
        shutil.copytree(laci_dir, version_target)
        (baseline_root / "VERSION").write_text(f"{version}\n")
        (baseline_root / "BOOTSTRAP_DATE").write_text(f"{date.today().isoformat()}\n")

    print(f"Bootstrap complete. Baseline version: {version}")
    print(f"Baseline stored at: {baseline_root}")
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_bootstrap -v`
Expected: 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_bootstrap.py
git commit -m "feat(laci-updater): implement bootstrap subcommand"
```

---

## Phase 3 — Status Subcommand

### Task 9: `cmd_status()` implementation

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Create: `tools/laci-updater/tests/test_status.py`

- [ ] **Step 1: Write the failing test**

Write `tools/laci-updater/tests/test_status.py`:

```python
"""Tests for the status subcommand."""
import argparse
import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)

from tests.fixtures import build_synthetic_laci_zip


class TestStatus(unittest.TestCase):
    def setUp(self):
        self.repo_dir = Path(tempfile.mkdtemp(prefix="laci-status-test-"))
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "t@t.local"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=self.repo_dir, check=True)
        (self.repo_dir / "README.md").write_text("initial\n")
        subprocess.run(["git", "add", "."], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=self.repo_dir, check=True)
        self._old_cwd = Path.cwd()
        os.chdir(self.repo_dir)

    def tearDown(self):
        os.chdir(self._old_cwd)

    def test_status_without_baseline_errors(self):
        args = argparse.Namespace(command="status")
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = laci_update.cmd_status(args)
        self.assertNotEqual(rc, 0)

    def test_status_after_bootstrap_prints_version(self):
        zip_path = build_synthetic_laci_zip(version="v1.0")
        laci_update.cmd_bootstrap(argparse.Namespace(zip_path=zip_path))
        args = argparse.Namespace(command="status")
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = laci_update.cmd_status(args)
        self.assertEqual(rc, 0)
        output = buf.getvalue()
        self.assertIn("v1.0", output)
        self.assertIn("Baseline", output)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_status -v`
Expected: tests fail (stub returns 2)

- [ ] **Step 3: Implement `cmd_status()`**

Edit `tools/laci-updater/laci-update.py` — replace the `cmd_status` stub with:

```python
def cmd_status(args: argparse.Namespace) -> int:
    """Print the current LACI baseline state."""
    import sys
    repo_root = Path.cwd()
    baseline_root = repo_root / BASELINE_DIR
    version_file = baseline_root / "VERSION"
    if not version_file.exists():
        print(
            f"error: no baseline found. Run `bootstrap` first.",
            file=sys.stderr,
        )
        return 2
    version = version_file.read_text().strip()
    bootstrap_date = (baseline_root / "BOOTSTRAP_DATE").read_text().strip() if (baseline_root / "BOOTSTRAP_DATE").exists() else "unknown"

    print(f"LACI Updater v{VERSION}")
    print(f"Baseline version: {version}")
    print(f"Bootstrap date: {bootstrap_date}")
    print(f"Baseline location: {baseline_root}")
    baseline_version_dir = baseline_root / version
    if baseline_version_dir.exists():
        file_count = sum(1 for _ in baseline_version_dir.rglob("*") if _.is_file())
        print(f"Baseline files: {file_count}")
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_status -v`
Expected: 2 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_status.py
git commit -m "feat(laci-updater): implement status subcommand"
```

---

## Phase 4 — Absorb Subcommand

### Task 10: `compute_file_plan()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestComputeFilePlan(unittest.TestCase):
    def test_classifies_add_when_file_only_in_new_drop(self):
        new_files = {Path("inference/vllm/new-thing.yaml")}
        baseline_files: set = set()
        plan = laci_update.compute_file_plan(new_files, baseline_files)
        self.assertEqual(plan["ADD"], {Path("inference/vllm/new-thing.yaml")})

    def test_classifies_remove_when_file_only_in_baseline(self):
        new_files: set = set()
        baseline_files = {Path("inference/vllm/old-thing.yaml")}
        plan = laci_update.compute_file_plan(new_files, baseline_files)
        self.assertEqual(plan["REMOVE"], {Path("inference/vllm/old-thing.yaml")})

    def test_classifies_update_when_file_in_both(self):
        new_files = {Path("inference/vllm/docker-compose.yaml")}
        baseline_files = {Path("inference/vllm/docker-compose.yaml")}
        plan = laci_update.compute_file_plan(new_files, baseline_files)
        self.assertEqual(plan["UPDATE"], {Path("inference/vllm/docker-compose.yaml")})

    def test_skips_env_files(self):
        new_files = {Path("inference/vllm/.env")}
        baseline_files = {Path("inference/vllm/.env")}
        plan = laci_update.compute_file_plan(new_files, baseline_files)
        self.assertEqual(plan["SKIP"], {Path("inference/vllm/.env")})
        self.assertNotIn(Path("inference/vllm/.env"), plan["UPDATE"])

    def test_archives_readme(self):
        new_files = {Path("README")}
        baseline_files = {Path("README")}
        plan = laci_update.compute_file_plan(new_files, baseline_files)
        self.assertEqual(plan["ARCHIVE"], {Path("README")})
        self.assertNotIn(Path("README"), plan["UPDATE"])

    def test_plan_keys_always_present(self):
        plan = laci_update.compute_file_plan(set(), set())
        for key in ("ADD", "REMOVE", "UPDATE", "SKIP", "ARCHIVE"):
            self.assertIn(key, plan)
            self.assertEqual(plan[key], set())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestComputeFilePlan -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'compute_file_plan'`

- [ ] **Step 3: Implement `compute_file_plan()`**

Edit `tools/laci-updater/laci-update.py` — add after `classify_file_action`:

```python
def compute_file_plan(
    new_files: set[Path], baseline_files: set[Path]
) -> dict[str, set[Path]]:
    """Classify every file in the new drop and old baseline into action buckets.

    Returns a dict with keys ADD, REMOVE, UPDATE, SKIP, ARCHIVE — each mapping to a
    set of relative paths.
    """
    plan: dict[str, set[Path]] = {
        "ADD": set(),
        "REMOVE": set(),
        "UPDATE": set(),
        "SKIP": set(),
        "ARCHIVE": set(),
    }
    all_files = new_files | baseline_files
    for rel_path in all_files:
        action = classify_file_action(rel_path)
        in_new = rel_path in new_files
        in_old = rel_path in baseline_files
        if action == "SKIP":
            plan["SKIP"].add(rel_path)
            continue
        if action == "ARCHIVE":
            plan["ARCHIVE"].add(rel_path)
            continue
        # action == UPDATE — refine into ADD/REMOVE/UPDATE based on presence
        if in_new and not in_old:
            plan["ADD"].add(rel_path)
        elif in_old and not in_new:
            plan["REMOVE"].add(rel_path)
        else:
            plan["UPDATE"].add(rel_path)
    return plan
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestComputeFilePlan -v`
Expected: 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add compute_file_plan helper"
```

---

### Task 11: `apply_file_plan()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestApplyFilePlan(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix="laci-apply-test-"))
        (self.work / "inference/vllm").mkdir(parents=True)
        (self.work / "inference/vllm/docker-compose.yaml").write_text("old content\n")
        (self.work / "inference/vllm/.env").write_text("SECRET=keep-me\n")
        (self.work / "inference/vllm/old-file.txt").write_text("to be removed\n")

        self.new_source = Path(tempfile.mkdtemp(prefix="laci-newsrc-"))
        (self.new_source / "inference/vllm").mkdir(parents=True)
        (self.new_source / "inference/vllm/docker-compose.yaml").write_text("new content\n")
        (self.new_source / "inference/vllm/new-file.txt").write_text("added\n")
        (self.new_source / "inference/vllm/.env").write_text("SECRET=OVERWRITE\n")
        (self.new_source / "README").write_text("# LACI README\n")

        self.docs_dir = self.work / "docs"

    def test_apply_updates_existing_file(self):
        plan = {
            "ADD": set(),
            "REMOVE": set(),
            "UPDATE": {Path("inference/vllm/docker-compose.yaml")},
            "SKIP": set(),
            "ARCHIVE": set(),
        }
        laci_update.apply_file_plan(plan, self.new_source, self.work, version="v1.0")
        self.assertEqual(
            (self.work / "inference/vllm/docker-compose.yaml").read_text(),
            "new content\n",
        )

    def test_apply_adds_new_file(self):
        plan = {
            "ADD": {Path("inference/vllm/new-file.txt")},
            "REMOVE": set(),
            "UPDATE": set(),
            "SKIP": set(),
            "ARCHIVE": set(),
        }
        laci_update.apply_file_plan(plan, self.new_source, self.work, version="v1.0")
        self.assertTrue((self.work / "inference/vllm/new-file.txt").exists())

    def test_apply_removes_obsolete_file(self):
        plan = {
            "ADD": set(),
            "REMOVE": {Path("inference/vllm/old-file.txt")},
            "UPDATE": set(),
            "SKIP": set(),
            "ARCHIVE": set(),
        }
        laci_update.apply_file_plan(plan, self.new_source, self.work, version="v1.0")
        self.assertFalse((self.work / "inference/vllm/old-file.txt").exists())

    def test_apply_never_touches_skip_env_files(self):
        plan = {
            "ADD": set(),
            "REMOVE": set(),
            "UPDATE": set(),
            "SKIP": {Path("inference/vllm/.env")},
            "ARCHIVE": set(),
        }
        laci_update.apply_file_plan(plan, self.new_source, self.work, version="v1.0")
        self.assertEqual(
            (self.work / "inference/vllm/.env").read_text(),
            "SECRET=keep-me\n",
        )

    def test_apply_archives_readme_to_docs_laci_version(self):
        plan = {
            "ADD": set(),
            "REMOVE": set(),
            "UPDATE": set(),
            "SKIP": set(),
            "ARCHIVE": {Path("README")},
        }
        laci_update.apply_file_plan(plan, self.new_source, self.work, version="v1.0")
        archived = self.work / "docs/laci/v1.0/README"
        self.assertTrue(archived.exists())
        self.assertEqual(archived.read_text(), "# LACI README\n")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestApplyFilePlan -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'apply_file_plan'`

- [ ] **Step 3: Implement `apply_file_plan()`**

Edit `tools/laci-updater/laci-update.py` — add after `compute_file_plan`:

```python
def apply_file_plan(
    plan: dict[str, set[Path]],
    new_source: Path,
    work_tree: Path,
    version: str,
) -> None:
    """Mutate the working tree according to the file plan.

    - ADD and UPDATE copy from new_source to work_tree
    - REMOVE deletes from work_tree
    - SKIP is a no-op (explicit invariant: never touch .env)
    - ARCHIVE copies to work_tree/docs/laci/<version>/
    """
    for rel_path in plan["ADD"] | plan["UPDATE"]:
        src = new_source / rel_path
        dst = work_tree / rel_path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    for rel_path in plan["REMOVE"]:
        target = work_tree / rel_path
        if target.exists():
            target.unlink()

    # SKIP — intentional no-op

    for rel_path in plan["ARCHIVE"]:
        src = new_source / rel_path
        if not src.exists():
            continue
        dst = work_tree / "docs" / "laci" / version / rel_path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestApplyFilePlan -v`
Expected: 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add apply_file_plan helper"
```

---

### Task 12: `compute_three_way_diff()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestComputeThreeWayDiff(unittest.TestCase):
    def setUp(self):
        self.baseline = Path(tempfile.mkdtemp(prefix="laci-3way-baseline-"))
        self.new_drop = Path(tempfile.mkdtemp(prefix="laci-3way-new-"))
        self.current = Path(tempfile.mkdtemp(prefix="laci-3way-current-"))

    def test_unchanged_file_reports_clean(self):
        for root in (self.baseline, self.new_drop, self.current):
            (root / "x.yaml").write_text("a: 1\n")
        result = laci_update.compute_three_way_diff(
            self.baseline, self.new_drop, self.current
        )
        self.assertEqual(result["clean"], [Path("x.yaml")])
        self.assertEqual(result["upstream_only"], [])
        self.assertEqual(result["downstream_only"], [])
        self.assertEqual(result["conflict"], [])

    def test_upstream_only_change(self):
        (self.baseline / "x.yaml").write_text("a: 1\n")
        (self.new_drop / "x.yaml").write_text("a: 2\n")
        (self.current / "x.yaml").write_text("a: 1\n")
        result = laci_update.compute_three_way_diff(
            self.baseline, self.new_drop, self.current
        )
        self.assertEqual(result["upstream_only"], [Path("x.yaml")])
        self.assertEqual(result["conflict"], [])

    def test_downstream_only_change(self):
        (self.baseline / "x.yaml").write_text("a: 1\n")
        (self.new_drop / "x.yaml").write_text("a: 1\n")
        (self.current / "x.yaml").write_text("a: 99\n")
        result = laci_update.compute_three_way_diff(
            self.baseline, self.new_drop, self.current
        )
        self.assertEqual(result["downstream_only"], [Path("x.yaml")])
        self.assertEqual(result["conflict"], [])

    def test_conflict_both_changed(self):
        (self.baseline / "x.yaml").write_text("a: 1\n")
        (self.new_drop / "x.yaml").write_text("a: 2\n")
        (self.current / "x.yaml").write_text("a: 99\n")
        result = laci_update.compute_three_way_diff(
            self.baseline, self.new_drop, self.current
        )
        self.assertEqual(result["conflict"], [Path("x.yaml")])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestComputeThreeWayDiff -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'compute_three_way_diff'`

- [ ] **Step 3: Implement `compute_three_way_diff()`**

Edit `tools/laci-updater/laci-update.py` — add after `apply_file_plan`:

```python
def _file_hash(path: Path) -> str:
    """Return a content hash string for quick equality checks."""
    import hashlib
    if not path.exists():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compute_three_way_diff(
    baseline: Path, new_drop: Path, current: Path
) -> dict[str, list[Path]]:
    """Classify each shared file as clean / upstream_only / downstream_only / conflict.

    - clean: all three identical
    - upstream_only: baseline == current, but new_drop differs (LACI changed; consumer did not)
    - downstream_only: baseline == new_drop, but current differs (consumer changed; LACI did not)
    - conflict: all three differ (both sides changed)

    Only considers files present in all three trees. ADD/REMOVE structural changes are
    covered by compute_file_plan, not here.
    """
    result: dict[str, list[Path]] = {
        "clean": [],
        "upstream_only": [],
        "downstream_only": [],
        "conflict": [],
    }
    baseline_files = {p.relative_to(baseline) for p in baseline.rglob("*") if p.is_file()}
    new_files = {p.relative_to(new_drop) for p in new_drop.rglob("*") if p.is_file()}
    current_files = {p.relative_to(current) for p in current.rglob("*") if p.is_file()}
    common = baseline_files & new_files & current_files
    for rel in sorted(common):
        b = _file_hash(baseline / rel)
        n = _file_hash(new_drop / rel)
        c = _file_hash(current / rel)
        if b == n == c:
            result["clean"].append(rel)
        elif b == c and n != c:
            result["upstream_only"].append(rel)
        elif b == n and c != n:
            result["downstream_only"].append(rel)
        else:
            result["conflict"].append(rel)
    return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestComputeThreeWayDiff -v`
Expected: 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add compute_three_way_diff helper"
```

---

### Task 13: `generate_diff_report()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestGenerateDiffReport(unittest.TestCase):
    def test_report_contains_all_required_sections(self):
        plan = {
            "ADD": {Path("inference/vllm/new.yaml")},
            "REMOVE": {Path("inference/vllm/old.yaml")},
            "UPDATE": {Path("inference/litellm/docker-compose.yaml")},
            "SKIP": {Path("inference/vllm/.env")},
            "ARCHIVE": {Path("README"), Path("LACI_SBOM.xlsx")},
        }
        three_way = {
            "clean": [Path("inference/langfuse/docker-compose.yaml")],
            "upstream_only": [Path("inference/litellm/docker-compose.yaml")],
            "downstream_only": [],
            "conflict": [],
        }
        report = laci_update.generate_diff_report(
            previous_version="v1.1",
            new_version="v1.2",
            plan=plan,
            three_way=three_way,
            tool_version=laci_update.VERSION,
        )
        # Required headers per spec
        self.assertIn("# LACI Update Report", report)
        self.assertIn("## Summary", report)
        self.assertIn("## Files Added", report)
        self.assertIn("## Files Removed", report)
        self.assertIn("## Files Updated", report)
        self.assertIn("## Image Version Changes", report)
        self.assertIn(".env Template Changes", report)
        self.assertIn("## Likely Conflicts", report)
        self.assertIn("## Structural Warnings", report)
        self.assertIn("## LACI Documentation Archived", report)

    def test_report_lists_added_files(self):
        plan = {
            "ADD": {Path("inference/vllm/new.yaml")},
            "REMOVE": set(), "UPDATE": set(), "SKIP": set(), "ARCHIVE": set(),
        }
        three_way = {"clean": [], "upstream_only": [], "downstream_only": [], "conflict": []}
        report = laci_update.generate_diff_report(
            previous_version="v1.1", new_version="v1.2",
            plan=plan, three_way=three_way, tool_version="0.1.0",
        )
        self.assertIn("inference/vllm/new.yaml", report)

    def test_report_flags_conflicts(self):
        plan = {"ADD": set(), "REMOVE": set(), "UPDATE": set(), "SKIP": set(), "ARCHIVE": set()}
        three_way = {
            "clean": [], "upstream_only": [], "downstream_only": [],
            "conflict": [Path("inference/litellm/litellm-config.yaml")],
        }
        report = laci_update.generate_diff_report(
            previous_version="v1.1", new_version="v1.2",
            plan=plan, three_way=three_way, tool_version="0.1.0",
        )
        self.assertIn("inference/litellm/litellm-config.yaml", report)

    def test_report_has_tool_version(self):
        plan = {"ADD": set(), "REMOVE": set(), "UPDATE": set(), "SKIP": set(), "ARCHIVE": set()}
        three_way = {"clean": [], "upstream_only": [], "downstream_only": [], "conflict": []}
        report = laci_update.generate_diff_report(
            previous_version="v1.1", new_version="v1.2",
            plan=plan, three_way=three_way, tool_version="0.1.0",
        )
        self.assertIn("0.1.0", report)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestGenerateDiffReport -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'generate_diff_report'`

- [ ] **Step 3: Implement `generate_diff_report()`**

Edit `tools/laci-updater/laci-update.py` — add after `compute_three_way_diff`:

```python
def generate_diff_report(
    *,
    previous_version: str,
    new_version: str,
    plan: dict[str, set[Path]],
    three_way: dict[str, list[Path]],
    tool_version: str,
) -> str:
    """Produce a structured markdown diff report for human + agentic-AI consumption."""
    lines: list[str] = []
    lines.append(f"# LACI Update Report — {new_version} ({date.today().isoformat()})")
    lines.append("")
    lines.append("## Summary")
    lines.append(f"- Previous version: {previous_version}")
    lines.append(f"- New version: {new_version}")
    lines.append(f"- Files added: {len(plan['ADD'])}")
    lines.append(f"- Files removed: {len(plan['REMOVE'])}")
    lines.append(f"- Files updated: {len(plan['UPDATE'])}")
    lines.append(f"- LACI docs archived: {len(plan['ARCHIVE'])}")
    lines.append(f"- Upstream-only changes: {len(three_way['upstream_only'])}")
    lines.append(f"- Downstream-only changes: {len(three_way['downstream_only'])}")
    lines.append(f"- Likely conflicts: {len(three_way['conflict'])}")
    lines.append(f"- Tool version: laci-update v{tool_version}")
    lines.append("")

    def _section(title: str, paths: list[Path] | set[Path], empty_note: str = "(none)") -> None:
        lines.append(f"## {title}")
        sorted_paths = sorted(paths, key=lambda p: str(p))
        if not sorted_paths:
            lines.append(empty_note)
        else:
            for p in sorted_paths:
                lines.append(f"- `{p}`")
        lines.append("")

    _section("Files Added (LACI introduces)", plan["ADD"])
    _section("Files Removed (LACI deletes)", plan["REMOVE"])
    _section("Files Updated", plan["UPDATE"])
    _section("Image Version Changes", [], "(detection not implemented in v0.1.0 — review docker-compose.yaml diffs manually)")
    lines.append("## .env Template Changes")
    lines.append("(review `.env.example` diffs in the updated files above)")
    lines.append("")
    _section("Likely Conflicts", three_way["conflict"], "(none detected)")
    _section("Structural Warnings", [], "(none)")
    _section("LACI Documentation Archived", plan["ARCHIVE"])

    return "\n".join(lines) + "\n"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestGenerateDiffReport -v`
Expected: 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add generate_diff_report helper"
```

---

### Task 14: `cmd_absorb()` wiring

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Create: `tools/laci-updater/tests/test_absorb.py`

- [ ] **Step 1: Write the failing test**

Write `tools/laci-updater/tests/test_absorb.py`:

```python
"""Tests for the absorb subcommand."""
import argparse
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)

from tests.fixtures import build_synthetic_laci_zip


class TestAbsorb(unittest.TestCase):
    def setUp(self):
        self.repo_dir = Path(tempfile.mkdtemp(prefix="laci-absorb-test-"))
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "t@t.local"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=self.repo_dir, check=True)
        (self.repo_dir / "README.md").write_text("initial\n")
        subprocess.run(["git", "add", "."], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=self.repo_dir, check=True)
        self._old_cwd = Path.cwd()
        os.chdir(self.repo_dir)
        # Bootstrap with v1.0
        laci_update.cmd_bootstrap(
            argparse.Namespace(zip_path=build_synthetic_laci_zip(version="v1.0"))
        )
        # Commit the bootstrap so absorb branches from a clean state
        subprocess.run(["git", "add", "-A"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "bootstrap"], cwd=self.repo_dir, check=True)

    def tearDown(self):
        os.chdir(self._old_cwd)

    def test_absorb_refuses_dirty_tree(self):
        (self.repo_dir / "dirty.txt").write_text("uncommitted\n")
        zip_path = build_synthetic_laci_zip(version="v1.1")
        rc = laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        self.assertNotEqual(rc, 0)

    def test_absorb_refuses_without_baseline(self):
        # Wipe the baseline to simulate missing bootstrap
        import shutil
        shutil.rmtree(self.repo_dir / ".laci-baseline")
        subprocess.run(["git", "add", "-A"], cwd=self.repo_dir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "remove baseline"], cwd=self.repo_dir, check=True)
        zip_path = build_synthetic_laci_zip(version="v1.1")
        rc = laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        self.assertNotEqual(rc, 0)

    def test_absorb_creates_branch(self):
        zip_path = build_synthetic_laci_zip(version="v1.1")
        rc = laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        self.assertEqual(rc, 0)
        current_branch = laci_update.git_current_branch(self.repo_dir)
        self.assertTrue(current_branch.startswith("laci-update/v1.1-"))

    def test_absorb_updates_baseline_version(self):
        zip_path = build_synthetic_laci_zip(version="v1.1")
        laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        version = (self.repo_dir / ".laci-baseline" / "VERSION").read_text().strip()
        self.assertEqual(version, "v1.1")

    def test_absorb_writes_diff_report(self):
        zip_path = build_synthetic_laci_zip(version="v1.1")
        laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        reports_dir = self.repo_dir / "docs" / "laci-updates"
        self.assertTrue(reports_dir.exists())
        reports = list(reports_dir.glob("*-v1.1-report.md"))
        self.assertEqual(len(reports), 1)

    def test_absorb_archives_readme_to_docs_laci_version(self):
        zip_path = build_synthetic_laci_zip(version="v1.1")
        laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        self.assertTrue((self.repo_dir / "docs/laci/v1.1/README").exists())

    def test_absorb_creates_commit(self):
        zip_path = build_synthetic_laci_zip(version="v1.1")
        laci_update.cmd_absorb(argparse.Namespace(zip_path=zip_path))
        log = subprocess.run(
            ["git", "log", "--oneline", "-1"],
            cwd=self.repo_dir, capture_output=True, text=True, check=True,
        ).stdout
        self.assertIn("v1.1", log)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_absorb -v`
Expected: tests fail (stub returns 2)

- [ ] **Step 3: Implement `cmd_absorb()`**

Edit `tools/laci-updater/laci-update.py` — replace the `cmd_absorb` stub with:

```python
def _rglob_files(root: Path) -> set[Path]:
    """Return a set of file paths relative to root."""
    return {p.relative_to(root) for p in root.rglob("*") if p.is_file()}


def cmd_absorb(args: argparse.Namespace) -> int:
    """Absorb a new LACI zip into the current repo on a new branch."""
    import sys
    zip_path = args.zip_path.resolve()
    if not zip_path.exists():
        print(f"error: zip not found: {zip_path}", file=sys.stderr)
        return 2

    repo_root = Path.cwd()
    baseline_root = repo_root / BASELINE_DIR
    version_file = baseline_root / "VERSION"
    if not version_file.exists():
        print(
            "error: no baseline found. Run `bootstrap` first.",
            file=sys.stderr,
        )
        return 2
    previous_version = version_file.read_text().strip()
    baseline_version_dir = baseline_root / previous_version
    if not baseline_version_dir.exists():
        print(
            f"error: baseline directory missing: {baseline_version_dir}",
            file=sys.stderr,
        )
        return 2

    if not git_is_clean(repo_root):
        print(
            "error: working tree has uncommitted changes. Commit or stash first.",
            file=sys.stderr,
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="laci-absorb-") as tmp:
        tmp_path = Path(tmp)
        laci_dir = extract_zip(zip_path, tmp_path)
        new_version = detect_laci_version(laci_dir)

        # Build the branch name: laci-update/<version>-<YYYY-MM-DD>
        branch_name = f"laci-update/{new_version}-{date.today().isoformat()}"
        git_create_branch(repo_root, branch_name)

        # Enumerate files on each side
        new_files = _rglob_files(laci_dir)
        baseline_files = _rglob_files(baseline_version_dir)

        # Compute the plan + 3-way diff
        plan = compute_file_plan(new_files, baseline_files)
        three_way = compute_three_way_diff(
            baseline_version_dir, laci_dir, repo_root
        )

        # Apply the plan to the working tree
        apply_file_plan(plan, laci_dir, repo_root, version=new_version)

        # Update the baseline
        shutil.rmtree(baseline_version_dir)
        new_baseline_target = baseline_root / new_version
        shutil.copytree(laci_dir, new_baseline_target)
        version_file.write_text(f"{new_version}\n")

        # Write the diff report
        reports_dir = repo_root / "docs" / "laci-updates"
        reports_dir.mkdir(parents=True, exist_ok=True)
        report_path = reports_dir / f"{date.today().isoformat()}-{new_version}-report.md"
        report_text = generate_diff_report(
            previous_version=previous_version,
            new_version=new_version,
            plan=plan,
            three_way=three_way,
            tool_version=VERSION,
        )
        report_path.write_text(report_text)

    git_add_all(repo_root)
    git_commit(
        repo_root,
        f"Absorb LACI {new_version} ({len(plan['UPDATE'])} updated, "
        f"{len(plan['ADD'])} added, {len(plan['REMOVE'])} removed)",
    )

    print(f"✅ Absorbed LACI {new_version} on branch {branch_name}")
    print(f"Next steps:")
    print(f"  1. Review the diff report: docs/laci-updates/{date.today().isoformat()}-{new_version}-report.md")
    print(f"  2. Push the branch: git push -u origin {branch_name}")
    print(f"  3. Open a PR in your git platform")
    print(f"  4. After merging, pull any new images listed in the report")
    print(f"  5. Start the stack and run `laci-update validate`")
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_absorb -v`
Expected: 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_absorb.py
git commit -m "feat(laci-updater): implement absorb subcommand"
```

---

## Phase 5 — Validate Subcommand (Capstone)

### Task 15: `discover_compose_stacks()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestDiscoverComposeStacks(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="laci-discover-"))
        (self.root / "inference/vllm").mkdir(parents=True)
        (self.root / "inference/vllm/docker-compose.yaml").write_text("services: {}\n")
        (self.root / "inference/litellm").mkdir(parents=True)
        (self.root / "inference/litellm/docker-compose.yaml").write_text("services: {}\n")
        (self.root / "web/authentik").mkdir(parents=True)
        (self.root / "web/authentik/docker-compose.yaml").write_text("services: {}\n")
        # A decoy compose file outside inference/ and web/ — should be ignored
        (self.root / "decoy").mkdir()
        (self.root / "decoy/docker-compose.yaml").write_text("services: {}\n")

    def test_discovers_inference_and_web_stacks(self):
        stacks = laci_update.discover_compose_stacks(self.root)
        stack_paths = sorted(s.relative_to(self.root).as_posix() for s in stacks)
        self.assertEqual(stack_paths, [
            "inference/litellm",
            "inference/vllm",
            "web/authentik",
        ])

    def test_returns_empty_for_non_laci_repo(self):
        empty = Path(tempfile.mkdtemp(prefix="laci-empty-"))
        stacks = laci_update.discover_compose_stacks(empty)
        self.assertEqual(stacks, [])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestDiscoverComposeStacks -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'discover_compose_stacks'`

- [ ] **Step 3: Implement `discover_compose_stacks()`**

Edit `tools/laci-updater/laci-update.py` — add after `generate_diff_report`:

```python
def discover_compose_stacks(repo_root: Path) -> list[Path]:
    """Return sorted list of directories under inference/ and web/ containing docker-compose.yaml."""
    stacks: list[Path] = []
    for top in ("inference", "web"):
        top_dir = repo_root / top
        if not top_dir.is_dir():
            continue
        for entry in sorted(top_dir.iterdir()):
            if entry.is_dir() and (entry / "docker-compose.yaml").exists():
                stacks.append(entry)
    return stacks
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestDiscoverComposeStacks -v`
Expected: 2 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add discover_compose_stacks helper"
```

---

### Task 16: `check_container_health()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
class TestCheckContainerHealth(unittest.TestCase):
    def test_parses_healthy_containers(self):
        # Simulated `docker compose ps --format json` output — one JSON object per line
        raw_output = (
            '{"Name": "vllm-1", "State": "running", "Health": "healthy"}\n'
        )
        result = laci_update.parse_compose_ps_output(raw_output)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["Name"], "vllm-1")
        self.assertTrue(laci_update.is_container_ok(result[0]))

    def test_parses_running_without_healthcheck(self):
        raw_output = '{"Name": "redis", "State": "running", "Health": ""}\n'
        result = laci_update.parse_compose_ps_output(raw_output)
        self.assertTrue(laci_update.is_container_ok(result[0]))

    def test_parses_starting_as_not_ok(self):
        raw_output = '{"Name": "vllm-1", "State": "running", "Health": "starting"}\n'
        result = laci_update.parse_compose_ps_output(raw_output)
        self.assertFalse(laci_update.is_container_ok(result[0]))

    def test_parses_unhealthy_as_not_ok(self):
        raw_output = '{"Name": "vllm-1", "State": "running", "Health": "unhealthy"}\n'
        result = laci_update.parse_compose_ps_output(raw_output)
        self.assertFalse(laci_update.is_container_ok(result[0]))

    def test_parses_empty_output(self):
        self.assertEqual(laci_update.parse_compose_ps_output(""), [])

    def test_parses_multiple_containers(self):
        raw_output = (
            '{"Name": "litellm", "State": "running", "Health": "healthy"}\n'
            '{"Name": "postgres", "State": "running", "Health": "healthy"}\n'
            '{"Name": "redis", "State": "running", "Health": ""}\n'
        )
        result = laci_update.parse_compose_ps_output(raw_output)
        self.assertEqual(len(result), 3)
        self.assertTrue(all(laci_update.is_container_ok(c) for c in result))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestCheckContainerHealth -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'parse_compose_ps_output'`

- [ ] **Step 3: Implement the parser and check functions**

Edit `tools/laci-updater/laci-update.py` — add after `discover_compose_stacks`:

```python
import json
import time


def parse_compose_ps_output(raw: str) -> list[dict]:
    """Parse `docker compose ps --format json` output (newline-delimited JSON)."""
    result: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        result.append(json.loads(line))
    return result


def is_container_ok(container: dict) -> bool:
    """True if a container is considered operational.

    A container passes if:
      - State == 'running' AND
      - Health is 'healthy' OR empty (no healthcheck defined)

    Returns False for 'starting', 'unhealthy', or any non-running state.
    """
    if container.get("State") != "running":
        return False
    health = container.get("Health", "")
    return health in ("", "healthy")


def check_stack_health(stack_dir: Path, wait_seconds: int = 60) -> dict:
    """Run `docker compose ps --format json` in stack_dir and classify containers.

    If any containers are in `starting` state, poll up to wait_seconds before returning.
    Returns: {'stack': <path>, 'containers': [...], 'ok': bool}
    """
    deadline = time.monotonic() + wait_seconds
    while True:
        proc = subprocess.run(
            ["docker", "compose", "ps", "--format", "json"],
            cwd=stack_dir, capture_output=True, text=True, check=False,
        )
        if proc.returncode != 0:
            return {"stack": stack_dir, "containers": [], "ok": False, "error": proc.stderr.strip()}
        containers = parse_compose_ps_output(proc.stdout)
        any_starting = any(
            c.get("Health") == "starting" for c in containers
        )
        if not any_starting or time.monotonic() >= deadline:
            ok = bool(containers) and all(is_container_ok(c) for c in containers)
            return {"stack": stack_dir, "containers": containers, "ok": ok}
        time.sleep(2)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestCheckContainerHealth -v`
Expected: 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add container health check helpers"
```

---

### Task 17: `run_laci_test_scripts()` helper

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Modify: `tools/laci-updater/tests/test_helpers.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/laci-updater/tests/test_helpers.py`:

```python
import stat


class TestRunLaciTestScripts(unittest.TestCase):
    def setUp(self):
        self.stack = Path(tempfile.mkdtemp(prefix="laci-teststack-"))
        (self.stack / "docker-compose.yaml").write_text("services: {}\n")

    def _write_script(self, name: str, content: str) -> Path:
        path = self.stack / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        return path

    def test_passing_script_reports_success(self):
        self._write_script("test-foo.sh", "#!/usr/bin/env bash\nexit 0\n")
        results = laci_update.run_laci_test_scripts(self.stack)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["exit_code"], 0)
        self.assertTrue(results[0]["passed"])

    def test_failing_script_reports_failure(self):
        self._write_script("test-foo.sh", "#!/usr/bin/env bash\necho boom\nexit 1\n")
        results = laci_update.run_laci_test_scripts(self.stack)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["exit_code"], 1)
        self.assertFalse(results[0]["passed"])
        self.assertIn("boom", results[0]["output"])

    def test_no_scripts_returns_empty(self):
        results = laci_update.run_laci_test_scripts(self.stack)
        self.assertEqual(results, [])

    def test_multiple_scripts_all_run(self):
        self._write_script("test-a.sh", "#!/usr/bin/env bash\nexit 0\n")
        self._write_script("test-b.sh", "#!/usr/bin/env bash\nexit 0\n")
        results = laci_update.run_laci_test_scripts(self.stack)
        self.assertEqual(len(results), 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestRunLaciTestScripts -v`
Expected: `AttributeError: module 'laci_update' has no attribute 'run_laci_test_scripts'`

- [ ] **Step 3: Implement `run_laci_test_scripts()`**

Edit `tools/laci-updater/laci-update.py` — add after `check_stack_health`:

```python
def run_laci_test_scripts(stack_dir: Path) -> list[dict]:
    """Execute any test-*.sh scripts in stack_dir and return per-script results.

    Each result dict: {'script': Path, 'exit_code': int, 'output': str, 'passed': bool}
    """
    results: list[dict] = []
    for script in sorted(stack_dir.glob("test-*.sh")):
        proc = subprocess.run(
            ["bash", str(script)],
            cwd=stack_dir, capture_output=True, text=True, check=False,
        )
        output = (proc.stdout + proc.stderr).strip()
        # Keep the last 10 lines for the validation report
        last_lines = "\n".join(output.splitlines()[-10:])
        results.append({
            "script": script,
            "exit_code": proc.returncode,
            "output": last_lines,
            "passed": proc.returncode == 0,
        })
    return results
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_helpers.TestRunLaciTestScripts -v`
Expected: 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_helpers.py
git commit -m "feat(laci-updater): add run_laci_test_scripts helper"
```

---

### Task 18: `cmd_validate()` wiring

**Files:**
- Modify: `tools/laci-updater/laci-update.py`
- Create: `tools/laci-updater/tests/test_validate.py`

- [ ] **Step 1: Write the failing test**

Write `tools/laci-updater/tests/test_validate.py`:

```python
"""Tests for the validate subcommand.

These tests exercise the validate codepath WITHOUT a live docker daemon by
monkeypatching check_stack_health to return synthetic results. A real docker
integration test is handled by Task 21 manual verification.
"""
import argparse
import os
import sys
import tempfile
import unittest
from pathlib import Path
import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_spec = importlib.util.spec_from_file_location(
    "laci_update", Path(__file__).resolve().parents[1] / "laci-update.py"
)
laci_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(laci_update)


class TestValidate(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="laci-validate-"))
        for stack in ("inference/vllm", "inference/litellm", "web/authentik"):
            (self.repo / stack).mkdir(parents=True)
            (self.repo / stack / "docker-compose.yaml").write_text("services: {}\n")
        self._old_cwd = Path.cwd()
        os.chdir(self.repo)

        # Patch check_stack_health for the test
        self._real_check = laci_update.check_stack_health
        self._real_run_scripts = laci_update.run_laci_test_scripts

        def _fake_check_all_ok(stack_dir, wait_seconds=60):
            return {
                "stack": stack_dir,
                "containers": [{"Name": "c", "State": "running", "Health": "healthy"}],
                "ok": True,
            }

        def _fake_check_fail(stack_dir, wait_seconds=60):
            return {
                "stack": stack_dir,
                "containers": [{"Name": "c", "State": "running", "Health": "unhealthy"}],
                "ok": False,
            }

        def _fake_run_scripts_ok(stack_dir):
            return [{"script": stack_dir / "test.sh", "exit_code": 0, "output": "ok", "passed": True}]

        self._fake_check_all_ok = _fake_check_all_ok
        self._fake_check_fail = _fake_check_fail
        self._fake_run_scripts_ok = _fake_run_scripts_ok

    def tearDown(self):
        os.chdir(self._old_cwd)
        laci_update.check_stack_health = self._real_check
        laci_update.run_laci_test_scripts = self._real_run_scripts

    def test_validate_exits_zero_on_all_healthy(self):
        laci_update.check_stack_health = self._fake_check_all_ok
        laci_update.run_laci_test_scripts = lambda d: []  # no scripts
        rc = laci_update.cmd_validate(argparse.Namespace())
        self.assertEqual(rc, 0)

    def test_validate_exits_nonzero_on_unhealthy_stack(self):
        laci_update.check_stack_health = self._fake_check_fail
        laci_update.run_laci_test_scripts = lambda d: []
        rc = laci_update.cmd_validate(argparse.Namespace())
        self.assertNotEqual(rc, 0)

    def test_validate_writes_report(self):
        laci_update.check_stack_health = self._fake_check_all_ok
        laci_update.run_laci_test_scripts = lambda d: []
        laci_update.cmd_validate(argparse.Namespace())
        reports = list((self.repo / "docs" / "laci-updates").glob("*-validation.md"))
        self.assertEqual(len(reports), 1)

    def test_validate_exits_two_on_no_stacks(self):
        # Empty repo with no stacks
        empty = Path(tempfile.mkdtemp())
        os.chdir(empty)
        rc = laci_update.cmd_validate(argparse.Namespace())
        self.assertEqual(rc, 2)
        os.chdir(self.repo)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/laci-updater && python -m unittest tests.test_validate -v`
Expected: tests fail (stub returns 2 always)

- [ ] **Step 3: Implement `cmd_validate()`**

Edit `tools/laci-updater/laci-update.py` — replace the `cmd_validate` stub with:

```python
def _write_validation_report(
    *,
    report_path: Path,
    tool_version: str,
    stack_results: list[dict],
    script_results: list[dict],
    overall_pass: bool,
) -> None:
    """Write the validation report to disk."""
    lines: list[str] = []
    lines.append(f"# LACI Validation Report ({date.today().isoformat()})")
    lines.append("")
    lines.append("## Summary")
    lines.append(f"- Tool version: laci-update v{tool_version}")
    lines.append(f"- Overall result: {'✅ PASS' if overall_pass else '❌ FAIL'}")
    lines.append("")
    lines.append("## Stage 1: Container Health")
    lines.append("| Stack | Containers | Healthy | Result |")
    lines.append("|---|---|---|---|")
    for r in stack_results:
        total = len(r["containers"])
        healthy = sum(1 for c in r["containers"] if is_container_ok(c))
        status = "✅" if r["ok"] else "❌"
        lines.append(f"| `{r['stack'].name}` | {total} | {healthy} | {status} |")
    lines.append("")
    lines.append("## Stage 2: LACI Test Scripts")
    if not script_results:
        lines.append("(no test-*.sh scripts found or Stage 2 skipped)")
    else:
        lines.append("| Script | Exit Code | Result |")
        lines.append("|---|---|---|")
        for s in script_results:
            status = "✅ PASS" if s["passed"] else "❌ FAIL"
            lines.append(f"| `{s['script'].name}` | {s['exit_code']} | {status} |")
    lines.append("")
    lines.append("## Failures")
    failing_stacks = [r for r in stack_results if not r["ok"]]
    failing_scripts = [s for s in script_results if not s["passed"]]
    if not failing_stacks and not failing_scripts:
        lines.append("(none)")
    for r in failing_stacks:
        lines.append(f"### Stack: {r['stack'].name}")
        for c in r["containers"]:
            if not is_container_ok(c):
                lines.append(f"- Container `{c.get('Name')}` — State: {c.get('State')}, Health: {c.get('Health') or '(none)'}")
    for s in failing_scripts:
        lines.append(f"### Script: {s['script'].name}")
        lines.append("```")
        lines.append(s["output"])
        lines.append("```")
    lines.append("")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines) + "\n")


def cmd_validate(args: argparse.Namespace) -> int:
    """Verify the deployed LACI stack is operational."""
    import sys
    repo_root = Path.cwd()
    stacks = discover_compose_stacks(repo_root)
    if not stacks:
        print("error: no LACI compose stacks found under inference/ or web/", file=sys.stderr)
        return 2

    print(f"LACI Updater v{VERSION}")
    print(f"Found {len(stacks)} stacks")
    print("")
    print("Stage 1: Container health checks")

    stack_results: list[dict] = []
    any_unhealthy = False
    for stack in stacks:
        result = check_stack_health(stack)
        stack_results.append(result)
        rel = stack.relative_to(repo_root).as_posix()
        if result["ok"]:
            healthy = sum(1 for c in result["containers"] if is_container_ok(c))
            total = len(result["containers"])
            print(f"  {rel}: ✅ {healthy}/{total} healthy")
        else:
            any_unhealthy = True
            print(f"  {rel}: ❌ see report for details")

    script_results: list[dict] = []
    if any_unhealthy:
        print("")
        print("Stage 2: SKIPPED (Stage 1 failures)")
    else:
        print("")
        print("Stage 2: LACI shipped test scripts")
        for stack in stacks:
            # Only run test scripts for inference/ stacks per spec
            if "inference" not in stack.parts:
                continue
            results = run_laci_test_scripts(stack)
            for r in results:
                script_results.append(r)
                status = "✅ PASS" if r["passed"] else f"❌ FAIL (exit {r['exit_code']})"
                rel_script = r["script"].relative_to(repo_root).as_posix()
                print(f"  {rel_script}: {status}")

    overall_pass = (not any_unhealthy) and all(s["passed"] for s in script_results)
    report_path = (
        repo_root / "docs" / "laci-updates" /
        f"{date.today().isoformat()}-validation.md"
    )
    _write_validation_report(
        report_path=report_path,
        tool_version=VERSION,
        stack_results=stack_results,
        script_results=script_results,
        overall_pass=overall_pass,
    )
    print("")
    print(f"Validation report: {report_path.relative_to(repo_root)}")
    if overall_pass:
        print("✅ All checks passed.")
        return 0
    print("❌ Validation failed. Review the report and container logs.")
    return 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/laci-updater && python -m unittest tests.test_validate -v`
Expected: 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add tools/laci-updater/laci-update.py tools/laci-updater/tests/test_validate.py
git commit -m "feat(laci-updater): implement validate subcommand"
```

---

## Phase 6 — Packaging and Manual Verification

### Task 19: Write the shipped README.md

**Files:**
- Modify: `tools/laci-updater/README.md`

- [ ] **Step 1: Write README content**

Replace `tools/laci-updater/README.md` with:

````markdown
# LACI Updater

Single-file Python tool that absorbs LACI Platform zip drops into downstream git repos while preserving consumer customizations.

## Requirements

- Python 3.11 or newer
- `git` on PATH
- `docker` on PATH (for the `validate` subcommand only)

No `pip install` needed — stdlib only.

## Installation

Drop `laci-update.py` into your repo's `tools/` directory:

```
<your-repo>/
└── tools/
    └── laci-update.py
```

## Usage

### First-time bootstrap (one-time per project)

```bash
python tools/laci-update.py bootstrap /path/to/laci-24mar.zip
```

Creates `.laci-baseline/<version>/` with an unmodified copy of LACI files and records the version.

### Absorb a new LACI update

```bash
python tools/laci-update.py absorb /path/to/laci-25apr.zip
```

1. Creates a new git branch `laci-update/<version>-<date>`
2. Overlays new LACI files (never touching `.env` files)
3. Archives LACI docs (`README`, `*.pdf`, `*.xlsx`, `*.pptx`) to `docs/laci/<version>/`
4. Writes a diff report to `docs/laci-updates/<date>-<version>-report.md`
5. Commits everything
6. Updates the baseline

Next: push the branch, open a PR in your git platform, review, merge, pull any new images, start the stack.

### Status

```bash
python tools/laci-update.py status
```

Prints the current baseline version, date, and file count.

### Validate deployment

```bash
python tools/laci-update.py validate
```

After the stack is running, runs two validation stages:

1. Container health checks for every compose stack under `inference/` and `web/`
2. LACI's shipped `test-*.sh` scripts in each `inference/` stack

Writes a report to `docs/laci-updates/<date>-validation.md` and exits non-zero on failure.

## Behavior

- **`.env` files are never overwritten.** Your secrets stay safe.
- **Dirty working tree is refused.** Commit or stash before `absorb`.
- **Bootstrap fails if a baseline already exists.** Delete `.laci-baseline/` manually to re-bootstrap.
- **No network calls.** Air-gap safe.

## Exit codes

- `0` — success
- `1` — validation failure
- `2` — setup error (missing zip, no baseline, dirty tree, no stacks, etc.)

## Version

Run `python tools/laci-update.py --version` to see the current tool version.
````

- [ ] **Step 2: Verify the README is readable**

Run: `cat tools/laci-updater/README.md | head -20`
Expected: the first 20 lines of the README

- [ ] **Step 3: Commit**

```bash
git add tools/laci-updater/README.md
git commit -m "docs(laci-updater): add shipped README"
```

---

### Task 20: Write the build.sh distribution script

**Files:**
- Modify: `tools/laci-updater/build.sh`

- [ ] **Step 1: Replace build.sh with the real script**

Replace `tools/laci-updater/build.sh` with:

```bash
#!/usr/bin/env bash
# build.sh — produce a distributable zip of the LACI Updater tool.
#
# Output: tools/laci-updater/dist/laci-updater-v<VERSION>.zip
# Contents: laci-update.py, README.md, CHANGELOG.md (no tests, no build.sh)
set -euo pipefail

cd "$(dirname "$0")"

# Extract VERSION from laci-update.py
VERSION=$(python -c 'import re; print(re.search(r"VERSION = \"([^\"]+)\"", open("laci-update.py").read()).group(1))')

if [[ -z "$VERSION" ]]; then
    echo "error: could not extract VERSION from laci-update.py" >&2
    exit 1
fi

DIST_DIR="dist"
STAGING_DIR="$DIST_DIR/laci-updater-v${VERSION}"
ZIP_NAME="laci-updater-v${VERSION}.zip"

rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

cp laci-update.py "$STAGING_DIR/"
cp README.md "$STAGING_DIR/"
cp CHANGELOG.md "$STAGING_DIR/"

(cd "$DIST_DIR" && zip -qr "$ZIP_NAME" "laci-updater-v${VERSION}")
rm -rf "$STAGING_DIR"

echo "✅ Built: tools/laci-updater/$DIST_DIR/$ZIP_NAME"
ls -la "$DIST_DIR/$ZIP_NAME"
```

- [ ] **Step 2: Make build.sh executable**

Run: `chmod +x tools/laci-updater/build.sh`

- [ ] **Step 3: Run build.sh**

Run: `tools/laci-updater/build.sh`
Expected: `✅ Built: tools/laci-updater/dist/laci-updater-v0.1.0.zip` and the zip file listed

- [ ] **Step 4: Verify the zip contains the right files**

Run: `unzip -l tools/laci-updater/dist/laci-updater-v0.1.0.zip`
Expected: 3 files inside `laci-updater-v0.1.0/`: `laci-update.py`, `README.md`, `CHANGELOG.md`

- [ ] **Step 5: Add dist/ to .gitignore**

Edit `.gitignore` — append:

```
# LACI updater build output
tools/laci-updater/dist/
```

- [ ] **Step 6: Commit**

```bash
git add tools/laci-updater/build.sh .gitignore
git commit -m "build(laci-updater): add distribution zip build script"
```

---

### Task 21: Manual integration verification against laci-24mar

**Files:**
- Create: `tools/laci-updater/MANUAL-VERIFICATION.md`

- [ ] **Step 1: Run the full test suite**

Run: `cd tools/laci-updater && python -m unittest discover tests -v`
Expected: all tests pass, no failures, no errors

- [ ] **Step 2: Manually bootstrap against the real LACI drop**

From the Basalt repo root:

```bash
# Move the pre-existing laci-baseline out of the way if Basalt already has one
ls .laci-baseline 2>/dev/null && mv .laci-baseline .laci-baseline.manual-backup || true

# First zip the existing extracted LACI dir to match the tool's expected input
(cd /d/BASALT/Basalt-Architecture/laci-24mar && zip -qr /tmp/laci-stack-v1.1.zip laci-stack-v1.1)

python tools/laci-updater/laci-update.py bootstrap /tmp/laci-stack-v1.1.zip
```

Expected: `Bootstrap complete. Baseline version: v1.1`

- [ ] **Step 3: Verify the baseline was created**

Run: `python tools/laci-updater/laci-update.py status`
Expected: prints version `v1.1`, bootstrap date (today), file count > 0

- [ ] **Step 4: Verify the baseline contents look correct**

Run: `find .laci-baseline/v1.1 -type f | head -20`
Expected: files under `inference/`, `web/`, `utils/`, plus `README`

- [ ] **Step 5: Clean up and restore**

```bash
rm -rf .laci-baseline
# Restore the original baseline if there was one
[ -d .laci-baseline.manual-backup ] && mv .laci-baseline.manual-backup .laci-baseline || true
rm /tmp/laci-stack-v1.1.zip
```

- [ ] **Step 6: Write the manual verification checklist to disk**

Write `tools/laci-updater/MANUAL-VERIFICATION.md`:

```markdown
# Manual Integration Verification Checklist

This checklist complements the automated unit tests. Unit tests run fast against synthetic LACI fixtures; manual verification exercises the tool against real LACI drops on the dev machine.

## Pre-flight

- [ ] All automated tests pass: `python -m unittest discover tests -v`
- [ ] A real LACI drop exists at `D:/BASALT/Basalt-Architecture/laci-<date>/`
- [ ] The drop is already extracted to a `laci-stack-vX.Y/` subdirectory

## Bootstrap flow

- [ ] Zip the extracted dir: `(cd D:/BASALT/Basalt-Architecture/laci-<date> && zip -qr /tmp/laci.zip laci-stack-vX.Y)`
- [ ] Run: `python tools/laci-updater/laci-update.py bootstrap /tmp/laci.zip`
- [ ] Verify: `.laci-baseline/VERSION` contains the expected version
- [ ] Verify: `.laci-baseline/<version>/` contains the LACI files
- [ ] Run `status` and verify the printed metadata

## Absorb flow (requires two LACI drops)

- [ ] Bootstrap with the older drop
- [ ] Commit the bootstrap: `git add -A && git commit -m "bootstrap baseline"`
- [ ] Run `absorb` with the newer drop
- [ ] Verify a new branch was created: `git branch`
- [ ] Verify the diff report exists: `ls docs/laci-updates/`
- [ ] Review the diff report for sanity (sections populated, paths correct)
- [ ] Verify `docs/laci/<version>/README` exists (archived LACI README)
- [ ] Verify `.laci-baseline/VERSION` now reflects the newer version

## Validate flow (requires live stack)

- [ ] Start the stack: follow CLAUDE.md startup sequence
- [ ] Wait for all containers to report healthy
- [ ] Run: `python tools/laci-updater/laci-update.py validate`
- [ ] Verify: exits 0 when everything is healthy
- [ ] Verify: `docs/laci-updates/<date>-validation.md` was written
- [ ] Stop one container (e.g., `docker stop vllm-vllm-1`), re-run validate
- [ ] Verify: exits non-zero, report identifies the failed container
```

- [ ] **Step 7: Commit**

```bash
git add tools/laci-updater/MANUAL-VERIFICATION.md
git commit -m "docs(laci-updater): add manual integration verification checklist"
```

---

## Self-Review Pass (check against the spec)

After completing Task 21, verify the plan covered every spec requirement:

### Goal coverage
- ✅ Goal 1 (tool-specific configuration preserved) — Task 11 (apply_file_plan skips `.env`), Task 14 (absorb creates branch for 3-way merge)
- ✅ Goal 2 (single-command workflow) — Task 7 (argparse), Task 14 (absorb wiring)
- ✅ Goal 3 (zero per-project configuration) — no config file loading anywhere; verified by absence
- ✅ Goal 4 (single-file distribution) — Task 20 (build.sh produces zip with just 3 files)
- ✅ Goal 5 (deployment validation) — Tasks 15-18
- ✅ Goal 6 (air-gap safe, stdlib only) — every task uses only stdlib; verified by absence of pip deps

### File classification rules coverage
- ✅ `.env` SKIP — Task 5 + Task 11
- ✅ `.env.example` UPDATE — Task 5
- ✅ `docker-compose.yaml` UPDATE — Task 5 (default case)
- ✅ `README`/`*.pdf`/`*.xlsx`/`*.pptx` ARCHIVE — Task 5
- ✅ ADD/REMOVE structural classification — Task 10

### Output directory structure coverage
- ✅ `.laci-baseline/VERSION` + `BOOTSTRAP_DATE` — Task 8
- ✅ `.laci-baseline/<version>/` snapshot — Task 8 (bootstrap) + Task 14 (absorb updates)
- ✅ `docs/laci/<version>/` archived docs — Task 11
- ✅ `docs/laci-updates/<date>-<version>-report.md` — Task 14
- ✅ `docs/laci-updates/<date>-validation.md` — Task 18

### Validation spec coverage
- ✅ Stage 1 container health — Tasks 15, 16, 18
- ✅ Stage 2 LACI test scripts — Task 17, 18
- ✅ 60-second starting wait cap — Task 16
- ✅ Stage 2 skipped if Stage 1 fails — Task 18
- ✅ Inspect-only (no lifecycle management) — verified by absence of `docker compose up` calls
- ✅ Exit code 0/1/2 semantics — Tasks 8, 9, 14, 18

### Out-of-scope adherence (things that MUST NOT be implemented)
- ❌ Repository restructuring — no `os.rename` of existing dirs anywhere
- ❌ Docker image pulls — no `docker pull` calls
- ❌ Stack lifecycle management — validate only inspects, never starts/stops
- ❌ LACI doc generation — no README templating
- ❌ Per-project documentation cleanup — no edits to repo docs beyond `docs/laci/` and `docs/laci-updates/`
- ❌ PR creation — no git platform API calls
- ❌ Structural auto-relocation — moved files surface in the diff report as "structural warnings" placeholder

### Placeholder scan
- No "TBD" — verified by the concrete code in every task
- No "TODO" except the `laci-update.py` `(detection not implemented in v0.1.0)` note inside the diff report section, which is an intentional v1 limitation documented in the report output

### Type consistency
- All helpers use `Path` for filesystem args
- `dict[str, set[Path]]` for plans is consistent across Tasks 10, 11, 13, 14
- `list[dict]` for container/script results is consistent across Tasks 16, 17, 18
- `str` for version strings is consistent (e.g., `"v1.1"`)

---

## Tool Size Estimate

After all 21 tasks land, `laci-update.py` will be approximately **450-500 lines** of Python (under the 500-line target in the spec). Tests will total ~600-800 lines across 6 test files. The shipped zip will be ~15 KB (script + README + CHANGELOG).

---

## Deferred to future versions (NOT in v0.1.0)

These were explicitly scoped out during the brainstorm and are not implemented by this plan:

- Level 3 validation (HTTP endpoint probes per service)
- Level 4 validation (end-to-end inference tracing)
- Image version diff detection in reports (currently a placeholder note in `generate_diff_report`)
- `.env.example` new-var detection in diff reports
- Structural warnings for LACI path moves
- `--wait N` flag for validate's starting-container patience
- `--force` flag for absorb against a dirty tree
- Bootstrap from current state (no zip) fallback

Track these as follow-on work once v0.1.0 proves itself in real use.
