<div align="center">

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
  Powered by Mixed-Integer Linear Programming (PuLP/CBC), Dynamic Emergency Code Red Preemption, Machine Learning No-Show Forecasting, Inpatient Bed Management, and Medical Device Fleets.
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
1. **Presentation & Clinical UI Layer**: Dual-theme (Hospital Clean Light / Dark) responsive interface with English and Arabic RTL localization, interactive doctor Gantt timeline, and public waiting hall monitor.
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

## 📊 Scheduling Algorithms Comparison

| Feature | ⚡ Greedy Heuristic | 🔢 Linear Programming (CBC) | 🔀 Hybrid Engine |
| :--- | :--- | :--- | :--- |
| **Optimality Guarantee** | Heuristic / Approximate | Mathematically Optimal | Near-Optimal with High Speed |
| **Computational Complexity** | $\mathcal{O}(P \cdot D \cdot S)$ | NP-Hard (Branch-and-Cut) | $\mathcal{O}(\text{LP}_{\text{critical}} + \text{Greedy}_{\text{normal}})$ |
| **Solving Time** | $< 20 \text{ ms}$ | $1 - 15 \text{ seconds}$ | $< 1 \text{ second}$ |
| **Recommended Dataset** | Massive Queues ($> 100$ patients) | Complex Surgical Suites ($\le 50$) | General Hospital Operations |
| **Emergency Preemption** | Native Support | Re-run with Warm Start | Instant Preemption Bumping |

---

## 🌟 Key Modules & Enterprise Features

### 1. 🛏️ Inpatient Bed & Ward Management (`/beds`)
* **Real-time bed matrix**: Tracks beds by department and room.
* **4 Operational States**: `Vacant` 🟢, `Occupied` 🔴, `Cleaning / UV-C Turnaround` 🧼, `Reserved` 🔵.
* **Admission & Discharge Lifecycle**: Record admission date, clinical notes, and automatically flag beds for sanitization upon patient discharge.

### 2. 🩺 Medical Equipment & Fleet Tracking (`/equipment`)
* Inventory management for high-value hospital equipment (Hamilton/Maquet ICU Ventilators, Siemens 3T MRI, GE CT Scanners, Laparoscopic Towers, Digital ECGs).
* Status management (`Available`, `In Use`, `Under Maintenance`).

### 3. 🤖 Machine Learning No-Show Predictor
* Infers the probability ($0.01$ to $0.85$) that an outpatient will miss their scheduled appointment.
* Features evaluated: Patient age cohort, ESI urgency, vital signs abnormality, and booking lead-time.
* Helps administrative desks proactively manage overbooking and optimize clinic throughput.

### 4. 🧪 Crisis & "What-If" Scenario Simulator (`/simulator`)
* Stress-test hospital infrastructure before real emergencies occur:
  * **Doctor Absenteeism**: Simulate epidemic or sick-leave outages.
  * **Room Closures**: Simulate decontamination shutdowns.
  * **Emergency Surges**: Influx slider from $+0\%$ up to $+100\%$.
* Generates side-by-side KPI comparison cards and charts (Backlog, Utilization %, Wait time delta).

### 5. 📈 Doctor Daily Timeline (Gantt Chart View)
* Located in `/appointments`: Toggle between a tabular list and a visual hour-by-hour timeline (08:00 to 18:00) showing occupied time blocks color-coded by triage severity.

### 6. 📺 Public Waiting Hall TV Monitor (`/queue-display`)
* Full-screen widescreen view optimized for lobby monitors:
  * Currently serving ticket and clinic room number.
  * Privacy protection: Patient names are automatically masked (`A*** J.`).
  * Live digital clock and hospital public announcements ticker.

### 7. 🌐 Bilingual & Dual-Theme UI
* **One-Click Language Switch**: English (LTR) and Arabic (RTL) with localized medical terminology.
* **Theme Switcher**: Crisp daytime **Hospital Clean Light Theme** ☀️ and prestigious **Clinical Dark Theme** 🌙.

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

---

## 🔑 Pre-Configured Demo Accounts

Navigate to **`http://127.0.0.1:5000/login`** (or use the one-click auto-fill buttons):

| Role | Username | Password | Operational Access |
| :--- | :--- | :--- | :--- |
| **👑 Super Admin** | `admin` | `admin123` | Full administrative control, user management, audit trails |
| **👨‍⚕️ Physician** | `dr_sarah` | `doctor123` | Clinic consultation roster, diagnosis notes & prescriptions |
| **🏢 Operations Director** | `manager` | `manager123` | Bed matrix, device fleets, crisis stress-test simulator |
| **📋 Receptionist** | `receptionist` | `reception123` | Outpatient directory, Code Red emergency walk-in intake |

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
├── models.py               # SQLAlchemy ORM models (Users, Beds, Equipment, etc.)
├── optimizer.py            # PuLP Linear Programming, Greedy & Code Red engine
├── config.py               # Environment configuration (Dev, Prod, Test)
├── seed_data.py            # Clinical database seeder with realistic records
├── requirements.txt        # Pinned Python package dependencies
├── Dockerfile              # Production Docker image with Coin-OR CBC
├── docker-compose.yml      # Docker orchestration
├── docs/
│   └── images/
│       ├── banner.svg      # Official vector header banner
│       ├── architecture.svg# Multi-layer architecture diagram
│       └── triage_workflow.svg # Emergency preemption workflow diagram
├── tests/
│   └── test_system.py      # Automated pytest test suite
├── static/
│   ├── css/style.css       # Healthcare design system (Dark & Clean Light)
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
