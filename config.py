"""
config.py - Application Configuration for Smart Hospital Resource Optimization System
"""

import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'smart-hospital-optimizer-key-2025-secure')
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'DATABASE_URL',
        f"sqlite:///{os.path.join(BASE_DIR, 'instance', 'hospital.db')}"
    )
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
