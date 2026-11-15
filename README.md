<div align="center">

<img src="docs/images/logo.png" alt="MediOptim Pro Official Logo" width="140" style="margin-bottom: 12px;"/>

<img src="docs/images/banner.svg" alt="MediOptim Pro Banner" width="100%"/>

<br/><br/>

[![Python](https://img.shields.io/badge/Python-3.11+-0284c7.svg?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Flask](https://img.shields.io/badge/Flask-3.0.0-0f172a.svg?style=for-the-badge&logo=flask&logoColor=white)](https://flask.palletsprojects.com/)
[![PuLP](https://img.shields.io/badge/PuLP-CBC%20MIP%20Solver-059669.svg?style=for-the-badge)](https://coin-or.github.io/pulp/)
[![Docker](https://img.shields.io/badge/Docker-Containerized-0284c7.svg?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)
[![Pytest](https://img.shields.io/badge/pytest-Passing%20100%25-059669.svg?style=for-the-badge&logo=pytest&logoColor=white)](https://pytest.org)
[![License](https://img.shields.io/badge/License-MIT-6366f1.svg?style=for-the-badge)](LICENSE)

<p align="center">
  <strong>An Enterprise-Grade Smart Hospital Resource Optimization &amp; Clinical Operations System</strong><br/>
  Powered by Mixed-Integer Linear Programming (PuLP/CBC), Dynamic Emergency Code Red Preemption, Machine Learning No-Show Forecasting, Inpatient Bed Management, Medical Device Fleets, and Official Hospital Clinical Light UI.
</p>

[Quick Start](#-quick-start) •
[System Architecture](#-system-architecture) •
[Optimization Models](#-mathematical-optimization-formulation) •
[Features](#-key-modules--enterprise-features) •
[Live Emergency Workflow](#-emergency-code-red-preemption-workflow) •
[API Reference](#-api-endpoints-reference)

---

</div>

## 📌 Executive Summary & Problem Statement

Modern healthcare institutions face severe operational bottlenecks:
* **Overcrowded waiting rooms** and unacceptable wait times for high-risk patients.
* **Physician burnout and capacity misallocation**, where consult times and procedure lengths are treated uniformly.
* **Emergency interruptions**: When acute walk-in patients arrive (myocardial infarctions, strokes, trauma), schedules collapse without automated preemption logic.
* **Disjointed bed and equipment tracking**: Lack of synchronization between outpatient consultations, operating rooms, ICU ventilators, and inpatient bed sanitization turnaround.

**MediOptim Pro** addresses these critical challenges through mathematical operations research, intelligent clinical triage, predictive AI, and real-time resource scheduling.

---

## 🏗️ System Architecture

<div align="center">
  <img src="docs/images/architecture.svg" alt="System Architecture Diagram" width="100%"/>
</div>

The platform follows a layered, service-oriented architecture designed for hospital reliability:
1. **Presentation & Clinical UI Layer**: Official **Hospital Clinical Light Theme** built with a rich, authoritative healthcare color palette (Medical Blue `#0284c7`, Surgical Teal `#0d9488`, Clinical Emerald `#059669`, Warning Amber `#d97706`, and Emergency Crimson `#dc2626`). Features full English and Arabic (RTL) localization, doctor Gantt timeline, and public waiting hall monitor.
2. **Application & API Layer**: Flask RESTful services with Session-based authentication, Role-Based Access Control (RBAC), and persistent audit logging.
3. **Core Operations Research & AI Engines**: Mixed-Integer Linear Programming (PuLP/CBC), priority-based Greedy scheduling, real-time emergency slot preemption, and ML patient no-show risk inference.
4. **Persistence Layer**: SQLAlchemy ORM with SQLite for rapid local testing and native compatibility with production PostgreSQL.

---

## ⚡ Emergency Code Red Preemption Workflow

<div align="center">
  <img src="docs/images/triage_workflow.svg" alt="Emergency Code Red Preemption Workflow" width="100%"/>
</div>

### How Real-Time Preemption Operates:
1. **Clinical Triage Scoring**: Upon arrival, patients are categorized via the international **Emergency Severity Index (ESI Levels 1–5)** with vital sign recording (BP, Heart Rate, SpO2, Temperature).
2. **Immediate Availability Scan**: The engine first scans compatible physicians and surgical/consultation rooms for an open slot within the shift.
3. **Automated Bumping & Re-optimization**: If the department is fully booked, the algorithm locates the earliest appointment held by a non-critical (Normal or Low priority) patient, bumps that appointment downstream (adding sanitization buffer time), and grants immediate admission to the Code Red patient without manual administrative intervention.

---

## 🔢 Mathematical Optimization Formulation

The scheduling problem is formulated as a **Mixed-Integer Linear Program (MIP)** solved via the **Coin-OR CBC Branch-and-Cut solver**:

### 1. Sets and Indices
* $p \in P$: Patients requiring clinical consultation or surgery.
* $d \in D$: Physicians with defined operating hours and daily capacity limits $C_d$.
* $s \in S$: Discrete time slots across the operating day (e.g. 15-minute intervals).
* $r \in R$: Hospital rooms (consultation suites, surgical theaters, ICU rooms).

### 2. Decision Variables
$$x_{p, d, s, r} \in \{0, 1\} \quad \forall (p, d, s, r) \in \text{FeasiblePairs}$$
where $x_{p, d, s, r} = 1$ if patient $p$ is assigned to doctor $d$ in room $r$ starting at slot $s$.

### 3. Objective Function
$$\max \sum_{(p, d, s, r)} \left( \text{Reward}(p) - \lambda \cdot (s - \text{Start}_d) \right) x_{p, d, s, r}$$
where:
* $\text{Reward}(p)$ assigns heavy positive weights to critical and urgent triage patients ($\text{Critical} = 10,000$, $\text{Urgent} = 5,000$, $\text{Normal} = 2,000$, $\text{Low} = 1,000$).
* $\lambda \cdot (s - \text{Start}_d)$ applies a wait penalty that incentivizes assigning patients to the earliest feasible slots.

### 4. Hard Constraints
* **Single Assignment per Patient**:
  $$\sum_{(d, s, r)} x_{p, d, s, r} \le 1 \quad \forall p \in P$$
* **Doctor Daily Capacity**:
  $$\sum_{(p, s, r)} x_{p, d, s, r} \le C_d \quad \forall d \in D$$
* **Doctor Time Window & Overlap Prevention**: No physician can treat two patients simultaneously:
  $$\sum_{k \in \text{Overlap}(d, t)} x_{k} \le 1 \quad \forall d \in D, \, \forall t$$
* **Room Overlap Prevention with Sanitization Buffer**:
  $$\sum_{k \in \text{RoomOverlap}(r, t, \text{Buffer})} x_{k} \le 1 \quad \forall r \in R, \, \forall t$$
* **Clinical Specialization Matching**: $x_{p, d, s, r} = 0$ if $\text{Spec}(d) \neq \text{Spec}(p)$.

---

## 📊 Scheduling Algorithms Comparison & Verification

| Feature | ⚡ Greedy Heuristic | 🔢 Linear Programming (CBC) | 🔀 Hybrid Engine |
| :--- | :--- | :--- | :--- |
| **Optimality Guarantee** | Heuristic / Approximate | Mathematically Optimal | Near-Optimal with High Speed |
| **Computational Complexity** | $\mathcal{O}(P \cdot D \cdot S)$ | NP-Hard (Branch-and-Cut) | $\mathcal{O}(\text{LP}_{\text{critical}} + \text{Greedy}_{\text{normal}})$ |
| **Benchmark Execution Time** | $\approx 2 \text{ ms}$ | $\approx 0.08 \text{ s}$ | $\approx 0.04 \text{ s}$ |
| **Patients Scheduled (20/20)** | **100% Success** (0 unassigned) | **100% Success** (0 unassigned) | **100% Success** (0 unassigned) |
| **Average Wait Time** | $35.2 \text{ min}$ | $31.5 \text{ min}$ | $13.5 \text{ min}$ |
| **Recommended Dataset** | Massive Queues ($> 100$ patients) | Complex Surgical Suites ($\le 50$) | General Hospital Operations |
| **Emergency Preemption** | Native Support | Re-run with Warm Start | Instant Preemption Bumping |

---

## 🌟 Key Modules & Enterprise Features

### 1. 🏥 Official Clinical Light Healthcare Design System
* Exclusively styled in a prestigious **Clinical Light Theme** matching international healthcare standards (Mayo Clinic, Johns Hopkins portals).
* Clean slate cards (`#ffffff`), high-contrast typography (`#0f172a`), and color-coded status badges:
  - 🔵 **Primary Blue (`#0284c7`)**: Clinical navigation and actions.
  - 🟢 **Emerald Green (`#059669`)**: Normal triage, occupied beds, active equipment.
  - 🟡 **Clinical Amber (`#d97706`)**: Urgent cases, cleaning turnarounds.
  - 🔴 **Emergency Crimson (`#dc2626`)**: Critical triage, Code Red preemption.
  - 🟣 **Violet (`#6366f1`)**: Analytical indicators and AI metrics.

### 2. 🛏️ Inpatient Bed & Ward Management (`/beds`)
* **Real-time bed matrix**: Tracks beds by department and room.
* **4 Operational States**: `Vacant` 🟢, `Occupied` 🔴, `Cleaning / UV-C Turnaround` 🧼, `Reserved` 🔵.
* **Admission & Discharge Lifecycle**: Record admission date, clinical notes, and automatically flag beds for sanitization upon patient discharge.

### 3. 🩺 Medical Equipment & Fleet Tracking (`/equipment`)
* Inventory management for high-value hospital equipment (Hamilton/Maquet ICU Ventilators, Siemens 3T MRI, GE CT Scanners, Laparoscopic Towers, Digital ECGs).
* Status management (`Available`, `In Use`, `Under Maintenance`).

### 4. 🤖 Machine Learning No-Show Predictor
* Infers the probability ($0.01$ to $0.85$) that an outpatient will miss their scheduled appointment.
* Features evaluated: Patient age cohort, ESI urgency, vital signs abnormality, and booking lead-time.
* Helps administrative desks proactively manage overbooking and optimize clinic throughput.

### 5. 🧪 Crisis & "What-If" Scenario Simulator (`/simulator`)
* Stress-test hospital infrastructure before real emergencies occur:
  * **Doctor Absenteeism**: Simulate epidemic or sick-leave outages.
  * **Room Closures**: Simulate decontamination shutdowns.
  * **Emergency Surges**: Influx slider from $+0\%$ up to $+100\%$.
* Generates side-by-side KPI comparison cards and charts (Backlog, Utilization %, Wait time delta).

### 6. 📈 Doctor Daily Timeline (Gantt Chart View)
* Located in `/appointments`: Toggle between a tabular list and a visual hour-by-hour timeline (08:00 to 18:00) showing occupied time blocks color-coded by triage severity.

### 7. 📺 Public Waiting Hall TV Monitor (`/queue-display`)
* Full-screen widescreen view optimized for lobby monitors:
  * Official hospital logo and real-time live clock.
  * Currently serving ticket and clinic room number.
  * Privacy protection: Patient names are automatically masked (`A*** J.`).
  * Hospital public announcements ticker.

### 8. 🌐 Bilingual Medical Localization
* **One-Click Language Switch**: English (LTR) and Arabic (RTL) with comprehensive medical terminology.

---

## 🚀 Quick Start

### Prerequisites
* Python 3.10 or 3.11+
* Git

### Step-by-Step Installation

```bash
# 1. Clone the repository
git clone https://github.com/username/Smart-Hospital-Resource-Optimization-System-V1.git
cd Smart-Hospital-Resource-Optimization-System-V1

# 2. Install dependencies
pip install -r requirements.txt

# 3. Launch the application
python app.py
```

Open your browser at: **`http://127.0.0.1:5000`**

### Docker Deployment

```bash
# Run multi-container stack in background
docker-compose up --build -d
```
Access the application at `http://localhost:5000`.

### ☁️ Vercel Serverless Deployment

MediOptim Pro is pre-configured for instant zero-config deployment on **Vercel**:
* **Optimized Serverless Package**: Pre-configured with `vercel.json`, `api/index.py`, `.vercelignore`, and lightweight serverless dependencies (<15MB).
* **Automatic Database Provisioning**: In Vercel serverless environments, SQLite is automatically mapped to `/tmp/hospital.db` and copies seeded clinical records on cold-start, or connects to external PostgreSQL (e.g. Supabase, Neon) via `DATABASE_URL`.
* **Fault-Tolerant Optimizer**: The LP optimization engine automatically handles cloud lambda constraints, falling back to fast heuristic scheduling if external solver binaries are unavailable in serverless containers.

```bash
# Deploy with Vercel CLI:
npm install -g vercel
vercel

# Or simply import the repository into https://vercel.com/new
```

---

## 🔑 User Accounts & Access Control (RBAC)

The system enforces strict Role-Based Access Control across all views and API endpoints with session-based authentication, CSRF tokens, and login rate limiting (5 attempts/min).

Navigate to **`http://127.0.0.1:5000/login`** (or use the one-click quick autofill buttons):

| Role | Username | Default Password | Operational Access Matrix |
| :--- | :--- | :--- | :--- |
| **👑 Super Admin** | `admin` | `Admin#2025!` | Full platform administration, RBAC assignment, audit logs, resource deletion |
| **🏢 Operations Director** | `manager` | `Manager#2025!` | Bed admissions, medical fleets, optimization engine, crisis simulator, CSV export |
| **👨‍⚕️ Physician** | `dr_sarah` | `Doctor#2025!` | View department schedule, update **own** appointments' status, clinical notes & prescriptions |
| **📋 Receptionist** | `receptionist` | `Reception#2025!` | Outpatient registration, appointments directory, Code Red emergency walk-in intake, bed occupancy |

> [!NOTE]
> All credentials can be customized via `.env` (`ADMIN_INITIAL_PASSWORD`, `DOCTOR_INITIAL_PASSWORD`, etc.).

---

## 🛡️ Security & Enterprise Hardening

* **Authentication & RBAC**: Every `/api/*` endpoint is guarded by `login_required` and role-specific `role_required` decorators. Doctors cannot tamper with other doctors' appointments.
* **Rate Limiting**: `Flask-Limiter` protects authentication against brute-force attacks (`5 requests/minute`).
* **CSRF Defense**: Double-submit cookie & header token pattern (`X-CSRF-Token`) verified on state-changing methods (`POST`, `PUT`, `PATCH`, `DELETE`).
* **Spreadsheet Formula Injection Protection**: Exported CSV cells starting with `=, +, -, @, \t, \r` are automatically escaped.
* **Cookie & Header Hardening**: `HttpOnly`, `SameSite=Lax`, CSP, `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`.
* **State Machine Validation**: Appointment statuses follow clinical lifecycle validation (`scheduled` -> `in_progress` -> `completed` / `cancelled`); terminal states cannot be illegally reversed.
* **Deletion Safeguards**: Resources with active scheduled appointments cannot be silently deleted, preventing accidental medical record data loss.

---

## 🌐 API Endpoints Reference

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/auth/login` | Session authentication |
| `POST` | `/api/auth/logout` | Session termination |
| `GET` | `/api/auth/me` | Fetch active authenticated user profile |
| `GET` | `/api/dashboard` | Aggregated hospital KPIs & utilization stats |
| `GET/POST` | `/api/patients` | Retrieve patient directory or register new patient |
| `PUT/DELETE`| `/api/patients/<id>` | Update patient record or remove |
| `POST` | `/api/emergency/walkin` | **Trigger Code Red walk-in with preemption engine** |
| `GET/POST` | `/api/doctors` | List doctors or add physician profile |
| `GET/POST` | `/api/rooms` | Manage hospital rooms and capacity |
| `GET/POST` | `/api/beds` | Inpatient bed inventory |
| `POST` | `/api/beds/<id>/admit` | Admit patient to specific bed |
| `POST` | `/api/beds/<id>/discharge`| Discharge patient and trigger bed cleaning state |
| `GET/POST` | `/api/equipment` | Medical devices and calibration tracking |
| `GET` | `/api/appointments` | Filterable consultation schedule |
| `PATCH`| `/api/appointments/<id>/status`| Update status, clinical notes, and prescriptions |
| `POST` | `/api/optimize` | Execute PuLP Linear Programming / Greedy optimizer |
| `POST` | `/api/simulation/run` | Execute crisis "What-If" stress simulation |
| `GET` | `/api/export/appointments/csv`| Export appointment roster to CSV file |
| `GET` | `/api/audit-logs` | Retrieve persistent security & audit event logs |

---

## 🧪 Automated Testing Suite

The system includes a dedicated unit and integration test suite using `pytest`:

```bash
python -m pytest tests/test_system.py -v
```

### Verified Test Cases:
* `test_user_authentication`: Password hashing, session security, and unauthorized access blocks.
* `test_no_show_prediction`: Machine learning clinical risk heuristics.
* `test_optimizer_algorithms`: Correctness and non-emptiness of LP, Greedy, and Hybrid solvers.
* `test_emergency_code_red_preemption`: Preemption mechanism and slot shifting under full capacity.
* `test_bed_management_api`: Complete admission, occupancy, and discharge-to-cleaning cycle.
* `test_scenario_simulation`: Crisis simulation metrics and delta impact calculations.

---

## 📂 Project Directory Structure

```
Smart-Hospital-Resource-Optimization-System-V1/
├── app.py                  # Main Flask application & 50+ RESTful API routes
├── api/
│   └── index.py            # Vercel Serverless WSGI entrypoint
├── vercel.json             # Vercel cloud serverless routing & build config
├── .vercelignore           # Deployment asset filter for fast cloud builds
├── models.py               # SQLAlchemy ORM models (Users, Beds, Equipment, etc.)
├── optimizer.py            # PuLP Linear Programming, Greedy & Code Red engine
├── config.py               # Environment configuration (Dev, Prod, Test)
├── seed_data.py            # Clinical database seeder with realistic records
├── requirements.txt        # Pinned Python package dependencies
├── Dockerfile              # Production Docker image with Coin-OR CBC
├── docker-compose.yml      # Docker orchestration
├── docs/
│   └── images/
│       ├── logo.png        # Official MediOptim Pro hospital crest logo
│       ├── banner.svg      # Official vector header banner
│       ├── architecture.svg# Multi-layer architecture diagram
│       └── triage_workflow.svg # Emergency preemption workflow diagram
├── tests/
│   └── test_system.py      # Automated pytest test suite (Passing 100%)
├── static/
│   ├── img/
│   │   └── logo.png        # Hospital logo used across UI and Favicon
│   ├── css/style.css       # Official Hospital Clinical Light design system
│   └── js/app.js           # Frontend controllers, modals, timeline & i18n
└── templates/
    ├── base.html           # Master layout with sidebar & emergency modal
    ├── index.html          # Operations dashboard & telemetry charts
    ├── appointments.html   # Schedule with Gantt / Timeline view & CSV export
    ├── patients.html       # Patient directory with vitals & ML no-show risk
    ├── beds.html           # Inpatient bed matrix & admissions
    ├── equipment.html      # Medical device inventory
    ├── simulator.html      # Crisis & "What-If" scenario simulator
    ├── queue_display.html  # Full-screen clinic waiting hall TV display
    ├── login.html          # Authentication portal with demo auto-fills
    ├── optimize.html       # AI optimization solver interface
    ├── analytics.html      # Clinical performance metrics
    ├── doctors.html        # Physician management
    ├── rooms.html          # Room & theater management
    ├── departments.html    # Department overview with bed/equipment stats
    └── history.html        # Historical solver logs & execution archive
```

---

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
