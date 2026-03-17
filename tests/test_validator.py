"""Tests for the Towlion spec conformance validator."""

import os
import subprocess
import sys
from unittest.mock import patch, MagicMock

import pytest

# Add the project root to the path so we can import the validator
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from validator.validate import Validator, Result

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
VALID_APP = os.path.join(FIXTURES_DIR, "valid-app")
INVALID_APP = os.path.join(FIXTURES_DIR, "invalid-app")


def run_validator(app_dir: str, tier: int = 2, strict: bool = False) -> Validator:
    """Run the validator and return it for inspection."""
    v = Validator(app_dir=app_dir, tier=tier, strict=strict)
    v.run()
    return v


def get_results(validator: Validator) -> dict[str, list[str]]:
    """Group result check names by status."""
    grouped: dict[str, list[str]] = {}
    for status, check, _detail in validator.results:
        grouped.setdefault(status, []).append(check)
    return grouped


def has_result(validator: Validator, status: str, check_substring: str) -> bool:
    """Check if validator has a result matching the given status and check substring."""
    return any(
        s == status and check_substring in c
        for s, c, _ in validator.results
    )


class TestTier1Structure:
    def test_valid_app_passes_tier1(self):
        v = run_validator(VALID_APP, tier=1)
        results = get_results(v)
        assert Result.FAIL not in results, f"Unexpected failures: {results.get(Result.FAIL)}"

    def test_missing_dockerfile_fails_tier1(self):
        v = run_validator(INVALID_APP, tier=1)
        assert has_result(v, Result.FAIL, "app/Dockerfile")

    def test_missing_directories_fail_tier1(self):
        v = run_validator(INVALID_APP, tier=1)
        assert has_result(v, Result.FAIL, "Directory: .github/workflows/")
        assert has_result(v, Result.FAIL, "Directory: scripts/")

    def test_missing_required_files_fail_tier1(self):
        v = run_validator(INVALID_APP, tier=1)
        assert has_result(v, Result.FAIL, "docker-compose.yml")
        assert has_result(v, Result.FAIL, "health-check.sh")


class TestTier2Content:
    def test_valid_app_passes_tier2(self):
        v = run_validator(VALID_APP, tier=2)
        results = get_results(v)
        assert Result.FAIL not in results, f"Unexpected failures: {results.get(Result.FAIL)}"

    def test_missing_database_url_fails_tier2(self):
        v = run_validator(INVALID_APP, tier=2)
        assert has_result(v, Result.FAIL, "DATABASE_URL")

    def test_missing_redis_url_fails_tier2(self):
        v = run_validator(INVALID_APP, tier=2)
        assert has_result(v, Result.FAIL, "REDIS_URL")

    def test_hardcoded_secret_detected_tier2(self):
        v = run_validator(INVALID_APP, tier=2)
        assert has_result(v, Result.FAIL, "No hardcoded secrets")

    def test_valid_app_env_template_has_required_vars(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "APP_DOMAIN")
        assert has_result(v, Result.PASS, "DATABASE_URL")
        assert has_result(v, Result.PASS, "REDIS_URL")

    def test_valid_app_has_fastapi(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "FastAPI")

    def test_valid_app_has_dependencies(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "fastapi")
        assert has_result(v, Result.PASS, "uvicorn")

    def test_valid_app_env_has_jwt_secret(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "JWT_SECRET")

    def test_missing_jwt_secret_warns(self):
        v = run_validator(INVALID_APP, tier=2)
        assert has_result(v, Result.WARN, "JWT_SECRET")


class TestStrictMode:
    def test_strict_mode_treats_warnings_as_errors(self):
        v = Validator(app_dir=VALID_APP, tier=1, strict=True)
        exit_code = v.run()
        # valid-app has optional frontend warning, so strict should fail
        results = get_results(v)
        if Result.WARN in results:
            assert exit_code == 1

    def test_non_strict_mode_allows_warnings(self):
        v = Validator(app_dir=VALID_APP, tier=1, strict=False)
        exit_code = v.run()
        assert exit_code == 0


class TestTier2DockerfileSecurity:
    def _make_app(self, tmp_path, dockerfile_content):
        """Create minimal app structure with given Dockerfile."""
        (tmp_path / "app").mkdir()
        (tmp_path / "app" / "Dockerfile").write_text(dockerfile_content)
        (tmp_path / "app" / "main.py").write_text('from fastapi import FastAPI\napp = FastAPI()\n@app.get("/health")\ndef h(): return {"status":"ok"}')
        (tmp_path / "deploy").mkdir()
        (tmp_path / "deploy" / "docker-compose.yml").write_text("services:\n  app:\n    build: .\n    healthcheck:\n      test: curl http://localhost:8000/health\n")
        (tmp_path / "deploy" / "docker-compose.standalone.yml").write_text("services:\n  app:\n    build: .\n    ports:\n      - '8000:8000'\n")
        (tmp_path / "deploy" / "Caddyfile").write_text("{$APP_DOMAIN}\nreverse_proxy app:8000\n")
        (tmp_path / "deploy" / "env.template").write_text("APP_DOMAIN=x\nDATABASE_URL=x\nREDIS_URL=x\nJWT_SECRET=x\n")
        (tmp_path / ".github" / "workflows").mkdir(parents=True)
        (tmp_path / ".github" / "workflows" / "deploy.yml").write_text("on: push\n")
        (tmp_path / "scripts").mkdir()
        (tmp_path / "scripts" / "health-check.sh").write_text("#!/bin/sh\n")
        (tmp_path / "README.md").write_text("# App\n")
        (tmp_path / "requirements.txt").write_text("fastapi\nuvicorn\n")

    def test_dockerfile_with_user_passes(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "Dockerfile sets USER")

    def test_dockerfile_without_user_warns(self, tmp_path):
        self._make_app(tmp_path, "FROM python:3.12-slim\nWORKDIR /app\nCMD ['python']\n")
        v = run_validator(str(tmp_path), tier=2)
        assert has_result(v, Result.WARN, "Dockerfile sets USER")

    def test_dockerfile_add_url_warns(self, tmp_path):
        self._make_app(tmp_path, "FROM python:3.12-slim\nADD https://example.com/file.tar.gz /app/\nUSER app\nCMD ['python']\n")
        v = run_validator(str(tmp_path), tier=2)
        assert has_result(v, Result.WARN, "Dockerfile ADD from URL")

    def test_dockerfile_env_secret_warns(self, tmp_path):
        self._make_app(tmp_path, "FROM python:3.12-slim\nENV DB_PASSWORD=hunter2\nUSER app\nCMD ['python']\n")
        v = run_validator(str(tmp_path), tier=2)
        assert has_result(v, Result.WARN, "Dockerfile ENV secrets")

    def test_dockerfile_missing_skips(self, tmp_path):
        self._make_app(tmp_path, "")
        os.remove(tmp_path / "app" / "Dockerfile")
        v = run_validator(str(tmp_path), tier=2)
        assert has_result(v, Result.SKIP, "Dockerfile security")


