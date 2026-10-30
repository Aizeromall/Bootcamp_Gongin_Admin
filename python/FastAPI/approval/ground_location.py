# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 지도에서 고른 좌표를 주소로 변환합니다. 이 API는 DB에 쓰지 않습니다.
import json
import logging
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException, Query
from ..education.education_access import require_headquarters

router = APIRouter(prefix='/approval/ground-location', tags=['구장 위치 선택'])
logger = logging.getLogger(__name__)


def address_text(result):
    region = result.get('region') or {}
    parts = [(region.get(f'area{i}') or {}).get('name', '') for i in range(1, 3)]
    town = (region.get('area3') or {}).get('name', '')
    if result.get('name') != 'roadaddr' or town.endswith(('읍', '면')):
        parts.append(town)
    land = result.get('land') or {}
    if result.get('name') == 'roadaddr':
        parts.append(land.get('name', ''))
    else:
        parts.append((region.get('area4') or {}).get('name', ''))
    number = str(land.get('number1') or '')
    if not number:
        return None  # 행정구역만 반환된 위치를 상세 주소처럼 저장하지 않습니다.
    if result.get('name') != 'roadaddr' and str(land.get('type')) == '2':
        number = '산' + number
    if land.get('number2'):
        number += '-' + str(land['number2'])
    parts.append(number)
    return ' '.join(part.strip() for part in parts if part and part.strip())


def reverse_location(lat, lng):
    key_id = os.getenv('NAVER_MAPS_CLIENT_ID', '').strip()
    secret = os.getenv('NAVER_MAPS_CLIENT_SECRET', '').strip()
    if not key_id or not secret:
        raise HTTPException(503, '지도 주소 조회 설정이 필요합니다. 관리자에게 문의해 주세요.')
    query = urlencode({'coords': f'{lng},{lat}', 'sourcecrs': 'epsg:4326',
                       'orders': 'roadaddr,addr', 'output': 'json'})
    request = Request('https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc?' + query,
                      headers={'x-ncp-apigw-api-key-id': key_id, 'x-ncp-apigw-api-key': secret})
    try:
        with urlopen(request, timeout=5) as response:
            payload = json.load(response)
        if payload.get('status', {}).get('code') != 0:
            raise HTTPException(422, '이 위치의 주소를 찾지 못했습니다. 다른 위치를 선택해 주세요.')
        results = payload.get('results') or []
        for name in ('roadaddr', 'addr'):
            for result in results:
                if result.get('name') == name and (address := address_text(result)):
                    if len(address) > 255:
                        raise HTTPException(422, '주소가 너무 깁니다. 다른 위치를 선택해 주세요.')
                    return {'g_address': address, 'g_lat': lat, 'g_lng': lng}
        raise HTTPException(422, '상세 주소가 없는 위치입니다. 구장 위치를 다시 선택해 주세요.')
    except HTTPException:
        raise
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError, AttributeError):
        logger.warning('지도 주소 변환 요청 실패')
        raise HTTPException(502, '주소를 불러오지 못했습니다. 잠시 후 다시 선택해 주세요.') from None


@router.get('')
def location(lat: float = Query(..., ge=-90, le=90),
             lng: float = Query(..., ge=-180, le=180),
             staff_id: str = Depends(require_headquarters)):
    return reverse_location(lat, lng)
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
