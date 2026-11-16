import pytest
from app import app, db
from models import User, Department, Doctor, Room, Bed, Equipment

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as c:
        with app.app_context():
            yield c


def login_admin(client):
    admin = User.query.filter_by(username='admin').first()
    with client.session_transaction() as sess:
        sess['user_id'] = admin.id
        sess['user'] = admin.to_dict()
        sess['role'] = 'admin'
        import hashlib
        sess['pwd_hash'] = hashlib.sha256(admin.password_hash.encode('utf-8')).hexdigest()[:16]


def test_department_crud_operations_and_safeguards(client):
    """Test full Department CRUD and deletion safeguards for linked resources."""
    login_admin(client)

    # 1. Create a department
    res_create = client.post('/api/departments', json={
        'name': 'Oncology Center',
        'capacity': 35,
        'description': 'Cancer treatment and chemotherapy'
    })
    assert res_create.status_code == 201
    created_id = res_create.get_json()['id']

    # 2. Update department
    res_update = client.put(f'/api/departments/{created_id}', json={
        'name': 'Comprehensive Oncology',
        'capacity': 45,
        'description': 'Updated scope'
    })
    assert res_update.status_code == 200
    assert res_update.get_json()['name'] == 'Comprehensive Oncology'
    assert res_update.get_json()['capacity'] == 45

    # 3. Add a linked doctor to this department
    doc = Doctor(
        name='Test Oncologist',
        specialization='Oncology',
        department_id=created_id,
        available_from='09:00',
        available_until='15:00'
    )
    db.session.add(doc)
    db.session.commit()

    # 4. Attempt to delete should fail (Safeguard)
    res_del_fail = client.delete(f'/api/departments/{created_id}')
    assert res_del_fail.status_code == 400
    assert 'physicians are currently assigned' in res_del_fail.get_json()['error']

    # 5. Remove linked doctor and delete successfully
    db.session.delete(doc)
    db.session.commit()

    res_del_ok = client.delete(f'/api/departments/{created_id}')
    assert res_del_ok.status_code == 200
    assert 'deleted successfully' in res_del_ok.get_json()['message']

    # Confirm it is gone
    assert db.session.get(Department, created_id) is None


def test_department_manage_permission_guards(client):
    """Users without departments.manage cannot create, edit, or delete departments."""
    # Login as receptionist who has departments.view but not departments.manage
    with app.app_context():
        rec = User.query.filter_by(username='receptionist').first()
        if not rec:
            rec_role = Role.query.filter_by(name='receptionist').first()
            rec = User(username='receptionist', email='rec@hospital.com', full_name='Receptionist', role_id=rec_role.id)
            db.session.add(rec)
        rec.set_password('Reception#2025!')
        db.session.commit()

    client.post('/api/auth/login', json={'username': 'receptionist', 'password': 'Reception#2025!'})

    res_post = client.post('/api/departments', json={'name': 'Unauthorized Dept'})
    assert res_post.status_code == 403

    res_put = client.put('/api/departments/1', json={'name': 'Unauthorized Change'})
    assert res_put.status_code == 403

    res_del = client.delete('/api/departments/1')
    assert res_del.status_code == 403


def test_ui_templates_and_modals_present():
    """Verify UI polish elements in templates (department modals, toolbar layout, etc.)."""
    with open('templates/departments.html', 'r', encoding='utf-8') as f:
        dept_html = f.read()
    assert 'id="dept-modal"' in dept_html
    assert 'id="delete-dept-modal"' in dept_html
    assert 'openAddDeptModal' in dept_html
    assert 'openEditDeptModal' in dept_html
    assert 'executeDeleteDepartment' in dept_html

    with open('templates/appointments.html', 'r', encoding='utf-8') as f:
        appts_html = f.read()
    # Controls moved into toolbar-right to eliminate top-header overlap
    assert 'class="toolbar-right"' in appts_html
    assert 'id="view-mode-btn"' in appts_html
    assert 'exportCSV()' in appts_html
