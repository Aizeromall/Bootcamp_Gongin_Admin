# 작업자 : 최현준
# 작업 일 : 2026-10-27
"""실제 ERD의 테이블·컬럼만 둔 가상 DB 검증. 운영 DB에는 접속하거나 쓰지 않습니다."""
import io
import json
import sqlite3
import sys
import tempfile
import unittest
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from FastAPI.approval import groundapproval, groundcontract, groundshoot, vacation, vacationapproval


class Cursor:
    def __init__(self, db):
        self.cursor = db.cursor()

    def execute(self, sql, args=()):
        values = [value.isoformat() if isinstance(value, (date, datetime)) else value for value in args]
        return self.cursor.execute(sql.replace(" FOR UPDATE", "").replace("%s", "?"), values)

    def fetchone(self):
        row = self.cursor.fetchone()
        return dict(row) if row is not None else None

    def fetchall(self):
        return [dict(row) for row in self.cursor.fetchall()]

    @property
    def lastrowid(self):
        return self.cursor.lastrowid


class ApprovalERDTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", check_same_thread=False, detect_types=sqlite3.PARSE_DECLTYPES)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript("""
        CREATE TABLE headquarter(h_id VARCHAR(50) PRIMARY KEY,h_pw VARCHAR(255) NOT NULL,h_name VARCHAR(50) NOT NULL,h_phone VARCHAR(20),h_position VARCHAR(50),h_department VARCHAR(50),h_startdate DATE,h_resignationdate DATE);
        CREATE TABLE memorandum(m_code INTEGER PRIMARY KEY AUTOINCREMENT,m_content TEXT);
        CREATE TABLE approval(a_seq INTEGER PRIMARY KEY AUTOINCREMENT,h_id VARCHAR(50) NOT NULL REFERENCES headquarter(h_id),m_code INTEGER NOT NULL REFERENCES memorandum(m_code),a_reason TEXT,a_state VARCHAR(20),a_step INTEGER,a_date DATETIME,a_signatures VARCHAR(255) CHECK(a_signatures IS NULL OR length(a_signatures)<=255),a_price INTEGER);
        CREATE TABLE owner(o_seq INTEGER PRIMARY KEY AUTOINCREMENT,o_name VARCHAR(100) NOT NULL,o_phone VARCHAR(20));
        CREATE TABLE ground(g_code INTEGER PRIMARY KEY AUTOINCREMENT,g_name VARCHAR(100) NOT NULL,g_address VARCHAR(255),g_lat DECIMAL(10,7),g_lng DECIMAL(10,7),g_num INTEGER,g_information TEXT,g_time VARCHAR(100),g_price INTEGER,e_code VARCHAR(50) NOT NULL DEFAULT '');
        CREATE TABLE contract(c_seq INTEGER PRIMARY KEY AUTOINCREMENT,h_id VARCHAR(50) NOT NULL REFERENCES headquarter(h_id),o_seq INTEGER NOT NULL REFERENCES owner(o_seq),m_code INTEGER REFERENCES memorandum(m_code),c_date DATE,c_record VARCHAR(255) CHECK(c_record IS NULL OR length(c_record)<=255),c_treaty TEXT,c_rentalfee INTEGER);
        CREATE TABLE maintain(maintain_seq INTEGER PRIMARY KEY AUTOINCREMENT,g_code INTEGER NOT NULL REFERENCES ground(g_code),o_seq INTEGER NOT NULL REFERENCES owner(o_seq),m_date DATE,m_content TEXT,m_name VARCHAR(50),m_department VARCHAR(50));
        CREATE TABLE match_manager(m_id VARCHAR(50) PRIMARY KEY,m_name VARCHAR(50),m_department VARCHAR(50),m_resignationdate DATE,m_workplace VARCHAR(100));
        CREATE TABLE assign(assign_seq INTEGER PRIMARY KEY AUTOINCREMENT,h_id VARCHAR(50) NOT NULL REFERENCES headquarter(h_id),m_id VARCHAR(50) NOT NULL REFERENCES match_manager(m_id),g_code INTEGER NOT NULL REFERENCES ground(g_code),a_day VARCHAR(50),a_time VARCHAR(50));
        CREATE TABLE shoot(shoot_seq INTEGER PRIMARY KEY AUTOINCREMENT,h_id VARCHAR(50) NOT NULL REFERENCES headquarter(h_id),g_code INTEGER NOT NULL REFERENCES ground(g_code),s_date DATE,s_image VARCHAR(255));
        CREATE TABLE h_vacation(v_seq INTEGER PRIMARY KEY AUTOINCREMENT,h_id VARCHAR(50) NOT NULL REFERENCES headquarter(h_id),h_deputy VARCHAR(50) REFERENCES headquarter(h_id),h_start DATE NOT NULL,h_end DATE NOT NULL,CHECK(h_end>=h_start));
        INSERT INTO memorandum(m_content) VALUES('신규 계약 양식'),('해지 양식'),('휴가 양식'),('재계약 양식');
        INSERT INTO match_manager(m_id,m_name,m_department) VALUES('mgr','가상 매니저','매니저'),('mgr2','두 번째 매니저','매니저');
        """)
        people = [('sales','오지은','영업팀','사원'),('lead','박성호','영업팀','팀장'),('exec','김태준','영업팀','임원'),
                  ('hr','인사사원','인사팀','사원'),('hrlead','인사팀장','인사팀','팀장'),('hrexec','인사임원','인사팀','임원'),
                  ('worker','휴가신청자','운영팀','사원'),('deputy','대리자','운영팀','사원'),('third','세번째직원','운영팀','사원'),
                  ('salesdeputy','영업대리자','영업팀','사원')]
        self.db.executemany("INSERT INTO headquarter(h_id,h_pw,h_name,h_department,h_position) VALUES(?,'pw',?,?,?)", people)
        self.db.commit()
        @contextmanager
        def database(write=False):
            try:
                yield Cursor(self.db)
                if write:
                    self.db.commit()
            except Exception:
                self.db.rollback()
                raise
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.patches = [patch.object(module, 'database', database) for module in (groundapproval,groundcontract,groundshoot,vacation)]
        self.patches.append(patch.object(groundshoot, 'UPLOAD_ROOT', self.root))
        for item in self.patches:
            item.start()
        self.app = FastAPI()
        for module in (groundapproval,groundcontract,groundshoot,vacation):
            self.app.include_router(module.router)
        self.client = TestClient(self.app)
        self.start = date.today() + timedelta(days=10)
        self.end = self.start + timedelta(days=2)

    def tearDown(self):
        self.client.close()
        for item in reversed(self.patches):
            item.stop()
        self.db.close()
        self.temp.cleanup()

    def upload(self, h_id='sales'):
        data = io.BytesIO()
        Image.new('RGB',(2,2)).save(data, format='PNG')
        response = self.client.post('/approval/ground-photos/draft', data={'h_id':h_id}, files={'file':('photo.png',data.getvalue(),'image/png')})
        self.assertEqual(response.status_code,201,response.text)
        return response.json()['s_image']

    def contract_data(self):
        return dict(owner_mode='신규',o_name='가상 소유주',o_phone='010-0000-0000',
                    g_name='반포 한강 코트',e_code='농구',g_address='서울 서초구 반포동',
                    g_lat=37.5101234,g_lng=126.9954321,g_num=12,g_information='실내화 착용, 주차 가능',
                    g_time='09:00~22:00',g_price=30000,c_treaty='구두 합의 조건과 계약 기간',c_rentalfee=100000,
                    s_image=[self.upload()],assignments=[dict(m_id='mgr',a_day=['월','수'],a_period='오전',a_start='09:00',a_end='12:00')])

    def submit(self, data, template=1, author='sales', line=None):
        return self.client.post('/approval/requests',json={'h_id':author,'m_code':template,'a_reason':'가상 품의 사유',
                                'approver_ids':line or ['sales','lead','exec'],'data':data})

    def sign(self, code, actors=('sales','lead','exec')):
        response = None
        for actor in actors:
            response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':actor,'approve':True})
            self.assertEqual(response.status_code,200,response.text)
        return response.json()

    def new_contract(self):
        response = self.submit(self.contract_data())
        self.assertEqual(response.status_code,201,response.text)
        code = response.json()['m_code']
        self.sign(code)
        return code, dict(self.db.execute('SELECT * FROM contract ORDER BY c_seq DESC LIMIT 1').fetchone())

    def test_no_invented_columns_in_virtual_schema(self):
        expected = {
            'approval':{'a_seq','h_id','m_code','a_reason','a_state','a_step','a_date','a_signatures','a_price'},
            'memorandum':{'m_code','m_content'},
            'contract':{'c_seq','h_id','o_seq','m_code','c_date','c_record','c_treaty','c_rentalfee'},
            'assign':{'assign_seq','h_id','m_id','g_code','a_day','a_time'},
            'h_vacation':{'v_seq','h_id','h_deputy','h_start','h_end'}}
        for table, fields in expected.items():
            self.assertEqual({row['name'] for row in self.db.execute('PRAGMA table_info('+table+')')}, fields)

    def test_template_read_without_added_type_column(self):
        response = self.client.get('/approval/templates')
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(len(response.json()['results']),4)
        self.assertEqual(set(response.json()['results'][0]),{'m_code','m_content'})
        self.assertEqual(self.client.get('/approval/approvers?m_code=3').status_code,200)

    def test_submit_and_three_approvals_append_existing_relation_rows(self):
        data = self.contract_data()
        response = self.submit(data)
        self.assertEqual(response.status_code,201,response.text)
        code = response.json()['m_code']
        self.assertNotEqual(code,1)
        self.assertEqual(self.db.execute('SELECT m_content FROM memorandum WHERE m_code=1').fetchone()[0],'신규 계약 양식')
        document = json.loads(self.db.execute('SELECT m_content FROM memorandum WHERE m_code=?',(code,)).fetchone()[0])
        self.assertEqual(document['내용']['new_ground']['g_address'],data['g_address'])
        self.sign(code,('sales','lead'))
        self.assertEqual(self.db.execute('SELECT count(*) FROM ground').fetchone()[0],0)
        self.sign(code,('exec',))
        rows = [dict(r) for r in self.db.execute('SELECT * FROM approval WHERE m_code=? ORDER BY a_seq',(code,))]
        self.assertEqual([r['a_step'] for r in rows],[0,1,2,3])
        self.assertEqual([r['h_id'] for r in rows],['sales','sales','lead','exec'])
        self.assertEqual([r['a_state'] for r in rows],['심사중','심사중','심사중','승인완료'])
        self.assertTrue(all(len(r['a_signatures'] or '')<=255 for r in rows))
        self.assertEqual(self.db.execute('SELECT count(*) FROM contract').fetchone()[0],1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM maintain').fetchone()[0],1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM shoot').fetchone()[0],1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM assign').fetchone()[0],1)
        ground = dict(self.db.execute('SELECT * FROM ground').fetchone())
        for key in ('g_name','e_code','g_address','g_lat','g_lng','g_num','g_information','g_time','g_price'):
            self.assertEqual(ground[key],data[key])
        contract = dict(self.db.execute('SELECT * FROM contract').fetchone())
        link = dict(self.db.execute('SELECT * FROM maintain').fetchone())
        self.assertEqual(link['o_seq'],contract['o_seq'])
        self.assertEqual(link['g_code'],ground['g_code'])

    def test_existing_owner_selected_without_new_owner(self):
        self.db.execute("INSERT INTO owner(o_name) VALUES('기존소유주')")
        self.db.commit()
        data = self.contract_data()
        data.pop('o_name'); data.pop('o_phone')
        data.update(owner_mode='기존',o_seq=1)
        response = self.submit(data)
        self.assertEqual(response.status_code,201,response.text)
        self.sign(response.json()['m_code'])
        self.assertEqual(self.db.execute('SELECT count(*) FROM owner').fetchone()[0],1)

    def test_renewal_and_termination_append_contract_history_without_status_columns(self):
        code, contract = self.new_contract()
        ground = self.db.execute('SELECT g_code FROM ground').fetchone()[0]
        response = self.submit({'g_code':ground,'c_treaty':'계약 기간 1년 연장','c_rentalfee':120000},template=4)
        self.assertEqual(response.status_code,201,response.text)
        renewed_code = response.json()['m_code']
        self.sign(renewed_code)
        records = [dict(r) for r in self.db.execute('SELECT * FROM contract ORDER BY c_seq')]
        self.assertEqual(len(records),2)
        self.assertEqual(records[0]['c_rentalfee'],100000)
        self.assertEqual(records[1]['c_rentalfee'],120000)
        response = self.submit({'c_seq':records[1]['c_seq']},template=2)
        self.assertEqual(response.status_code,201,response.text)
        self.sign(response.json()['m_code'])
        self.assertEqual(self.db.execute('SELECT count(*) FROM contract').fetchone()[0],3)
        self.assertEqual(self.db.execute('SELECT count(*) FROM ground').fetchone()[0],1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM assign').fetchone()[0],1)
        response = self.submit({'g_code':ground,'c_treaty':'해지후 연장','c_rentalfee':100},template=4)
        self.assertEqual(response.status_code,409,response.text)

    def test_wrong_signer_and_duplicate_final_approval(self):
        response = self.submit(self.contract_data())
        code = response.json()['m_code']
        response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'exec','approve':True})
        self.assertEqual(response.status_code,403)
        self.sign(code)
        response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'exec','approve':True})
        self.assertEqual(response.status_code,409)
        self.assertEqual(self.db.execute('SELECT count(*) FROM contract').fetchone()[0],1)

    def test_rejection_keeps_previous_rows(self):
        code = self.submit(self.contract_data()).json()['m_code']
        response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'sales','approve':False,'comment':'조건 재검토'})
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(self.db.execute('SELECT count(*) FROM approval').fetchone()[0],2)
        self.assertEqual(self.db.execute('SELECT count(*) FROM ground').fetchone()[0],0)

    def test_atomic_finalization_rollback_includes_relation_insert(self):
        code = self.submit(self.contract_data()).json()['m_code']
        self.sign(code,('sales','lead'))
        original = groundcontract.finalize_ground
        def broken(*args):
            original(*args)
            raise RuntimeError('가상 저장 실패')
        with patch.object(groundcontract,'finalize_ground',broken):
            with self.assertRaises(RuntimeError):
                self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'exec','approve':True})
        for table in ('ground','owner','contract','maintain','assign','shoot'):
            self.assertEqual(self.db.execute('SELECT count(*) FROM '+table).fetchone()[0],0,table)
        self.assertEqual(self.db.execute('SELECT count(*) FROM approval').fetchone()[0],3)

    def test_delegated_signature_keeps_original_in_existing_signature_column(self):
        self.db.execute('INSERT INTO h_vacation(h_id,h_deputy,h_start,h_end) VALUES(?,?,?,?)',
                        ('lead','salesdeputy',date.today().isoformat(),date.today().isoformat()))
        self.db.commit()
        code = self.submit(self.contract_data()).json()['m_code']
        self.sign(code,('sales','salesdeputy','exec'))
        record = self.db.execute('SELECT a_signatures FROM approval WHERE m_code=? AND a_step=2',(code,)).fetchone()[0]
        self.assertEqual(json.loads(record)['original_h_id'],'lead')
        self.assertEqual(json.loads(record)['h_id'],'salesdeputy')

    def test_vacation_and_pending_deputy_conflict(self):
        data = {'h_start':self.start.isoformat(),'h_end':self.end.isoformat(),'h_deputy':'deputy'}
        line = ['hr','hrlead','hrexec']
        response = self.submit(data,3,'worker',line)
        self.assertEqual(response.status_code,201,response.text)
        code = response.json()['m_code']
        data['h_deputy']='third'
        response = self.submit(data,3,'deputy',line)
        self.assertEqual(response.status_code,409,response.text)
        self.sign(code,tuple(line))
        self.assertEqual(self.db.execute('SELECT count(*) FROM h_vacation').fetchone()[0],1)
        self.assertEqual(self.db.execute('SELECT count(*) FROM approval WHERE m_code=?',(code,)).fetchone()[0],4)

    def test_vacation_rechecks_before_final_approval(self):
        data = {'h_start':self.start.isoformat(),'h_end':self.end.isoformat(),'h_deputy':'deputy'}
        code = self.submit(data,3,'worker',['hr','hrlead','hrexec']).json()['m_code']
        self.sign(code,('hr','hrlead'))
        self.db.execute('INSERT INTO h_vacation(h_id,h_deputy,h_start,h_end) VALUES(?,?,?,?)',
                        ('deputy','third',self.start.isoformat(),self.end.isoformat()))
        self.db.commit()
        response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'hrexec','approve':True})
        self.assertEqual(response.status_code,409,response.text)
        self.assertEqual(self.db.execute("SELECT count(*) FROM h_vacation WHERE h_id='worker'").fetchone()[0],0)

    def test_pending_manager_conflict_and_final_recheck(self):
        data = self.contract_data()
        code = self.submit(data).json()['m_code']
        other = self.contract_data(); other.update(g_name='다른 코트',g_address='다른 주소')
        self.assertEqual(self.submit(other).status_code,409)
        self.sign(code,('sales','lead'))
        self.db.execute("INSERT INTO ground(g_name,g_time) VALUES('기존 구장','09:00~22:00')")
        ground_id = self.db.execute('SELECT g_code FROM ground').fetchone()[0]
        self.db.execute("INSERT INTO assign(h_id,m_id,g_code,a_day,a_time) VALUES('sales','mgr',?,'월','10:00~12:00')",(ground_id,))
        self.db.commit()
        response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'exec','approve':True})
        self.assertEqual(response.status_code,409,response.text)
        self.assertEqual(self.db.execute('SELECT count(*) FROM contract').fetchone()[0],0)

    def test_reads_have_no_authentication_and_include_names(self):
        code = self.submit(self.contract_data()).json()['m_code']
        for path in ('/approval/templates','/approval/requests',f'/approval/requests/{code}',
                     '/approval/grounds/owners','/approval/grounds/managers','/approval/contracts','/approval/vacation','/approval/ground-photos'):
            response = self.client.get(path)
            self.assertEqual(response.status_code,200,(path,response.text))
        detail = self.client.get(f'/approval/requests/{code}').json()
        self.assertEqual(detail['approval'][0]['h_name'],'오지은')

    def test_photo_uses_file_name_and_existing_shoot_only(self):
        image = self.upload()
        response = self.client.get('/approval/ground-photos/files/'+image)
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(self.db.execute('SELECT count(*) FROM shoot').fetchone()[0],0)
        response = self.client.post('/approval/ground-photos/draft',data={'h_id':'sales'},files={'file':('bad.png',b'bad','image/png')})
        self.assertEqual(response.status_code,400)
        data = self.contract_data()
        data['s_image']=[self.upload('lead')]
        self.assertEqual(self.submit(data).status_code,400)

    def test_required_ground_fields_and_four_sport_names(self):
        base = self.contract_data()
        for key in ('g_name','e_code','g_address','g_lat','g_lng','g_num','g_information','g_time','g_price'):
            data = dict(base); data.pop(key)
            self.assertEqual(self.submit(data).status_code,400,key)
        for e_code in ('축구','농구','배구','야구'):
            data = dict(base); data['e_code']=e_code
            response = self.submit(data)
            self.assertEqual(response.status_code,201,response.text)
            code = response.json()['m_code']
            response = self.client.post(f'/approval/requests/{code}/sign',json={'h_id':'sales','approve':False,'comment':'가상 종목 검증 완료'})
            self.assertEqual(response.status_code,200)
        for invalid in ('테니스',['축구','농구'],1):
            data = dict(base); data['e_code']=invalid
            self.assertEqual(self.submit(data).status_code,400)

    def test_swagger_and_source_do_not_depend_on_added_database_columns(self):
        schema = self.app.openapi()
        self.assertIn('/approval/requests/{m_code}/sign',schema['paths'])
        self.assertNotIn('/approval/requests/{a_seq}/sign',schema['paths'])
        content = schema['paths']['/approval/requests']['post']['requestBody']['content']['application/json']
        self.assertIn('s_image',content['examples']['new_owner']['value']['data'])
        forbidden = ('a_payload','a_kind','m_kind','approval_ground_photo','c_expires','c_enddate','c_state','a_active','photo_ids','approval_id')
        for path in (Path(__file__).resolve().parents[1] / 'FastAPI' / 'approval').glob('*.py'):
            source = path.read_text()
            for token in forbidden:
                self.assertNotIn(token,source,(path.name,token))

    def test_existing_ground_search_reads_new_ground(self):
        code, contract = self.new_contract()
        from FastAPI.match import ground_search
        @contextmanager
        def cursor(*args):
            yield Cursor(self.db)
        connection = SimpleNamespace(cursor=cursor,close=lambda:None)
        self.app.include_router(ground_search.router,prefix='/match')
        with patch.object(ground_search,'connect',return_value=connection):
            response = self.client.get('/match/ground')
            self.assertEqual(response.status_code,200,response.text)
            self.assertEqual(response.json()['results'][0]['e_code'],'농구')


if __name__ == '__main__':
    unittest.main()
# 최종 수정일 : 2026-10-27
