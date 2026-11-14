# Dockerfile for Smart Hospital Resource Optimization System
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies including CBC solver for PuLP if needed
RUN apt-get update && apt-get install -y --no-install-recommends \
    coinor-cbc \
    coinor-libcbc-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Set environment variables
ENV FLASK_ENV=prod \
    PYTHONUNBUFFERED=1 \
    PORT=5000

# Expose port
EXPOSE 5000

# Run application with gunicorn or python
CMD ["python", "app.py"]
