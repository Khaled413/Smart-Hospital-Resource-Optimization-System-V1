"""
config.py - Application Configuration for Smart Hospital Resource Optimization System
Handles environment variable loading, strict security validations, session cookies,
Supabase PostgreSQL connection pooling (NullPool, transaction mode port 6543), and operational constants.
"""

import os
import secrets
from datetime import timedelta
from urllib.parse import quote_plus
from sqlalchemy.pool import NullPool

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Detect if running in Vercel Serverless or AWS Lambda
IS_VERCEL = bool(os.environ.get('VERCEL') or os.environ.get('AWS_LAMBDA_FUNCTION_NAME'))


def normalize_database_url(url: str | None) -> str:
    """
    Normalize PostgreSQL database URL for SQLAlchemy and psycopg2 driver compatibility.
    Replaces postgres:// or postgresql:// with postgresql+psycopg2://
    """
    if not url:
        return ''
    trimmed = url.strip()
    if trimmed.startswith('postgres://'):
        return trimmed.replace('postgres://', 'postgresql+psycopg2://', 1)
    if trimmed.startswith('postgresql://'):
        return trimmed.replace('postgresql://', 'postgresql+psycopg2://', 1)
    return trimmed


# Primary Runtime Database URL (Supabase pooled connection string, Supavisor port 6543)
raw_db_url = os.environ.get('DATABASE_URL')
database_url = normalize_database_url(raw_db_url)

# Dedicated Migration Database URL (Direct connection, port 5432 or session pooler)
raw_migration_url = os.environ.get('MIGRATION_DATABASE_URL')
migration_database_url = normalize_database_url(raw_migration_url) or database_url

if not database_url:
    # Local fallback for development and unit testing when DATABASE_URL is unset
    default_db_path = os.path.join(BASE_DIR, 'instance', 'hospital.db')
    clean_path = default_db_path.replace('\\', '/')
    database_url = f"sqlite:///{clean_path}"

is_postgres = database_url.startswith('postgresql')

# SQLAlchemy Engine Options for serverless PostgreSQL
# In Vercel serverless functions with Supabase pooled connection string (Supavisor port 6543):
# - NullPool ensures ephemeral serverless instances do not hold idle connections.
# - pool_pre_ping validates connection liveness before query execution.
# - sslmode=require enforces TLS in transit.
engine_options = {}
if is_postgres:
    engine_options = {
        'poolclass': NullPool,
        'pool_pre_ping': True,
        'connect_args': {
            'sslmode': 'require'
        }
    }


class Config:
    # Core Security Settings
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-insecure-secret-key-change-in-prod')
    SQLALCHEMY_DATABASE_URI = database_url
    SQLALCHEMY_ENGINE_OPTIONS = engine_options
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MIGRATION_DATABASE_URI = migration_database_url
    
    # Session Cookie Hardening
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    SESSION_COOKIE_SECURE = False  # Enabled in ProductionConfig
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)

    # Timezone Configuration (Africa/Cairo standard for hospital operations)
    APP_TIMEZONE = os.environ.get('APP_TIMEZONE', 'Africa/Cairo')
    
    # Public Waiting Hall Kiosk Display Token (Read-Only)
    # In production, must be explicitly configured with a strong secret.
    # In dev/testing, uses an ephemeral random token if unset.
    KIOSK_VIEW_TOKEN = os.environ.get('KIOSK_VIEW_TOKEN') or secrets.token_urlsafe(32)
    
    # Demo Mode (Restricted read-only demo viewer)
    DEMO_MODE = os.environ.get('DEMO_MODE', 'false').lower() in ('true', '1', 'yes')

    # Hospital Operational Parameters
    DEFAULT_CLEANING_BUFFER = int(os.environ.get('DEFAULT_CLEANING_BUFFER', 10))  # minutes between appointments
    DEFAULT_EMERGENCY_ESI = int(os.environ.get('DEFAULT_EMERGENCY_ESI', 1))        # Level 1 = Resuscitation / Code Red
    ENABLE_SMART_OVERBOOKING = os.environ.get('ENABLE_SMART_OVERBOOKING', 'false').lower() in ('true', '1', 'yes')
    MAX_OVERBOOKING_FACTOR = float(os.environ.get('MAX_OVERBOOKING_FACTOR', 1.15)) # Up to 15% smart overbooking
    LP_MAX_PATIENTS_THRESHOLD = int(os.environ.get('LP_MAX_PATIENTS_THRESHOLD', 75))
    
    # Procedure Durations by Specialization (minutes)
    PROCEDURE_DURATIONS = {
        'cardiology': 30,
        'neurology': 40,
        'orthopedics': 30,
        'pediatrics': 20,
        'general surgery': 60
    }


