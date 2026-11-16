-- MediOptim Pro - Least-Privilege Supabase Database Role Setup
-- Run this script in the Supabase SQL Editor to provision a dedicated non-superuser role
-- for the Vercel serverless application runtime.

-- 1. Create dedicated application role
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'medioptim_app') THEN
        CREATE ROLE medioptim_app WITH LOGIN PASSWORD 'YOUR_STRONG_PASSWORD_HERE' NOINHERIT;
    END IF;
END
$$;

-- 2. Grant connection and schema access
GRANT CONNECT ON DATABASE postgres TO medioptim_app;
GRANT USAGE ON SCHEMA public TO medioptim_app;

-- 3. Grant operational CRUD privileges on existing tables & sequences
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO medioptim_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO medioptim_app;

-- 4. Automatically grant privileges on future tables created by Alembic migrations
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO medioptim_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO medioptim_app;

-- Note: In Vercel environment variables, set:
-- DATABASE_URL=postgresql://medioptim_app:[PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres?sslmode=require
