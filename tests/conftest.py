"""
conftest.py - Shared pytest fixtures for MediOptim Pro test suite
"""

import os
import pytest
from app import app, limiter
from models import db, User


@pytest.fixture
def client():
    """Create Flask test client with rate-limiting disabled."""
    app.config['TESTING'] = True
    app.config['RATELIMIT_ENABLED'] = False
    limiter.enabled = False
    os.environ['ADMIN_INITIAL_PASSWORD'] = 'Admin#2025!'

    with app.test_client() as test_client:
        with app.app_context():
            yield test_client
