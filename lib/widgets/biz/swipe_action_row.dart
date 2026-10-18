import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 左滑操作项（钱迹式：左滑露出操作按钮，点击按钮执行动作）
class SwipeAction {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const SwipeAction({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
}

/// 全局「当前展开行」通知：同一时间只允许一行处于展开态，
/// 新行展开时自动收起旧行（与钱迹一致）。
final ValueNotifier<Object?> swipeActionOpenNotifier = ValueNotifier(null);

/// 左滑操作行：内容可向左拖动，露出右侧 [actions] 操作按钮。
/// 拖动超过一半吸附展开、否则收起；点击内容时若已展开则先收起。
/// 不做整行划出删除（区别于 Dismissible），操作必须点按钮触发。
class SwipeActionRow extends StatefulWidget {
  final Widget child;
  final List<SwipeAction> actions;
  final double actionWidth;

  const SwipeActionRow({
    super.key,
    required this.child,
    required this.actions,
    this.actionWidth = 72,
  });

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow> {
  double _offset = 0;
  bool _dragging = false;
  Object? _openKey;

  double get _maxOffset => widget.actions.length * widget.actionWidth;

  @override
  void initState() {
    super.initState();
    swipeActionOpenNotifier.addListener(_onGlobalOpenChanged);
  }

  @override
  void dispose() {
    swipeActionOpenNotifier.removeListener(_onGlobalOpenChanged);
    // 该行被回收时若还持有展开标记，清掉避免悬挂
    if (_isOpen && swipeActionOpenNotifier.value == _openKey) {
      swipeActionOpenNotifier.value = null;
    }
    super.dispose();
  }

  bool get _isOpen => _offset >= _maxOffset;

  void _onGlobalOpenChanged() {
    if (!mounted) return;
    // 别的行展开了 → 收起自己
    if (swipeActionOpenNotifier.value != _openKey && _offset > 0) {
      setState(() {
        _offset = 0;
        _openKey = null;
      });
    }
  }

  void _open() {
    _openKey = Object();
    swipeActionOpenNotifier.value = _openKey;
    setState(() => _offset = _maxOffset);
  }

  void _close() {
    if (swipeActionOpenNotifier.value == _openKey) {
      swipeActionOpenNotifier.value = null;
    }
    _openKey = null;
    setState(() => _offset = 0);
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // endToStart：向左滑 delta.dx 为负，位移取正累加
    final next = (_offset - details.delta.dx).clamp(0.0, _maxOffset).toDouble();
    if (next != _offset) setState(() => _offset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    // 快速轻扫（速度）或过半（位移）都视为展开意图
    final fling =
        details.primaryVelocity != null && details.primaryVelocity! < -200;
    if (_offset > _maxOffset / 2 || (fling && _offset > 8)) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // 底层操作按钮（右对齐，内容滑开后露出）。
        // 仅在拖动/展开时渲染：内容层透明，常驻渲染会直接透过内容显示。
        if (_offset > 0)
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final action in widget.actions)
                  SizedBox(
                    width: widget.actionWidth,
                    child: Material(
                      color: action.background,
                      child: InkWell(
                        onTap: () {
                          _close();
                          action.onTap();
                        },
                        child: Center(
                          child: Text(
                            action.label,
                            style: TextStyle(
                              color: action.foreground,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // 内容层：向左平移露出操作（拖动中即时跟手，松手后动画吸附）。
        // 必须带不透明背景：盖住底层按钮，滑动时按钮才呈「抽屉渐开」露出，
        // 否则透明内容直接透出按钮（无渐开效果）。
        AnimatedContainer(
          duration:
              _dragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(-_offset, 0, 0),
          child: Container(
            color: BeeTokens.surface(context),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _isOpen ? _close : null,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
