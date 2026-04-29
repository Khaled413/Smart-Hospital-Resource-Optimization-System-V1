# 🏥 Smart Hospital Resource Optimization System

A full-stack web application for optimal allocation of hospital resources using **Linear Programming**, **Greedy Scheduling**, and a **Hybrid Algorithm**.

---

## 🚀 Quick Start

```bash
# 1. Install dependencies
pip install flask flask-sqlalchemy pulp

# 2. Run the application
python app.py

# 3. Open browser at
http://127.0.0.1:5000
```

---

## 📁 Project Structure

```
hospital_optimizer/
├── app.py              # Flask application & API routes
├── models.py           # SQLAlchemy database models
├── optimizer.py        # Optimization engine (LP, Greedy, Hybrid)
├── seed_data.py        # Sample data seeder
├── hospital.db         # SQLite database (auto-created)
├── static/
│   ├── css/style.css   # Main stylesheet
│   └── js/app.js       # Core JavaScript utilities
└── templates/
    ├── base.html        # Base layout with sidebar
    ├── index.html       # Dashboard
    ├── patients.html    # Patient management
    ├── doctors.html     # Doctor management
    ├── rooms.html       # Room management
    ├── departments.html # Department overview
    ├── appointments.html# Appointment viewer
    ├── optimize.html    # Optimization engine UI
    ├── analytics.html   # Analytics & charts
    └── history.html     # Run history
```

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📊 Dashboard | Real-time KPIs with interactive charts |
| 🧑‍⚕️ Patients | CRUD with priority levels, search & filter |
| 👨‍⚕️ Doctors | Card-view management with utilization bars |
| 🚪 Rooms | Grid management by type (consultation/surgery/ICU/ward) |
| 🏢 Departments | Overview with doctor listing and capacity |
| 📅 Appointments | Full schedule with inline status updates |
| ⚡ Optimization | 3 algorithms with live results & solver log |
| 📈 Analytics | 4 charts: wait time, utilization, assignment status, trends |
| 🕓 Run History | Complete history with log viewer |

---

## 🔢 Optimization Algorithms

### 1. Greedy Algorithm
- Sorts patients by priority (Critical → Urgent → Normal → Low)
- Assigns first available doctor with matching specialization
- Finds next free room in the doctor's department
- Time: O(P × D × S) where P=patients, D=doctors, S=slots

### 2. Linear Programming (PuLP/CBC)
- Decision variable: `x[patient, doctor, slot, room] ∈ {0,1}`
- Objective: Minimize weighted waiting time (priority-weighted)
- Constraints:
  - Each patient assigned at most once
  - Doctor daily capacity not exceeded
  - No overlapping doctor appointments
  - No overlapping room appointments
  - Specialization must match

### 3. Hybrid Algorithm
- Uses LP for **Critical** and **Urgent** patients (precision matters)
- Uses Greedy for **Normal** and **Low** patients (speed matters)
- Combines results into unified schedule

---

## 🌐 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dashboard` | Dashboard KPIs and chart data |
| GET/POST | `/api/patients` | List / create patients |
| PUT/DELETE | `/api/patients/<id>` | Update / delete patient |
| GET/POST | `/api/doctors` | List / create doctors |
| PUT/DELETE | `/api/doctors/<id>` | Update / delete doctor |
| GET/POST | `/api/rooms` | List / create rooms |
| PUT/DELETE | `/api/rooms/<id>` | Update / delete room |
| GET | `/api/departments` | List departments |
| GET | `/api/appointments` | List appointments |
| PATCH | `/api/appointments/<id>/status` | Update appointment status |
| POST | `/api/optimize` | Run optimization |
| GET | `/api/analytics/wait-time` | Wait time by priority |
| GET | `/api/analytics/utilization` | Doctor utilization |
| GET | `/api/analytics/patients-status` | Assigned vs unassigned |
| GET | `/api/optimization-runs` | Run history |

---

## 🗃️ Database Models

| Table | Key Fields |
|-------|-----------|
| `departments` | name, capacity, description |
| `doctors` | name, specialization, department_id, max_patients_per_day, available_from/until |
| `patients` | name, age, gender, priority, required_specialization, preferred_date |
| `rooms` | room_number, department_id, room_type, capacity |
| `appointments` | patient_id, doctor_id, room_id, date, start/end_time, waiting_time, status |
| `optimization_runs` | algorithm, run_date, metrics, solver_log |

---

## 📊 Sample Data

Auto-seeded on first run:
- **5 Departments**: Cardiology, Neurology, Orthopedics, Pediatrics, General Surgery
- **8 Doctors**: Various specializations and schedules
- **10 Rooms**: Mix of consultation, surgery, ICU, and ward rooms
- **20 Patients**: Range of priorities and conditions

---

## 🛠️ Tech Stack

- **Backend**: Python 3.11 + Flask 3.0
- **Database**: SQLite + SQLAlchemy ORM
- **Optimization**: PuLP (CBC Solver)
- **Frontend**: HTML5, CSS3 (custom design system), Vanilla JS
- **Charts**: Chart.js 4.4
- **Fonts**: Google Fonts (Inter)