class TestTier2ComposeHardening:
    def test_resource_limits_present(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "Resource limits configured")

    def test_resource_limits_missing_warns(self, tmp_path):
        (tmp_path / "deploy").mkdir()
        (tmp_path / "deploy" / "docker-compose.yml").write_text("services:\n  app:\n    build: .\n    healthcheck:\n      test: curl http://localhost:8000/health\n")
        v = Validator(app_dir=str(tmp_path), tier=2, strict=False)
        v._check_resource_limits()
        assert has_result(v, Result.WARN, "Resource limits configured")

    def test_read_only_fs_present(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "Read-only filesystem enabled")

    def test_read_only_fs_missing_warns(self, tmp_path):
        (tmp_path / "deploy").mkdir()
        (tmp_path / "deploy" / "docker-compose.yml").write_text("services:\n  app:\n    build: .\n")
        v = Validator(app_dir=str(tmp_path), tier=2, strict=False)
        v._check_read_only_fs()
        assert has_result(v, Result.WARN, "Read-only filesystem enabled")


class TestTier2AlembicConfig:
    def test_alembic_with_config_passes(self):
        v = run_validator(VALID_APP, tier=2)
        assert has_result(v, Result.PASS, "Alembic config present")

    def test_alembic_without_config_warns(self, tmp_path):
        (tmp_path / "requirements.txt").write_text("fastapi\nalembic\n")
        v = Validator(app_dir=str(tmp_path), tier=2, strict=False)
        v._check_alembic_config()
        assert has_result(v, Result.WARN, "Alembic config present")

    def test_no_alembic_dep_skips(self, tmp_path):
        (tmp_path / "requirements.txt").write_text("fastapi\nuvicorn\n")
        v = Validator(app_dir=str(tmp_path), tier=2, strict=False)
        v._check_alembic_config()
        assert has_result(v, Result.SKIP, "Alembic config")


class TestTier3WithMocking:
    """Tier 3 tests using mocked subprocess.run — no Docker required."""

    def _make_mock_result(self, returncode=0, stdout="", stderr=""):
        mock = MagicMock()
        mock.returncode = returncode
        mock.stdout = stdout
        mock.stderr = stderr
        return mock

    @patch("subprocess.run")
    def test_compose_config_pass(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=0)
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_compose_config()
        assert has_result(v, Result.PASS, "docker compose config validates")

    @patch("subprocess.run")
    def test_compose_config_fail(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=1, stderr="invalid yaml")
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_compose_config()
        assert has_result(v, Result.FAIL, "docker compose config validates")

    @patch("subprocess.run")
    def test_container_build_pass(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=0)
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_container_build()
        assert has_result(v, Result.PASS, "Container builds successfully")

    @patch("subprocess.run")
    def test_container_build_fail(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=1, stderr="build error")
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_container_build()
        assert has_result(v, Result.FAIL, "Container builds successfully")

    def test_container_build_missing_skips(self, tmp_path):
        v = Validator(app_dir=str(tmp_path), tier=3, strict=False)
        v._check_container_build()
        assert has_result(v, Result.SKIP, "Container build")

    @patch("subprocess.run")
    def test_docker_not_available_skips_all(self, mock_run):
        mock_run.side_effect = FileNotFoundError("docker not found")
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v.check_runtime()
        assert has_result(v, Result.SKIP, "Docker available")
        assert len(v.results) == 1

    @patch("subprocess.run")
    def test_frontend_build_pass(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=0)
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_frontend_build()
        # valid-app has no frontend, so it should skip
        assert has_result(v, Result.SKIP, "Frontend build")

    def test_frontend_build_missing_skips(self, tmp_path):
        v = Validator(app_dir=str(tmp_path), tier=3, strict=False)
        v._check_frontend_build()
        assert has_result(v, Result.SKIP, "Frontend build")

    @patch("subprocess.run")
    def test_standalone_compose_config_pass(self, mock_run):
        mock_run.return_value = self._make_mock_result(returncode=0)
        v = Validator(app_dir=VALID_APP, tier=3, strict=False)
        v._check_standalone_compose_config()
        assert has_result(v, Result.PASS, "Standalone compose config validates")

    def test_standalone_compose_config_missing_skips(self, tmp_path):
        v = Validator(app_dir=str(tmp_path), tier=3, strict=False)
        v._check_standalone_compose_config()
        assert has_result(v, Result.SKIP, "Standalone compose config")
