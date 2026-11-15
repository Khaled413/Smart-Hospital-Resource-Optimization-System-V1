"""
api/index.py - Serverless WSGI Handler for Vercel Deployment
Exposes the Flask app instance for zero-config and WSGI serverless execution.
"""

import sys
import os

# Add parent directory to path so imports work seamlessly on Vercel
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app

# Vercel looks for 'app' by default in WSGI entrypoint
if __name__ == '__main__':
    app.run()
