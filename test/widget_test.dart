import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/main.dart';

void main() {
  testWidgets('앱이 뜨고 빈 상태가 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    // 제목
    expect(find.text('AI Chat — 실습 1'), findsOneWidget);

    // 대화가 없으면 빈 상태 안내 문구가 보인다
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('무엇이든 물어보세요'), findsOneWidget);

    // 입력창과 전송 버튼이 보인다
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });

  testWidgets('답변 전 5초 동안 타이핑 점이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    await tester.enterText(find.byType(TextField), '질문');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    // 전송 직후: 사용자 메시지 + 타이핑 점, 아직 답변 없음
    expect(find.text('질문'), findsOneWidget);
    expect(find.byKey(const ValueKey('typingDots')), findsOneWidget);
    expect(find.textContaining('보내기, 기다리기'), findsNothing);

    // 4.9초까지는 점이 유지된다
    await tester.pump(const Duration(milliseconds: 4900));
    expect(find.byKey(const ValueKey('typingDots')), findsOneWidget);

    // 5초가 지나면 점이 사라지고 답변이 도착한다
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byKey(const ValueKey('typingDots')), findsNothing);
    expect(find.textContaining('보내기, 기다리기'), findsOneWidget);
  });

  testWidgets('메시지를 보내면 준비된 답변이 순서대로 온다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    // 첫 번째 전송 → 첫 번째 준비된 답변
    await tester.enterText(find.byType(TextField), '첫 번째 질문');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('첫 번째 질문'), findsOneWidget);
    expect(
      find.text('오늘은 AI 챗봇에 움직이는 응답을 붙입니다. 보내기, 기다리기, 도착, 실패를 상태로 나눠요.'),
      findsOneWidget,
    );
    expect(find.text('무엇이든 물어보세요'), findsNothing);

    // 두 번째 전송 → 두 번째 준비된 답변
    await tester.enterText(find.byType(TextField), '두 번째 질문');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('두 번째 질문'), findsOneWidget);
    expect(
      find.text('응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다. 그래서 점 3개로 생각 중임을 보여줘요'),
      findsOneWidget,
    );

    // 입력창은 비워짐
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });
}