class DevelopmentConfig(Config):
    DEBUG = True
    SESSION_COOKIE_SECURE = False


class ProductionConfig(Config):
    DEBUG = False
    SESSION_COOKIE_SECURE = True
    # Production strictly forbids SQLite and requires valid PostgreSQL connection string


class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    SQLALCHEMY_ENGINE_OPTIONS = {}
    DEBUG = True
    SESSION_COOKIE_SECURE = False
    WTF_CSRF_ENABLED = False
    RATELIMIT_ENABLED = False


config_by_name = {
    'dev': DevelopmentConfig,
    'development': DevelopmentConfig,
    'prod': ProductionConfig,
    'production': ProductionConfig,
    'test': TestingConfig,
    'testing': TestingConfig
}


def get_config(env_name=None):
    """Retrieve configuration class and enforce fail-fast production checks."""
    if env_name is None:
        env_name = os.environ.get('FLASK_ENV', 'dev').lower()
    
    cfg_class = config_by_name.get(env_name, DevelopmentConfig)
    
    if cfg_class == ProductionConfig:
        prod_secret = os.environ.get('SECRET_KEY')
        insecure_defaults = {
            None, '', 'dev-insecure-secret-key-change-in-prod',
            'smart-hospital-optimizer-key-2025-secure',
            'prod-hospital-secret-replace-me',
            'change-this-to-a-very-strong-random-key-in-production-min-32-chars'
        }
        if prod_secret in insecure_defaults:
            raise ValueError(
                "CRITICAL SECURITY CONFIGURATION ERROR: "
                "In production mode, the 'SECRET_KEY' environment variable must be explicitly defined "
                "and cannot use a known default or insecure value."
            )
        cfg_class.SECRET_KEY = prod_secret

        prod_db_url = os.environ.get('DATABASE_URL')
        if not prod_db_url or not prod_db_url.strip():
            raise ValueError(
                "CRITICAL DATABASE CONFIGURATION ERROR: "
                "In production mode (or on Vercel), the 'DATABASE_URL' environment variable must be explicitly configured "
                "pointing to your Supabase PostgreSQL database. SQLite is strictly forbidden in production."
            )
        if not (prod_db_url.startswith('postgres://') or prod_db_url.startswith('postgresql://') or prod_db_url.startswith('postgresql+')):
            raise ValueError(
                "CRITICAL DATABASE CONFIGURATION ERROR: "
                f"'DATABASE_URL' must be a valid PostgreSQL connection string in production, got: {prod_db_url[:12]}..."
            )

        prod_kiosk_token = os.environ.get('KIOSK_VIEW_TOKEN')
        insecure_kiosk_tokens = {
            None, '', 'medioptim-kiosk-display-token-2025', 'kiosk-token', 'default',
            'change-this-in-production'
        }
        if not prod_kiosk_token or prod_kiosk_token.strip() in insecure_kiosk_tokens:
            raise ValueError(
                "CRITICAL SECURITY CONFIGURATION ERROR: "
                "In production mode, the 'KIOSK_VIEW_TOKEN' environment variable must be explicitly defined "
                "and cannot use a known default or placeholder value. Generate a secure token via: "
                "python -c \"import secrets; print(secrets.token_urlsafe(32))\""
            )
        cfg_class.KIOSK_VIEW_TOKEN = prod_kiosk_token.strip()

    return cfg_class
