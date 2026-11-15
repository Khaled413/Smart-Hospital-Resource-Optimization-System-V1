"""
config.py - Application Configuration for Smart Hospital Resource Optimization System
Compatible with local environments, Docker, and Vercel Serverless.
"""

import os
import shutil
import tempfile

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Detect if running in Vercel Serverless or AWS Lambda
IS_VERCEL = bool(os.environ.get('VERCEL') or os.environ.get('AWS_LAMBDA_FUNCTION_NAME'))

# Configure Database URL
database_url = os.environ.get('DATABASE_URL')

if database_url:
    # Normalize legacy postgres:// to postgresql:// for modern SQLAlchemy
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
    SECRET_KEY = os.environ.get('SECRET_KEY', 'smart-hospital-optimizer-key-2025-secure')
    SQLALCHEMY_DATABASE_URI = database_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Hospital Operational Parameters
    DEFAULT_CLEANING_BUFFER = 10  # minutes between appointments
    DEFAULT_EMERGENCY_ESI = 1      # Level 1 = Resuscitation / Code Red
    MAX_OVERBOOKING_FACTOR = 1.15  # Up to 15% smart overbooking for high no-show risk
    
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

class ProductionConfig(Config):
    DEBUG = False
    SECRET_KEY = os.environ.get('SECRET_KEY', 'prod-hospital-secret-replace-me')

class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    DEBUG = True

config_by_name = {
    'dev': DevelopmentConfig,
    'prod': ProductionConfig,
    'test': TestingConfig
}
