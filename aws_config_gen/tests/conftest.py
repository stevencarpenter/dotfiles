"""Shared test fixtures for aws_config_gen."""

from __future__ import annotations

import pytest

from aws_config_gen.types import GeneratorConfig, SSOAccount


@pytest.fixture
def sample_generator_config() -> GeneratorConfig:
    return GeneratorConfig(
        sso_session="test-session",
        sso_start_url="https://test.awsapps.com/start/#",
        sso_region="us-west-2",
        default_region="us-west-2",
        account_names={
            "111111111111": "acme",
            "222222222222": "acme-dev",
        },
        role_short_names={
            "SRE-ClientEnvironments": "sre",
            "Administrator-Access-SRE": "admin",
        },
        skip=[],
    )


@pytest.fixture
def sample_accounts() -> list[SSOAccount]:
    return [
        SSOAccount(
            account_id="111111111111",
            account_name="Acme Corp",
            email_address="acme@example.com",
        ),
        SSOAccount(
            account_id="222222222222",
            account_name="Acme Dev",
            email_address="acme-dev@example.com",
        ),
        SSOAccount(
            account_id="333333333333",
            account_name="Other Account",
            email_address="other@example.com",
        ),
    ]
