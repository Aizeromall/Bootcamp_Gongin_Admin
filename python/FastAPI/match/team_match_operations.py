# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 경기 시간대의 실제 예약자만 팀별 출석·경기 기록 대상으로 사용합니다.
from copy import deepcopy
from datetime import datetime
from zoneinfo import ZoneInfo
import logging
import time

import pymysql
from fastapi import APIRouter, Depends, HTTPException
from database import connect
from . import match_operations as operations
from .manager_session import require_manager
from .team_match_search import TEAM_MATCH_SELECT
from .match_schedule import NOT_CANCELED_CONDITION
from .match_result_insert import (
    SPORT_BY_SEQUENCE, PlayerRecord, TeamMatchResult,
    persist_team_match_result,
)

router = APIRouter(prefix="/match/team_operations", tags=["팀매칭 경기 운영"])
logger = logging.getLogger(__name__)


def load_team(cursor, code, manager_id):
    cursor.execute(TEAM_MATCH_SELECT + " WHERE base.team_code=%s AND rm.m_id=%s", (code, manager_id))
    match = cursor.fetchone()
    if match is None:
        raise HTTPException(404, "담당하는 성사된 팀매칭이 아닙니다.")
    if match['rental_r_seq'] is None:
        raise HTTPException(409, "성사된 구장대여 예약을 확인할 수 없습니다.")
    if not match.get('home_t_name') or not match.get('away_t_name'):
        raise HTTPException(409, "홈·원정 팀 정보를 확인할 수 없습니다.")
    key = str(code)
    cached = operations._MATCHES.get(key)
    cursor.execute("SELECT 1 FROM t_result_record WHERE t_r_r_m_code=%s LIMIT 1", (key,))
    if cursor.fetchone() is not None:
        if cached and cached[0]['m_id'] == manager_id and cached[0]['status'] == 'completed':
            return deepcopy(cached)
        raise HTTPException(409, "완료된 경기는 팀매칭 결과에서 확인해 주세요.")
    if match['team_start'].date() < datetime.now(ZoneInfo('Asia/Seoul')).date():
        raise HTTPException(409, "오늘 이전 팀매칭은 진행할 수 없습니다.")
    sport = SPORT_BY_SEQUENCE.get(str(match.get('home_sport')))
    if sport is None or sport != SPORT_BY_SEQUENCE.get(str(match.get('away_sport'))):
        raise HTTPException(409, "홈·원정 팀의 종목을 확인해 주세요.")
    # 팀 전체 명단이 아닌 동일 구장·날짜·시작/종료 시간의 유효 대여 예약만 조회합니다.
    cursor.execute(f"""SELECT r.r_seq, r.c_id_seq, c.c_name, c.c_position, c.c_rating,
        c.c_prefer_stock, c.c_team
        FROM reservation r JOIN customer c ON c.c_id_seq=r.c_id_seq
        WHERE r.g_code=%s AND r.r_date=DATE(%s) AND r.rs_time=TIME(%s)
          AND (r.re_time=TIME(%s) OR (r.re_time='24:00:00' AND TIME(%s)='00:00:00'))
          AND r.reservation_category=2
          AND {NOT_CANCELED_CONDITION} AND c.c_deletdate IS NULL
          AND c.c_team IN (%s,%s)
        ORDER BY r.r_seq""", (match['rental_g_code'], match['team_start'], match['team_start'],
                              match['team_end'], match['team_end'], match['home_t_name'], match['away_t_name']))
    rows = cursor.fetchall()
    # 잘못된 다른 종목 회원 ID는 조용히 출전자로 사용하지 않습니다.
    if any(SPORT_BY_SEQUENCE.get(str(r['c_prefer_stock'])) != sport for r in rows):
        raise HTTPException(409, "예약자의 종목과 팀매칭 종목이 다릅니다.")
    state = operations.initial_state(rows)
    sides = {str(r['r_seq']): 'A' if r['c_team'] == match['home_t_name'] else 'B' for r in rows}
    # 중복 예약이 있어도 initial_state가 선택한 회원당 대표 예약번호만 유지합니다.
    sides = {str(p['r_seq']): sides[str(p['r_seq'])] for p in state['players']}
    if cached:
        if cached[0]['m_id'] != manager_id:
            raise HTTPException(403, "다른 담당자가 진행 중인 팀매칭입니다.")
        record, previous = deepcopy(cached)
        if record['status'] != 'attendance':
            if previous['fixed_sides'] != sides:
                raise HTTPException(409, "출전 예약 명단이 변경됐습니다. 담당자에게 확인해 주세요.")
            return record, previous
        state = previous
        state['players'] = operations.initial_state(rows)['players']
        state['attendance'] = {k: v for k, v in state['attendance'].items() if k in sides}
    else:
        record = dict(match_code=key, anchor_r_seq=code, m_id=manager_id,
                      g_code=match['rental_g_code'], g_name=match['rental_g_name'],
                      match_date=match['team_start'].date().isoformat(),
                      start_time=match['team_start'].strftime('%H:%M:%S'), status='attendance',
                      version=0, kind='team')
        cursor.execute("SELECT c_id_seq,c_r_r_attendance FROM c_result_record WHERE c_r_r_code=%s ORDER BY c_r_r_seq", (key,))
        saved = {r['c_id_seq']: r['c_r_r_attendance'] for r in cursor.fetchall()}
        state['attendance'] = {str(p['r_seq']): bool(saved[p['c_id_seq']]) for p in state['players']
                               if saved.get(p['c_id_seq']) is not None}
    state['fixed_sport'] = sport
    state['fixed_sides'] = sides
    state['team_names'] = [match['home_t_name'], match['away_t_name']]
    state['team_colors'] = ['green', 'blue']
    state['injuries'] = operations.read_injuries(cursor, record, state['players'])
    return record, state


