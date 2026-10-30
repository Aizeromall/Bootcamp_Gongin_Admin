# 수정 일 : 2026-10-30 / 작업자 : 양태건
# 외부 지도·실제 DB 호출 없이 주소 변환·오류·본사 권한을 검증합니다.
import io
import json
import os
import unittest
from unittest.mock import patch
from urllib.error import URLError
from fastapi import FastAPI
from fastapi.testclient import TestClient
from FastAPI.approval import ground_location as target


def result(name='roadaddr'):
    return {'name': name, 'region': {'area1': {'name': '서울특별시'}, 'area2': {'name': '강남구'}, 'area3': {'name': '역삼동'}},
            'land': {'name': '테헤란로', 'number1': '123', 'number2': '4', 'type': '1'}}


class GroundLocationTest(unittest.TestCase):
    def test_road_address_and_coordinate_order(self):
        response = io.BytesIO(json.dumps({'status': {'code': 0}, 'results': [result()]}).encode())
        with patch.dict(os.environ, {'NAVER_MAPS_CLIENT_ID': 'mock-id', 'NAVER_MAPS_CLIENT_SECRET': 'mock-secret'}), patch.object(target, 'urlopen', return_value=response) as call:
            value = target.reverse_location(37.5, 127.0)
        self.assertEqual(value, {'g_address': '서울특별시 강남구 테헤란로 123-4', 'g_lat': 37.5, 'g_lng': 127.0})
        self.assertIn('coords=127.0%2C37.5', call.call_args.args[0].full_url)
        self.assertEqual(call.call_args.kwargs['timeout'], 5)

    def test_missing_configuration_fails_without_external_request(self):
        with patch.dict(os.environ, {'NAVER_MAPS_CLIENT_ID': '', 'NAVER_MAPS_CLIENT_SECRET': ''}), patch.object(target, 'urlopen') as call:
            with self.assertRaises(target.HTTPException) as error:
                target.reverse_location(37, 127)
            self.assertEqual(error.exception.status_code, 503)
            call.assert_not_called()

    def test_land_address_and_no_detailed_address(self):
        self.assertEqual(target.address_text(result('addr')), '서울특별시 강남구 역삼동 123-4')
        self.assertIsNone(target.address_text({'name': 'roadaddr', 'land': {}}))

    def test_external_failure_is_sanitized(self):
        with patch.dict(os.environ, {'NAVER_MAPS_CLIENT_ID': 'mock-id', 'NAVER_MAPS_CLIENT_SECRET': 'mock-secret'}), patch.object(target, 'urlopen', side_effect=URLError('private-provider-error')):
            with self.assertRaises(target.HTTPException) as error:
                target.reverse_location(37, 127)
            self.assertEqual(error.exception.status_code, 502)
            self.assertNotIn('private', error.exception.detail)

    def test_route_validates_coordinates_and_requires_headquarters(self):
        app = FastAPI()
        app.include_router(target.router)
        client = TestClient(app)
        self.assertEqual(client.get('/approval/ground-location?lat=37&lng=127').status_code, 401)
        app.dependency_overrides[target.require_headquarters] = lambda: 'mock-staff'
        self.assertEqual(client.get('/approval/ground-location?lat=91&lng=127').status_code, 422)
        with patch.object(target, 'reverse_location', return_value={'g_address': '주소', 'g_lat': 37, 'g_lng': 127}):
            self.assertEqual(client.get('/approval/ground-location?lat=37&lng=127').status_code, 200)

if __name__ == '__main__':
    unittest.main()
# 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
