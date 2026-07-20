// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_ai_app/main.dart'; // pubspec.yaml의 name이 lecture_ai_app 이어야 함

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 루트 위젯: LectureAiApp (우리가 만든 앱 클래스)
    await tester.pumpWidget(const LectureAiApp());

    // 기본 위젯들이 렌더링되는지 간단 확인
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);     // 질문 입력창
    expect(find.text('질문 보내기'), findsOneWidget);      // 전송 버튼

    // (선택) 버튼 탭 동작까지 트리거 해보기
    await tester.tap(find.text('질문 보내기'));
    await tester.pump(); // setState 후 프레임 진행
  });
}
