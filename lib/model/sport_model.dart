// ###  2026.10.23 종목 모델 클래스 구성
//
// [이 파일의 역할]
// 앱에서 쓰는 4개 종목(축구·농구·야구·배구)과 회원 아이디(c_id_seq) 끝 번호의 대응표
//   c_id_seq 형식 : 회원아이디_01 (01=축구, 02=농구, 03=야구, 04=배구)
//   회원은 가입 시 고른 선호 종목마다 customer 행이 따로 생기고, 예약·문의는 선택한 종목의 c_id_seq로 처리

import 'package:flutter/material.dart';

class Sport {
  final int code; // 종목 번호 (1~4) = c_id_seq 끝 번호
  final String name; // 종목 이름
  final IconData icon; // 화면 표시용 아이콘

  const Sport(this.code, this.name, this.icon);

  // 전체 종목 목록 (회원가입 선택, 종목 선택 화면에서 사용)
  static const List<Sport> all = [
    Sport(1, '축구', Icons.sports_soccer),
    Sport(2, '농구', Icons.sports_basketball),
    Sport(3, '야구', Icons.sports_baseball),
    Sport(4, '배구', Icons.sports_volleyball),
  ];

  // 서버가 준 값(1, "1", "축구" 등)을 Sport로 변환. 알 수 없는 값이면 null
  // 로그인 응답의 preferred_stocks가 종목 번호 또는 종목 이름으로 올 수 있어서 둘 다 처리
  static Sport? fromValue(dynamic value) {
    final text = value.toString().trim();
    final number = int.tryParse(text);
    for (final sport in all) {
      if (sport.code == number || sport.name == text) return sport;
    }
    return null;
  }
}
