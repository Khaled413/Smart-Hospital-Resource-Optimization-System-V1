# Data Governance & Compliance Policy

## Egyptian Personal Data Protection Law (Law No. 151 of 2020) & Healthcare Data Standards

### 1. Executive Summary & Scope
MediOptim Pro is designed as a Smart Hospital Resource Optimization System. This policy defines the legal, technical, and operational safeguards governing the handling of clinical, patient, and operational hospital data in compliance with:
- **Egyptian Personal Data Protection Law (Law 151 of 2020)**.
- International healthcare information protection best practices (HIPAA / GDPR data protection principles).
- Supabase PostgreSQL infrastructure security requirements.

---

### 2. Strict Boundary: Synthetic Demo vs. Production Patient Data
1. **Public Demonstrations & Vercel Preview Environments**:
   - MUST exclusively contain **100% synthetic, anonymized, and randomized data**.
   - No real patient identities, national IDs, genuine phone numbers, or clinical histories may ever be imported into demo or preview environments.
   - The application enforces client and API name masking (`DEMO_MODE=true` masks patient names as `Pt-****`).
2. **Production Healthcare Environments**:
   - Prior to onboarding genuine patients, an institutional Data Protection Impact Assessment (DPIA) must be approved by the designated Data Protection Officer (DPO).

---

### 3. Legal Principles of Law 151 of 2020
Under Egyptian Law 151/2020, health and clinical data is classified as **Sensitive Personal Data** (البيانات الشخصية الحساسة), requiring the highest tier of protection:

| Law 151 Principle | MediOptim Pro Implementation |
| :--- | :--- |
| **Explicit Consent (الموافقة الصريحة)** | Patients must provide explicit documented consent prior to processing their clinical records. |
| **Purpose Limitation (تحديد الغرض)** | Data is processed solely for triage, appointment scheduling, and inpatient bed allocation. |
| **Data Minimization (الحد الأدنى للبيانات)** | Non-clinical staff (receptionists, resource managers) are restricted via RBAC from viewing diagnostic vitals. |
| **Confidentiality & Integrity (السرية والسلامة)** | All database connections require TLS 1.3 (`sslmode=require`). Passwords hashed with salted Werkzeug pbkdf2. |
| **Right to Erasure & Rectification** | Patients have the legal right to request correction or removal of obsolete records. |
| **Cross-Border Transfer Restrictions** | Database regions must comply with statutory data localization regulations where applicable. |

---

### 4. Technical Security Architecture

#### 4.1 Transport & Storage Encryption
- **In-Transit**: Mandatory HTTPS enforced via HSTS (`Strict-Transport-Security`). PostgreSQL connections enforce `sslmode=require`.
- **At-Rest**: Managed database storage volumes on Supabase are encrypted at rest with AES-256.

#### 4.2 Row Level Security (RLS) PostgREST Isolation
- Direct PostgreSQL connections (`postgresql+psycopg2://`) are used exclusively by the Flask serverless backend.
- Supabase PostgREST public APIs (`anon` and `authenticated` roles) have **RLS enabled on every table with zero policies**, effectively rejecting all direct HTTP/REST queries and preventing credential harvesting or data exfiltration.

#### 4.3 Immutable Audit Logging
- Every authentication attempt (success, failure, lockout), privilege override, patient triage update, and manual appointment override is permanently captured in the `audit_logs` table with an aware UTC timestamp (`timestamptz`), actor user ID, client IP, and contextual action detail.

#### 4.4 Automated Backups & Disaster Recovery
- Scheduled daily backups (`pg_dump` compressed with gzip) are preserved in encrypted storage.
- Keep-alive pings prevent free-tier database hibernation, ensuring zero unplanned operational disruption.
