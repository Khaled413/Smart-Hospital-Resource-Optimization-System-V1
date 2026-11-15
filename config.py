"""
config.py - Application Configuration for Smart Hospital Resource Optimization System
Handles environment variable loading, strict security validations, session cookies, and operational constants.
"""

import os
import tempfile
from datetime import timedelta

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Detect if running in Vercel Serverless or AWS Lambda
IS_VERCEL = bool(os.environ.get('VERCEL') or os.environ.get('AWS_LAMBDA_FUNCTION_NAME'))

# Configure Database URL
database_url = os.environ.get('DATABASE_URL')

if database_url:
    # Normalize legacy postgres:// to postgresql:// for SQLAlchemy compatibility
    if database_url.startswith('postgres://'):
        database_url = database_url.replace('postgres://', 'postgresql://', 1)
else:
    if IS_VERCEL:
        # In Vercel serverless functions, only temporary directory is writable
        DEFAULT_DB_PATH = os.path.join(tempfile.gettempdir(), 'hospital.db')
    else:
        DEFAULT_DB_PATH = os.path.join(BASE_DIR, 'instance', 'hospital.db')
    # Standardize forward slashes for SQLite URI
    clean_path = DEFAULT_DB_PATH.replace('\\', '/')
    database_url = f"sqlite:///{clean_path}"


class Config:
    # Core Security Settings
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-insecure-secret-key-change-in-prod')
    SQLALCHEMY_DATABASE_URI = database_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Session Cookie Hardening
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    SESSION_COOKIE_SECURE = False  # Enabled in ProductionConfig
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)

    # Timezone Configuration
    APP_TIMEZONE = os.environ.get('APP_TIMEZONE', 'Africa/Cairo')
    
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


class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
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

    return cfg_class