def mutate_team(cursor, record, state, command):
    if record['status'] == 'completed':
        if command.action == 'publish':
            return
        raise HTTPException(409, "이미 결과가 등록된 경기입니다.")
    if command.version != record['version']:
        raise HTTPException(409, "갱신된 경기 상태를 다시 불러와 주세요.")
    if command.action in ('teams', 'back'):
        raise HTTPException(409, "팀매칭은 홈·원정 팀을 변경할 수 없습니다.")
    if command.action == 'start':
        if record['status'] != 'attendance':
            raise HTTPException(409, "출석 확인 후 시작해 주세요.")
        if not state['players'] or any(str(p['r_seq']) not in state['attendance'] for p in state['players']):
            raise HTTPException(409, "모든 예약자의 출석 또는 결석을 확인해 주세요.")
        # 고정 팀은 인원 차이를 강제로 맞추지 않으며 양 팀에 출석자가 있어야 합니다.
        assigned = {key: side for key, side in state['fixed_sides'].items() if state['attendance'].get(key)}
        if set(assigned.values()) != {'A', 'B'}:
            raise HTTPException(409, "홈·원정 팀 모두 출석자가 있어야 시작할 수 있습니다.")
        state['assignments'] = assigned
        state['running_since'] = time.time()
        record['status'] = 'live'
    elif command.action == 'publish':
        if record['status'] != 'review':
            raise HTTPException(409, "경기 종료 후 결과를 확인해 주세요.")
        stats, scores = operations.totals(state)
        groups = {'A': [], 'B': []}
        for player in state['players']:
            key = str(player['r_seq'])
            if state['attendance'].get(key):
                groups[state['fixed_sides'][key]].append(PlayerRecord(c_id_seq=player['c_id_seq'], stats=stats[key]))
        result = persist_team_match_result(cursor, record['m_id'], int(record['match_code']),
            TeamMatchResult(home_score=scores['A'], away_score=scores['B'],
                            home_players=groups['A'], away_players=groups['B']))
        state['rating_changes'] = result['members']
        record['status'] = 'completed'
    else:
        operations.mutate(cursor, record, state, command)
        if command.action == 'attendance':
            player = next(p for p in state['players'] if p['r_seq'] == command.r_seq)
            side = state['fixed_sides'][str(player['r_seq'])]
            cursor.execute("""UPDATE c_result_record SET c_r_r_team=%s,e_code=%s
                WHERE c_r_r_code=%s AND c_id_seq=%s""",
                (state['team_names'][0 if side == 'A' else 1], operations.sport_code(state),
                 record['match_code'], player['c_id_seq']))


def handle(code, manager_id, command=None):
    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            # 같은 경기의 출석·명단·결과 요청을 DB에서도 직렬화합니다.
            if command is not None:
                cursor.execute('SELECT team_code FROM team_match WHERE team_code=%s FOR UPDATE', (code,))
                if cursor.fetchone() is None:
                    raise HTTPException(404, '팀매칭을 찾을 수 없습니다.')
            record, state = load_team(cursor, code, manager_id)
            if command is not None:
                completed = record['status'] == 'completed'
                mutate_team(cursor, record, state, command)
                if not completed:
                    record['version'] += 1
        conn.commit()
        operations.remember(record, state)
        return dict(operations.response_for(record, state), kind='team')
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        logger.exception('팀매칭 운영 실패')
        raise HTTPException(500, '팀매칭을 처리하지 못했습니다.')
    finally:
        conn.close()


@router.get('/{code}')
@operations.serialized
def detail(code: int, manager_id: str = Depends(require_manager)):
    return handle(code, manager_id)


@router.post('/{code}')
@operations.serialized
def update(code: int, command: operations.Command, manager_id: str = Depends(require_manager)):
    return handle(code, manager_id, command)

# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
