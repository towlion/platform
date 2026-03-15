#!/usr/bin/env python3
"""Towlion Spec Conformance Validator.

Validates that an application repository conforms to the Towlion platform
specification (docs/spec.md, Spec Version 1.0).

Usage:
    python validator/validate.py [--tier 1|2|3] [--strict] [--dir PATH]
"""

import argparse
import os
import re
import subprocess
import sys

SPEC_VERSION = "1.0"

# ANSI color codes
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
GRAY = "\033[90m"
RESET = "\033[0m"
BOLD = "\033[1m"

# Disable colors if not a TTY
if not sys.stdout.isatty():
    GREEN = RED = YELLOW = GRAY = RESET = BOLD = ""


class Result:
    PASS = "PASS"
    FAIL = "FAIL"
    WARN = "WARN"
    SKIP = "SKIP"


class Validator:
    def __init__(self, app_dir: str, tier: int, strict: bool):
        self.app_dir = os.path.abspath(app_dir)
        self.tier = tier
        self.strict = strict
        self.results: list[tuple[str, str, str]] = []  # (status, check, detail)

    def _path(self, *parts: str) -> str:
        return os.path.join(self.app_dir, *parts)

    def _exists(self, *parts: str) -> bool:
        return os.path.exists(self._path(*parts))

    def _read(self, *parts: str) -> str | None:
        path = self._path(*parts)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except (OSError, IOError):
            return None

    def _record(self, status: str, check: str, detail: str = ""):
        self.results.append((status, check, detail))
        color = {
            Result.PASS: GREEN,
            Result.FAIL: RED,
            Result.WARN: YELLOW,
            Result.SKIP: GRAY,
        }.get(status, "")
        tag = f"{color}{status:4s}{RESET}"
        msg = f"  {tag}  {check}"
        if detail:
            msg += f" — {detail}"
        print(msg)

    # ── Tier 1: Structure ──────────────────────────────────────────────

    def check_structure(self):
        print(f"\n{BOLD}Tier 1 — Structure{RESET}")

        required_dirs = ["app", "deploy", ".github/workflows", "scripts"]
        for d in required_dirs:
            if os.path.isdir(self._path(d)):
                self._record(Result.PASS, f"Directory: {d}/")
            else:
                self._record(Result.FAIL, f"Directory: {d}/", "missing")

        required_files = [
            "deploy/docker-compose.yml",
            "deploy/docker-compose.standalone.yml",
            "deploy/Caddyfile",
            "deploy/env.template",
            ".github/workflows/deploy.yml",
            "scripts/health-check.sh",
            "README.md",
        ]
        for f in required_files:
            if self._exists(f):
                self._record(Result.PASS, f"File: {f}")
            else:
                self._record(Result.FAIL, f"File: {f}", "missing")

        # Dockerfiles
        if self._exists("app", "Dockerfile"):
            self._record(Result.PASS, "File: app/Dockerfile")
        else:
            self._record(Result.FAIL, "File: app/Dockerfile", "missing")

        # Optional: frontend
        if os.path.isdir(self._path("frontend")):
            self._record(Result.PASS, "Directory: frontend/ (optional)")
            if self._exists("frontend", "Dockerfile"):
                self._record(Result.PASS, "File: frontend/Dockerfile")
            else:
                self._record(Result.WARN, "File: frontend/Dockerfile", "frontend/ exists but no Dockerfile")
        else:
            self._record(Result.WARN, "Directory: frontend/ (optional)", "not present")

    # ── Tier 2: Content ────────────────────────────────────────────────

    def check_content(self):
        print(f"\n{BOLD}Tier 2 — Content{RESET}")

        self._check_compose()
        self._check_env_template()
        self._check_caddyfile()
        self._check_main_py()
        self._check_dependencies()
        self._check_secrets()

    def _check_compose(self):
        content = self._read("deploy", "docker-compose.yml")
        if content is None:
            self._record(Result.SKIP, "docker-compose.yml content", "file missing")
            return

        # Try YAML parsing if available
        yaml_valid = self._validate_yaml(content, "docker-compose.yml")

        if "8000" in content:
            self._record(Result.PASS, "docker-compose.yml references port 8000")
        else:
            self._record(Result.FAIL, "docker-compose.yml references port 8000", "port 8000 not found")

        if re.search(r"healthcheck", content, re.IGNORECASE):
            self._record(Result.PASS, "docker-compose.yml has healthcheck")
        else:
            self._record(Result.FAIL, "docker-compose.yml has healthcheck", "no healthcheck block found")

    def _validate_yaml(self, content: str, filename: str) -> bool:
        try:
            import yaml
            yaml.safe_load(content)
            self._record(Result.PASS, f"{filename} is valid YAML")
            return True
        except ImportError:
            # Fallback: basic structure check
            if content.strip() and not content.strip().startswith("{"):
                # Looks like YAML (has key: value patterns)
                if re.search(r"^\w[\w\-]*:", content, re.MULTILINE):
                    self._record(Result.PASS, f"{filename} appears to be valid YAML (PyYAML not available for full validation)")
                    return True
            self._record(Result.WARN, f"{filename} YAML validation", "PyYAML not installed, could not fully validate")
            return False
        except Exception as e:
            self._record(Result.FAIL, f"{filename} is valid YAML", str(e))
            return False

    def _check_env_template(self):
        content = self._read("deploy", "env.template")
        if content is None:
            self._record(Result.SKIP, "env.template content", "file missing")
            return

        required_vars = ["APP_DOMAIN", "DATABASE_URL", "REDIS_URL"]
        for var in required_vars:
            if var in content:
                self._record(Result.PASS, f"env.template contains {var}")
            else:
                self._record(Result.FAIL, f"env.template contains {var}", "not found")

    def _check_caddyfile(self):
        content = self._read("deploy", "Caddyfile")
        if content is None:
            self._record(Result.SKIP, "Caddyfile content", "file missing")
            return

        if "reverse_proxy" in content:
            self._record(Result.PASS, "Caddyfile contains reverse_proxy")
        else:
            self._record(Result.FAIL, "Caddyfile contains reverse_proxy", "not found")

        if "8000" in content:
            self._record(Result.PASS, "Caddyfile references port 8000")
        else:
            self._record(Result.FAIL, "Caddyfile references port 8000", "not found")

    def _check_main_py(self):
        content = self._read("app", "main.py")
        if content is None:
            self._record(Result.FAIL, "app/main.py exists", "missing")
            return

        self._record(Result.PASS, "app/main.py exists")
        if "FastAPI" in content:
            self._record(Result.PASS, "app/main.py contains FastAPI")
        else:
            self._record(Result.FAIL, "app/main.py contains FastAPI", "not found")

    def _check_dependencies(self):
        # Find the deps file
        deps_content = None
        deps_file = None

        if self._exists("requirements.txt"):
            deps_content = self._read("requirements.txt")
            deps_file = "requirements.txt"
        elif self._exists("pyproject.toml"):
            deps_content = self._read("pyproject.toml")
            deps_file = "pyproject.toml"

        if deps_content is None:
            self._record(Result.FAIL, "Dependencies file", "neither requirements.txt nor pyproject.toml found")
            return

        self._record(Result.PASS, f"Dependencies file: {deps_file}")

        content_lower = deps_content.lower()
        if "fastapi" in content_lower:
            self._record(Result.PASS, f"{deps_file} contains fastapi")
        else:
            self._record(Result.FAIL, f"{deps_file} contains fastapi", "not found")

        if "uvicorn" in content_lower:
            self._record(Result.PASS, f"{deps_file} contains uvicorn")
        else:
            self._record(Result.FAIL, f"{deps_file} contains uvicorn", "not found")

        if "alembic" in content_lower:
            self._record(Result.PASS, f"{deps_file} contains alembic")
        else:
            self._record(Result.WARN, f"{deps_file} contains alembic", "not found (only needed if using database migrations)")

    def _check_secrets(self):
        secret_patterns = [
            (r'(?i)password\s*=\s*["\'][^"\']+["\']', "hardcoded password"),
            (r'(?i)secret\s*=\s*["\'][^"\']+["\']', "hardcoded secret"),
            (r'(?i)api[_-]?key\s*=\s*["\'][^"\']+["\']', "hardcoded API key"),
            (r'(?i)token\s*=\s*["\'][^"\']+["\']', "hardcoded token"),
            (r'AKIA[0-9A-Z]{16}', "AWS access key"),
        ]
        issues: list[str] = []

        for root, _dirs, files in os.walk(self.app_dir):
            # Skip hidden dirs, node_modules, __pycache__, .git
            rel_root = os.path.relpath(root, self.app_dir)
            skip = False
            for part in rel_root.split(os.sep):
                if part.startswith(".") or part in ("node_modules", "__pycache__", "venv", ".venv"):
                    skip = True
                    break
            if skip:
                continue

            for fname in files:
                if not fname.endswith((".py", ".yml", ".yaml", ".toml", ".cfg", ".ini", ".json", ".sh", ".env")):
                    continue
                # Skip env.template (it's expected to have placeholder values)
                if fname == "env.template":
                    continue
                fpath = os.path.join(root, fname)
                try:
                    with open(fpath, encoding="utf-8", errors="replace") as f:
                        content = f.read()
                except (OSError, IOError):
                    continue

                rel_path = os.path.relpath(fpath, self.app_dir)
                for pattern, label in secret_patterns:
                    matches = re.findall(pattern, content)
                    if matches:
                        issues.append(f"{rel_path}: {label}")

        if issues:
            for issue in issues:
                self._record(Result.FAIL, "No hardcoded secrets", issue)
        else:
            self._record(Result.PASS, "No hardcoded secrets detected")

    # ── Tier 3: Runtime ────────────────────────────────────────────────

    def check_runtime(self):
        print(f"\n{BOLD}Tier 3 — Runtime{RESET}")

        # Check Docker is available
        try:
            subprocess.run(
                ["docker", "version"],
                capture_output=True,
                timeout=10,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            self._record(Result.SKIP, "Docker available", "docker not found or not responding")
            return

        self._check_compose_config()
        self._check_container_build()
        self._check_health_endpoint()

    def _check_compose_config(self):
        compose_path = self._path("deploy", "docker-compose.yml")
        if not os.path.exists(compose_path):
            self._record(Result.SKIP, "docker compose config", "file missing")
            return

        result = subprocess.run(
            ["docker", "compose", "-f", compose_path, "config"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            self._record(Result.PASS, "docker compose config validates")
        else:
            self._record(Result.FAIL, "docker compose config validates", result.stderr.strip()[:200])

    def _check_container_build(self):
        dockerfile = self._path("app", "Dockerfile")
        if not os.path.exists(dockerfile):
            self._record(Result.SKIP, "Container build", "app/Dockerfile missing")
            return

        result = subprocess.run(
            ["docker", "build", "-f", dockerfile, "-t", "towlion-validate-test", self._path("app")],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode == 0:
            self._record(Result.PASS, "Container builds successfully")
        else:
            self._record(Result.FAIL, "Container builds successfully", result.stderr.strip()[:200])

    def _check_health_endpoint(self):
        import json
        import time
        import urllib.request
        import urllib.error

        compose_path = self._path("deploy", "docker-compose.yml")
        if not os.path.exists(compose_path):
            self._record(Result.SKIP, "Health endpoint", "compose file missing")
            return

        # Start the containers
        start = subprocess.run(
            ["docker", "compose", "-f", compose_path, "up", "-d"],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=self.app_dir,
        )
        if start.returncode != 0:
            self._record(Result.SKIP, "Health endpoint", f"failed to start containers: {start.stderr.strip()[:200]}")
            return

        try:
            # Wait for service to be ready (up to 30 seconds)
            health_ok = False
            for _ in range(15):
                time.sleep(2)
                try:
                    req = urllib.request.Request("http://localhost:8000/health")
                    with urllib.request.urlopen(req, timeout=5) as resp:
                        status = resp.status
                        body = resp.read().decode("utf-8", errors="replace")
                        if status == 200:
                            try:
                                data = json.loads(body)
                                if data.get("status") == "ok":
                                    self._record(Result.PASS, "GET /health returns 200 with {\"status\": \"ok\"}")
                                    health_ok = True
                                    break
                                else:
                                    self._record(Result.FAIL, "Health endpoint response", f"unexpected body: {body[:100]}")
                                    health_ok = True  # Got a response, just wrong body
                                    break
                            except json.JSONDecodeError:
                                self._record(Result.FAIL, "Health endpoint response", f"invalid JSON: {body[:100]}")
                                health_ok = True
                                break
                        else:
                            self._record(Result.FAIL, "Health endpoint HTTP status", f"got {status}, expected 200")
                            health_ok = True
                            break
                except urllib.error.URLError:
                    continue
                except Exception:
                    continue

            if not health_ok:
                self._record(Result.FAIL, "Health endpoint", "service did not respond within 30 seconds")
        finally:
            # Always tear down
            subprocess.run(
                ["docker", "compose", "-f", compose_path, "down"],
                capture_output=True,
                timeout=30,
                cwd=self.app_dir,
            )

    # ── Run ────────────────────────────────────────────────────────────

    def run(self) -> int:
        print(f"{BOLD}Towlion Spec Validator v{SPEC_VERSION}{RESET}")
        print(f"Validating: {self.app_dir}")
        print(f"Tier: {self.tier} | Strict: {self.strict}")

        self.check_structure()

        if self.tier >= 2:
            self.check_content()

        if self.tier >= 3:
            self.check_runtime()

        return self._summary()

    def _summary(self) -> int:
        passed = sum(1 for s, _, _ in self.results if s == Result.PASS)
        failed = sum(1 for s, _, _ in self.results if s == Result.FAIL)
        warned = sum(1 for s, _, _ in self.results if s == Result.WARN)
        skipped = sum(1 for s, _, _ in self.results if s == Result.SKIP)

        print(f"\n{BOLD}Summary:{RESET} {GREEN}{passed} passed{RESET}, {RED}{failed} failed{RESET}, {YELLOW}{warned} warnings{RESET}", end="")
        if skipped:
            print(f", {GRAY}{skipped} skipped{RESET}")
        else:
            print()

        if failed > 0:
            return 1
        if self.strict and warned > 0:
            return 1
        return 0


def main():
    parser = argparse.ArgumentParser(
        description="Validate an app repo against the Towlion platform spec."
    )
    parser.add_argument(
        "--tier",
        type=int,
        choices=[1, 2, 3],
        default=2,
        help="Validation tier: 1=structure, 2=content, 3=runtime (default: 2)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors",
    )
    parser.add_argument(
        "--dir",
        default=".",
        help="Path to the app repo to validate (default: current directory)",
    )
    args = parser.parse_args()

    validator = Validator(app_dir=args.dir, tier=args.tier, strict=args.strict)
    sys.exit(validator.run())


if __name__ == "__main__":
    main()
