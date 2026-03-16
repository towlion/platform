"""Tests for the Towlion spec conformance validator."""

import os
import sys

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
