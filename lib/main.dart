import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

/// 대화 한 줄. 서버 없이 화면만 만들기 위한 최소 모델.
class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// 오류 종류 — 401/429/500과 타임아웃을 한 곳에서 구분한다.
enum ChatErrorType {
  unauthorized(401, '키/권한을 확인해 주세요'),
  tooManyRequests(429, '잠시 후 다시 시도해 주세요'),
  serverError(500, '응답을 받지 못했습니다'),
  timeout(null, '네트워크를 확인해주세요');

  const ChatErrorType(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  /// HTTP 상태 코드를 오류 타입으로 변환한다. 모르는 코드는 null.
  static ChatErrorType? fromStatusCode(int statusCode) => switch (statusCode) {
    401 => ChatErrorType.unauthorized,
    429 => ChatErrorType.tooManyRequests,
    500 => ChatErrorType.serverError,
    _ => null,
  };
}

/// 화면 상태 — idle / loading / success / error를 하나의 값으로 관리한다.
/// sealed class라서 switch로 모든 상태를 빠짐없이 처리할 수 있다.
sealed class ChatState {
  const ChatState();
}

/// 아직 요청을 보내지 않은 상태.
final class ChatIdle extends ChatState {
  const ChatIdle();
}

/// 응답을 기다리는 상태.
final class ChatLoading extends ChatState {
  const ChatLoading();
}

/// 응답이 도착한 상태.
final class ChatSuccess extends ChatState {
  const ChatSuccess({required this.reply});

  final String reply;
}

/// 요청이 실패한 상태.
final class ChatError extends ChatState {
  const ChatError({required this.type});

  final ChatErrorType type;

  String get message => type.message;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 처음에는 대화가 없다. 첫 메시지를 보내면 빈 상태가 사라진다.
  final List<ChatMessage> _messages = [];

  /// 준비된 AI 답변 — 사용자가 보낼 때마다 순서대로 꺼내 쓰고,
  /// 두 개를 다 쓰면 처음부터 다시 반복한다.
  static const List<String> _preparedReplies = [
    '오늘은 AI 챗봇에 움직이는 응답을 붙입니다. 보내기, 기다리기, 도착, 실패를 상태로 나눠요.',
    '응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다. 그래서 점 3개로 생각 중임을 보여줘요',
  ];

  int _replyIndex = 0;

  /// 답변 전에 점 3개를 보여 주는 시간.
  static const Duration _typingDelay = Duration(seconds: 5);

  /// 이번 실습에서는 세 번째 입력을 429(요청 과다) 오류로 처리한다.
  static const int _rateLimitAtInput = 3;

  /// 화면 상태는 이 값 하나로 관리한다. (idle → loading → success/error)
  ChatState _state = const ChatIdle();
  Timer? _typingTimer;

  /// "다시 시도"일 때는 3번째 입력 429 시뮬레이션을 한 번 건너뛴다.
  bool _skipRateLimitOnce = false;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 입력창의 글자를 목록에 추가하고, 5초 뒤에 준비된 AI 답변을 붙인다.
  void _send() {
    final text = _controller.text.trim();
    // 대기 중인지는 통합 상태로 판단한다.
    if (text.isEmpty || _state is ChatLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _state = const ChatLoading();
    });

    _controller.clear();
    _scrollToBottom();

    _startReplyTimer();
  }

  /// 오류 말풍선의 "다시 시도" — 마지막 요청을 한 번 더 보낸다.
  void _retry() {
    if (_state is! ChatError) return;

    setState(() {
      // 재시도에서는 같은 429 오류가 반복되지 않게 한 번 건너뛴다.
      _skipRateLimitOnce = true;
      _state = const ChatLoading();
    });

    _scrollToBottom();
    _startReplyTimer();
  }

