# ABOUTME: unit tests for the pure logic in the morning-login credential refresher
# ABOUTME: aws/gcloud config is synthesised as text; no real credentials are read

import importlib.machinery
import types
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "morning-login"


def _load():
    """Import the extensionless script as a module."""
    loader = importlib.machinery.SourceFileLoader("morning_login", str(SCRIPT))
    module = types.ModuleType(loader.name)
    module.__file__ = str(SCRIPT)
    loader.exec_module(module)
    return module


ml = _load()


AWS_CONFIG = """
[default]
region = us-east-1

[sso-session acme]
sso_start_url = https://example.awsapps.com/start/#
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile alpha-dev]
sso_session = acme
sso_account_id = 111111111111
sso_role_name = developers

[profile beta-dev]
sso_session = acme
sso_account_id = 222222222222
sso_role_name = developers
"""


class TestResolveAwsTarget:
    def test_picks_the_first_profile_backed_by_an_sso_session(self):
        target = ml.resolve_aws_target(AWS_CONFIG)
        assert target.profile == "alpha-dev"
        assert target.session == "acme"
        assert target.start_url == "https://example.awsapps.com/start/#"

    def test_named_profile_overrides_the_first(self):
        target = ml.resolve_aws_target(AWS_CONFIG, profile="beta-dev")
        assert target.profile == "beta-dev"
        assert target.session == "acme"

    def test_returns_none_when_no_profile_uses_sso(self):
        assert ml.resolve_aws_target("[profile local]\nregion = us-east-1\n") is None

    def test_returns_none_when_the_named_profile_is_absent(self):
        assert ml.resolve_aws_target(AWS_CONFIG, profile="nope") is None

    def test_ignores_a_profile_whose_sso_session_is_not_defined(self):
        config = "[profile orphan]\nsso_session = missing\n"
        assert ml.resolve_aws_target(config) is None


class TestAdcQuotaProject:
    def test_reads_the_pinned_quota_project(self):
        adc = '{"type": "authorized_user", "quota_project_id": "some-project"}'
        assert ml.adc_quota_project(adc) == "some-project"

    def test_returns_none_when_no_quota_project_is_pinned(self):
        assert ml.adc_quota_project('{"type": "authorized_user"}') is None

    def test_returns_none_for_unparseable_json(self):
        assert ml.adc_quota_project("not json at all") is None

    def test_returns_none_for_an_empty_file(self):
        assert ml.adc_quota_project("") is None


TOKEN = {
    "startUrl": "https://example.awsapps.com/start/#",
    "accessToken": "irrelevant",
    "expiresAt": "2026-09-11T16:24:13Z",
}

REGISTRATION = {
    "clientId": "abc",
    "issuerUrl": "https://example.awsapps.com/start/#",
    "expiresAt": "2026-11-22T13:53:46Z",
}


class TestSsoTokenExpiry:
    def test_finds_the_expiry_for_a_matching_start_url(self):
        expiry = ml.sso_token_expiry([TOKEN], "https://example.awsapps.com/start/#")
        assert expiry == datetime(2026, 9, 11, 16, 24, 13, tzinfo=timezone.utc)

    def test_matches_across_a_trailing_hash_difference(self):
        expiry = ml.sso_token_expiry([TOKEN], "https://example.awsapps.com/start/")
        assert expiry == datetime(2026, 9, 11, 16, 24, 13, tzinfo=timezone.utc)

    def test_ignores_client_registrations_that_hold_no_access_token(self):
        assert ml.sso_token_expiry([REGISTRATION], TOKEN["startUrl"]) is None

    def test_returns_none_when_no_entry_matches(self):
        assert ml.sso_token_expiry([TOKEN], "https://other.awsapps.com/start/") is None

    def test_returns_none_when_the_matching_entry_has_no_expiry(self):
        entries = [{"startUrl": "https://example.awsapps.com/start/", "accessToken": "x"}]
        assert ml.sso_token_expiry(entries, "https://example.awsapps.com/start/") is None


def leg(state):
    return ml.Leg(name="whichever", state=state, detail="")


class TestExitCode:
    def test_succeeds_when_every_leg_is_valid(self):
        assert ml.exit_code([leg(ml.OK), leg(ml.OK)]) == 0

    def test_fails_when_any_leg_is_still_expired(self):
        assert ml.exit_code([leg(ml.OK), leg(ml.EXPIRED)]) == 1

    def test_a_skipped_leg_is_not_a_failure(self):
        assert ml.exit_code([leg(ml.OK), leg(ml.SKIPPED)]) == 0

    def test_skipping_everything_is_not_a_failure(self):
        assert ml.exit_code([leg(ml.SKIPPED), leg(ml.SKIPPED)]) == 0
