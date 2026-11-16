import pytest
from app import app, db
from models import User, Department, Doctor, Patient, Room, Appointment
from optimizer import run_greedy, run_hybrid, run_optimization, run_scenario_simulation

@pytest.fixture
def opt_client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        with app.app_context():
            yield client


def setup_capacity_constrained_scenario(target_date):
    """Seed doctors and patients where demand exceeds doctor capacity or specializations mismatch."""
    Appointment.query.filter_by(date=target_date).delete()
    db.session.commit()

    dept = Department.query.filter_by(name='Cardiology').first() or Department(name='Cardiology', capacity=50)
    db.session.add(dept)
    db.session.flush()

    doc = Doctor.query.filter_by(name='Test Constrained Doc').first()
    if not doc:
        doc = Doctor(
            name='Test Constrained Doc',
            specialization='Cardiology',
            department_id=dept.id,
            available_from='08:00',
            available_until='10:00',
            max_patients_per_day=1
        )
        db.session.add(doc)
    else:
        doc.max_patients_per_day = 1
        doc.available_from = '08:00'
        doc.available_until = '10:00'

    room = Room.query.filter_by(room_number='R-OPT-1').first()
    if not room:
        room = Room(room_number='R-OPT-1', room_type='consultation', department_id=dept.id)
        db.session.add(room)
    db.session.flush()

    # Patient 1: Cardiology (will be assigned)
    p1 = Patient(
        name='Patient One',
        age=40,
        gender='M',
        priority='critical',
        required_specialization='Cardiology',
        preferred_date=target_date
    )
    # Patient 2: Cardiology (will be skipped due to doc max_patients_per_day = 1)
    p2 = Patient(
        name='Patient Two',
        age=55,
        gender='F',
        priority='urgent',
        required_specialization='Cardiology',
        preferred_date=target_date
    )
    # Patient 3: Dermatology (will be skipped due to no matching doctor)
    p3 = Patient(
        name='Patient Three',
        age=30,
        gender='M',
        priority='normal',
        required_specialization='Dermatology',
        preferred_date=target_date
    )

    db.session.add_all([p1, p2, p3])
    db.session.commit()

    return {'doc': doc, 'room': room, 'p1': p1, 'p2': p2, 'p3': p3}


def test_unassigned_details_and_reasons_in_optimizer():
    """Verify optimizer records accurate per-patient unassigned reasons."""
    target_date = "2032-04-15"
    with app.app_context():
        data = setup_capacity_constrained_scenario(target_date)
        patients = [data['p1'], data['p2'], data['p3']]
        doctors = [data['doc']]
        rooms = [data['room']]

        # Test Greedy
        res_greedy = run_greedy(patients, doctors, rooms, target_date)
        assert len(res_greedy.assignments) == 1
        assert len(res_greedy.unassigned) == 2
        assert len(res_greedy.unassigned_details) == 2

        details_map = {item['patient_id']: item for item in res_greedy.unassigned_details}
        # Patient 3 mismatch specialization
        assert data['p3'].id in details_map
        assert 'specialization' in details_map[data['p3'].id]['reason'].lower() or 'matching' in details_map[data['p3'].id]['reason'].lower()

        # Patient 2 doctor capacity full
        assert data['p2'].id in details_map
        assert 'capacity' in details_map[data['p2'].id]['reason'].lower() or 'quota' in details_map[data['p2'].id]['reason'].lower()

        # Test Unified run_optimization wrapper
        opt_res = run_optimization('greedy', patients, doctors, rooms, target_date)
        assert opt_res['skipped_count'] == 2
        assert len(opt_res['unassigned_details']) == 2
        assert len(opt_res['skipped_reasons']) >= 1


def test_api_optimize_endpoint_returns_skipped_breakdown(opt_client):
    """Verify /api/optimize returns skipped_count, skipped_reasons, and unassigned_details."""
    # Log in as admin
    with opt_client.session_transaction() as sess:
        admin_user = User.query.filter_by(username='admin').first()
        sess['user_id'] = admin_user.id
        sess['user'] = admin_user.to_dict()
        sess['role'] = 'admin'

    target_date = "2032-04-16"
    setup_capacity_constrained_scenario(target_date)

    res = opt_client.post('/api/optimize', json={
        'algorithm': 'greedy',
        'date': target_date,
        'clear_existing': True
    })
    assert res.status_code == 200
    data = res.get_json()
    assert data['status'] == 'success'
    assert 'skipped_count' in data
    assert 'skipped_reasons' in data
    assert 'unassigned_details' in data
    assert data['metrics']['unassigned'] == data['skipped_count']


def test_simulator_baseline_aligned_with_optimizer():
    """Verify simulator baseline matches run_optimization."""
    target_date = "2032-04-17"
    with app.app_context():
        data = setup_capacity_constrained_scenario(target_date)
        patients = [data['p1'], data['p2'], data['p3']]
        doctors = [data['doc']]
        rooms = [data['room']]

        sim = run_scenario_simulation(patients, doctors, rooms, target_date, patient_surge_percent=0)
        direct_opt = run_optimization('hybrid', patients, doctors, rooms, target_date)

        assert sim['baseline']['total_patients'] == direct_opt['metrics']['total']
        assert sim['baseline']['assigned'] == direct_opt['metrics']['assigned']
        assert sim['baseline']['unassigned'] == direct_opt['metrics']['unassigned']
        assert sim['baseline']['utilization_rate'] == direct_opt['metrics']['utilization_rate']