  /// 5초 뒤 응답(또는 오류)을 만드는 공통 타이머.
  void _startReplyTimer() {
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingDelay, () {
      if (!mounted) return;

      setState(() {
        // 세 번째 입력은 성공 대신 429 오류로 끝낸다.
        final userInputCount = _messages
            .where((message) => message.isUser)
            .length;
        final shouldRateLimit =
            userInputCount == _rateLimitAtInput && !_skipRateLimitOnce;
        // 재시도 예외는 이번 요청에만 적용한다.
        _skipRateLimitOnce = false;

        if (shouldRateLimit) {
          _state = const ChatError(type: ChatErrorType.tooManyRequests);
          return;
        }

        // 준비된 답변을 순서대로 붙인다.
        final reply = _preparedReplies[_replyIndex % _preparedReplies.length];
        _messages.add(ChatMessage(text: reply, isUser: false));
        _replyIndex++;

        // 응답 도착도 같은 상태 변수로 표현한다.
        _state = ChatSuccess(reply: reply);
      });

      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    // reverse: true라서 offset 0이 화면 맨 아래(최신 메시지)다.
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩/오류 여부도 통합 상태에서 파생한다.
    final state = _state;
    final isLoading = state is ChatLoading;
    final error = state is ChatError ? state : null;

    return Scaffold(
      // TODO 5 — 키보드가 입력창을 가리지 않게
      // TIP: Scaffold의 resizeToAvoidBottomInset은 기본값이 true다.
      //      body를 SafeArea로 감싸 홈 인디케이터와 노치를 피한다.
      appBar: AppBar(title: const Text('AI Chat — 실습 1')),
      body: SafeArea(
        child: Column(
          children: [
            // ─────────────────────────────────────────────────────────
            // ✅ 할 일 1 — 완료된 부분
            //    ListView.builder + reverse: true
            //    · reverse:true면 index 0이 화면 맨 아래(최신)다.
            //    · 그래서 _messages[length - 1 - i]로 거꾸로 꺼낸다.
            // ─────────────────────────────────────────────────────────
            // ─────────────────────────────────────────────────────────
            // ✅ 할 일 4 — 완료된 부분
            //    빈 상태
            //    · ListView를 Stack으로 감싸 목록 위에 문구를 겹친다.
            //    · _messages가 비었을 때만 "무엇이든 물어보세요"를 보여 준다.
            //    · IgnorePointer로 문구가 목록 스크롤을 막지 않게 한다.
            // ─────────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // 로딩 중에는 점 3개를, 실패하면 오류 말풍선을 맨 아래에 그린다.
                    itemCount:
                        _messages.length +
                        ((isLoading || error != null) ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (isLoading && index == 0) {
                        return const _TypingBubble();
                      }
                      if (error != null && index == 0) {
                        return _ErrorBubble(error: error, onRetry: _retry);
                      }

                      final messageIndex =
                          _messages.length -
                          1 -
                          ((isLoading || error != null) ? index - 1 : index);
                      final message = _messages[messageIndex];
                      return _Bubble(message: message);
                    },
                  ),
                  if (_messages.isEmpty)
                    IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '무엇이든 물어보세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ─────────────────────────────────────────────────────────
            // ✅ 할 일 3 — 완료된 부분
            //    입력창 (TextField + 전송 버튼)
            //    · Enter(전송 액션)와 버튼 모두 _send()로 연결한다.
            //    · 빈 입력은 무시하고, 보낸 뒤에는 입력창을 비운다.
            //    · 입력창은 radius 24의 둥근(pill) 형태다.
            //    · _controller/_scrollController는 dispose()에서 정리한다.
            // ─────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '메시지를 입력하세요',
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    // 로딩 중에는 중복 전송을 막는다.
                    onPressed: isLoading ? null : _send,
                    tooltip: '전송',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────────────────────────────────────────────────
/// ✅ 할 일 2 — 완료된 부분
///    말풍선 2종 (사용자 오른쪽 / AI 왼쪽)
///    · Align으로 좌우를 나누고, 색은 colorScheme에서 꺼내 다크 모드에도 대응한다.
///    · 사용자/AI 모두 파란색(primaryContainer)으로 표시한다.
///    · maxWidth를 잡아 긴 글은 자동으로 줄바꿈된다.
///    · 말풍선 꼬리 쪽 모서리만 덜 둥글게 해 방향을 표현한다.
/// ───────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          // 사용자/AI 모두 같은 파란 계열을 쓴다.
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// ───────────────────────────────────────────────────────────────
/// 오류 말풍선 — 실패한 요청의 원인을 왼쪽에 표시한다.
/// · 오류 종류별 문구는 ChatErrorType.message에서 가져온다.
/// ───────────────────────────────────────────────────────────────
class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.error, required this.onRetry});

  final ChatError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('errorBubble'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    error.message,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 오류가 난 요청을 다시 보낼 수 있는 버튼.
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────────────────────────────────────────────────
/// 타이핑 점 — AI가 답변을 준비하는 동안 왼쪽 말풍선에 점 3개를 보여 준다.
/// · AnimationController로 점마다 위상을 어긋나게 해 순서대로 깜빡이게 한다.
/// ───────────────────────────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      key: const ValueKey('typingDots'),
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          // 답변 말풍선과 같은 파란 계열.
          color: colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  _buildDot(i, colorScheme.onPrimaryContainer),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDot(int index, Color color) {
    // index마다 위상을 어긋나게 해 물결처럼 깜빡인다.
    final pulse =
        (math.sin(_controller.value * 2 * math.pi - index * 0.9) + 1) / 2;

    return Transform.scale(
      scale: 0.8 + 0.2 * pulse,
      child: Opacity(
        opacity: 0.35 + 0.65 * pulse,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
