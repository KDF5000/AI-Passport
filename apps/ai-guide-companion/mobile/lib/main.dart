import 'dart:async';

import 'package:flutter/material.dart';

import 'ai/ai_settings.dart';
import 'ble/guide_ble_session.dart';
import 'guide_controller.dart';
import 'trip/trip_plan.dart';

void main() => runApp(const GuideCompanionApp());

abstract final class GuideColors {
  static const ink = Color(0xff1f2929);
  static const paper = Color(0xfff6f0e2);
  static const paperLight = Color(0xfffffaf0);
  static const green = Color(0xff214f47);
  static const mint = Color(0xffdcebe4);
  static const gold = Color(0xffe7b757);
  static const red = Color(0xffb95c44);
  static const muted = Color(0xff68716d);
}

class GuideCompanionApp extends StatelessWidget {
  const GuideCompanionApp({super.key, this.controller});

  final GuideController? controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '随行',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: GuideColors.green,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: GuideColors.paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: GuideColors.green,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: GuideColors.paperLight,
        margin: EdgeInsets.zero,
      ),
      useMaterial3: true,
    ),
    home: GuideHomePage(controller: controller),
  );
}

class GuideHomePage extends StatefulWidget {
  const GuideHomePage({super.key, this.controller});
  final GuideController? controller;

  @override
  State<GuideHomePage> createState() => _GuideHomePageState();
}

class _GuideHomePageState extends State<GuideHomePage> {
  late final GuideController controller;
  late final bool ownsController;
  int section = 0;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ?? GuideController();
    controller.addListener(_refresh);
    controller.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (ownsController) controller.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final value = await Navigator.of(context).push<AiSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initial: controller.settings),
      ),
    );
    if (value != null) await controller.saveSettings(value);
  }

  Future<void> _createTrip() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TripBuilderPage(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = controller.hasTrip
        ? const ['行程票', '问导游', '离线包']
        : const ['开始', '问导游', '设置'];
    final icons = controller.hasTrip
        ? const [
            Icons.confirmation_number_outlined,
            Icons.auto_awesome,
            Icons.download_outlined,
          ]
        : const [
            Icons.add_location_alt_outlined,
            Icons.auto_awesome,
            Icons.tune,
          ];
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRAVEL PASS',
              style: TextStyle(fontSize: 10, letterSpacing: 1.4),
            ),
            Text(
              '随行',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'AI 服务设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: section,
          children: [
            controller.hasTrip
                ? TripTicketView(
                    controller: controller,
                    onCreateTrip: _createTrip,
                  )
                : EmptyTripView(onCreateTrip: _createTrip),
            ConversationView(controller: controller),
            controller.hasTrip
                ? OfflinePackView(controller: controller)
                : SetupView(
                    controller: controller,
                    onOpenSettings: _openSettings,
                  ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: section,
        onDestinationSelected: (value) => setState(() => section = value),
        backgroundColor: GuideColors.paperLight,
        indicatorColor: GuideColors.green,
        destinations: [
          for (var index = 0; index < labels.length; index++)
            NavigationDestination(
              icon: Icon(icons[index]),
              selectedIcon: Icon(icons[index], color: Colors.white),
              label: labels[index],
            ),
        ],
      ),
    );
  }
}

class EmptyTripView extends StatelessWidget {
  const EmptyTripView({super.key, required this.onCreateTrip});
  final VoidCallback onCreateTrip;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
    children: [
      const Text(
        '先把想去的地方\n变成一张行程票',
        style: TextStyle(
          color: GuideColors.ink,
          fontSize: 31,
          height: 1.12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '输入目的地和确定场次，AI 生成路线与完整讲解。你审核后才会保存到手机。',
        style: TextStyle(color: GuideColors.muted, height: 1.55),
      ),
      const SizedBox(height: 26),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          backgroundColor: GuideColors.red,
        ),
        onPressed: onCreateTrip,
        icon: const Icon(Icons.add),
        label: const Text('创建新行程'),
      ),
      const SizedBox(height: 12),
      const Text(
        '创建时联网一次；保存后的路线、进度和已缓存讲解均可离线使用',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: GuideColors.muted),
      ),
      const SizedBox(height: 34),
      const _FlowRow(
        number: '1',
        title: '告诉 AI 去哪里',
        body: '目的地、日期、到离时间和同行情况。',
      ),
      const _FlowRow(
        number: '2',
        title: '锁定真实场次',
        body: '门票、演出和预约由你确认，AI 不猜时间。',
      ),
      const _FlowRow(
        number: '3',
        title: '生成并审核草案',
        body: '路线、摘要、讲解稿和待核对事项一次生成。',
      ),
      const _FlowRow(
        number: '4',
        title: '保存后离线游玩',
        body: '按需缓存语音，再将路线同步到 Passport。',
      ),
    ],
  );
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xffe4ddce),
          foregroundColor: GuideColors.ink,
          child: Text(number, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  color: GuideColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class TripTicketView extends StatelessWidget {
  const TripTicketView({
    super.key,
    required this.controller,
    required this.onCreateTrip,
  });
  final GuideController controller;
  final VoidCallback onCreateTrip;

  @override
  Widget build(BuildContext context) {
    final trip = controller.trip;
    final stop = controller.currentStop!;
    final connected = controller.connection == GuideConnectionState.connected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: GuideColors.green,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${controller.completedStopCount} / ${trip.stops.length} 已完成',
                      style: const TextStyle(
                        color: Color(0xffd7e4df),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      trip.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (trip.date.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        trip.date,
                        style: const TextStyle(color: Color(0xffd7e4df)),
                      ),
                    ],
                  ],
                ),
              ),
              ActionChip(
                avatar: Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  size: 17,
                ),
                label: Text(connected ? '已连接' : '连接'),
                onPressed: connected
                    ? controller.ble.disconnect
                    : controller.connect,
                backgroundColor: connected
                    ? const Color(0xffa9d1c2)
                    : const Color(0xff376a61),
                labelStyle: TextStyle(
                  color: connected ? GuideColors.ink : Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.time,
                            style: const TextStyle(
                              color: GuideColors.red,
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            stop.name,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '第 ${trip.currentIndex + 1} 站 · ${stop.durationMinutes} 分钟',
                            style: const TextStyle(color: GuideColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: stop.completed ? '取消完成' : '标记完成',
                      onPressed: () => controller.setStopCompleted(
                        trip.currentIndex,
                        !stop.completed,
                      ),
                      icon: Icon(
                        stop.completed ? Icons.check_circle : Icons.check,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 30),
                Text(stop.summary, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: GuideColors.gold,
                          foregroundColor: GuideColors.ink,
                        ),
                        onPressed: controller.busy
                            ? null
                            : () => controller.playOfflineGuide(),
                        icon: const Icon(Icons.headphones),
                        label: const Text('离线讲解'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (trip.verificationItems.isNotEmpty) ...[
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff3e4c5),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fact_check_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '出发前核对：${trip.verificationItems.first}',
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '今天的路线',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            TextButton(onPressed: onCreateTrip, child: const Text('重新规划')),
          ],
        ),
        for (final entry in trip.stops.indexed)
          _RouteTile(
            index: entry.$1,
            stop: entry.$2,
            selected: entry.$1 == trip.currentIndex,
            onTap: () => controller.selectStop(entry.$1),
          ),
        const SizedBox(height: 12),
        Text(
          controller.tripStatus,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: GuideColors.muted),
        ),
      ],
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.index,
    required this.stop,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final TripStop stop;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      tileColor: selected ? GuideColors.mint : Colors.transparent,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: stop.completed
            ? GuideColors.green
            : selected
            ? GuideColors.gold
            : const Color(0xffe5dece),
        foregroundColor: stop.completed ? Colors.white : GuideColors.ink,
        child: stop.completed
            ? const Icon(Icons.check, size: 17)
            : Text('${index + 1}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(stop.name),
      subtitle: Text(
        '${stop.time} · ${stop.durationMinutes} 分钟'
        '${stop.fixed ? ' · 已确认场次' : ''}',
      ),
      trailing: Icon(selected ? Icons.navigation : Icons.chevron_right),
    ),
  );
}

class ConversationView extends StatelessWidget {
  const ConversationView({super.key, required this.controller});
  final GuideController controller;

  @override
  Widget build(BuildContext context) {
    final stop = controller.currentStop;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (stop != null)
          Chip(
            avatar: const Icon(Icons.location_on_outlined, size: 18),
            label: Text('上下文：${stop.name}'),
            backgroundColor: GuideColors.mint,
          ),
        const SizedBox(height: 15),
        const Text(
          '现在想了解\n什么？',
          style: TextStyle(
            fontSize: 31,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          stop == null ? '还没有行程，也可以先问一个普通旅行问题。' : '当前站点、简介和已完成行程会随问题一起发送。',
          style: const TextStyle(color: GuideColors.muted, height: 1.5),
        ),
        if (controller.transcript.isNotEmpty) ...[
          const SizedBox(height: 24),
          _MessageBubble(text: controller.transcript, user: true),
        ],
        if (controller.answer.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MessageBubble(text: controller.answer, user: false),
        ],
        const SizedBox(height: 28),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => controller.startPhoneConversation(),
          onTapUp: (_) => controller.stopAndProcessPhoneConversation(),
          onTapCancel: controller.stopAndProcessPhoneConversation,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            decoration: BoxDecoration(
              color: controller.phoneRecording
                  ? GuideColors.green
                  : GuideColors.red,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  controller.phoneRecording ? Icons.graphic_eq : Icons.mic,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Text(
                  controller.phoneRecording ? '正在听 · 松开发送' : '按住问 AI 导游',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          controller.voiceStatus,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: GuideColors.muted),
        ),
        if (controller.busy && controller.canCancel)
          TextButton.icon(
            onPressed: controller.cancelConversation,
            icon: const Icon(Icons.close),
            label: const Text('取消等待'),
          ),
        if (controller.retryAvailable)
          TextButton.icon(
            onPressed: controller.retryLastConversation,
            icon: const Icon(Icons.refresh),
            label: const Text('不重新录音，直接重试'),
          ),
        if (controller.voiceError != null)
          Text(
            controller.voiceError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.user});
  final String text;
  final bool user;

  @override
  Widget build(BuildContext context) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: user ? const Color(0xffd3e4ef) : GuideColors.paperLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: const TextStyle(height: 1.5)),
    ),
  );
}

class OfflinePackView extends StatelessWidget {
  const OfflinePackView({super.key, required this.controller});
  final GuideController controller;

  @override
  Widget build(BuildContext context) {
    final ready = controller.cachedGuideCount == controller.trip.stops.length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '先下载故事\n再轻装出发',
          style: TextStyle(
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '路线和进度始终保存在手机；缓存讲解后，重复播放不再调用语音服务。',
          style: TextStyle(color: GuideColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.offline_pin_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.trip.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${controller.cachedGuideCount}/${controller.trip.stops.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: controller.trip.stops.isEmpty
                      ? 0
                      : controller.cachedGuideCount /
                            controller.trip.stops.length,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: GuideColors.green,
                  backgroundColor: const Color(0xffe5dece),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: GuideColors.green,
                  ),
                  onPressed:
                      ready ||
                          controller.preparingOfflineGuides ||
                          controller.busy
                      ? null
                      : controller.prepareOfflineGuides,
                  icon: controller.preparingOfflineGuides
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(ready ? '全部讲解已就绪' : '缓存剩余讲解'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          controller.tripStatus,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GuideColors.muted),
        ),
      ],
    );
  }
}

class SetupView extends StatelessWidget {
  const SetupView({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });
  final GuideController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '出发前设置',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      const Text(
        '先配置 AI 与语音服务。密钥只保存在手机的系统安全存储中，不会发送到 Passport。',
        style: TextStyle(color: GuideColors.muted, height: 1.5),
      ),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: onOpenSettings,
        icon: const Icon(Icons.key),
        label: const Text('配置 AI 服务'),
      ),
    ],
  );
}

class TripBuilderPage extends StatefulWidget {
  const TripBuilderPage({super.key, required this.controller});
  final GuideController controller;

  @override
  State<TripBuilderPage> createState() => _TripBuilderPageState();
}

class _TripBuilderPageState extends State<TripBuilderPage> {
  int step = 0;
  final destination = TextEditingController();
  final date = TextEditingController(text: _today());
  final arrival = TextEditingController(text: '10:00');
  final departure = TextEditingController(text: '19:00');
  final notes = TextEditingController();
  TripPace pace = TripPace.balanced;
  String companion = '成人';
  final events = <ConfirmedEvent>[];
  TripPlan? draft;

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    destination.dispose();
    date.dispose();
    arrival.dispose();
    departure.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _addEvent() async {
    final name = TextEditingController();
    final time = TextEditingController();
    final value = await showDialog<ConfirmedEvent>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加确定场次'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '演出或预约名称'),
            ),
            TextField(
              controller: time,
              decoration: const InputDecoration(labelText: '时间，例如 15:30'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty ||
                  !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                      .hasMatch(time.text.trim())) {
                return;
              }
              Navigator.pop(
                context,
                ConfirmedEvent(name: name.text.trim(), time: time.text.trim()),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    name.dispose();
    time.dispose();
    if (value != null) setState(() => events.add(value));
  }

  TripRequest _request() => TripRequest(
    destination: destination.text.trim(),
    date: date.text.trim(),
    arrivalTime: arrival.text.trim(),
    departureTime: departure.text.trim(),
    pace: pace,
    companion: companion,
    confirmedEvents: events,
    notes: notes.text.trim(),
  );

  Future<void> _generate() async {
    if (destination.text.trim().isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.text.trim()) ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(arrival.text.trim()) ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
            .hasMatch(departure.text.trim())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请检查目的地、日期和时间格式')));
      return;
    }
    setState(() => step = 2);
    final value = await widget.controller.generateTripDraft(_request());
    if (!mounted) return;
    if (value == null) {
      setState(() => step = 1);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.controller.tripStatus)));
      return;
    }
    setState(() {
      draft = value;
      step = 3;
    });
  }

  Future<void> _save() async {
    final value = draft;
    if (value == null) return;
    await widget.controller.saveTripDraft(value);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('新建行程'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(8),
        child: LinearProgressIndicator(
          value: switch (step) {
            0 => .25,
            1 => .5,
            2 => .75,
            _ => 1,
          },
          minHeight: 5,
          color: GuideColors.gold,
          backgroundColor: Colors.white24,
        ),
      ),
    ),
    body: SafeArea(
      child: switch (step) {
        0 => _BasicsStep(
          destination: destination,
          date: date,
          arrival: arrival,
          departure: departure,
          onNext: () => setState(() => step = 1),
        ),
        1 => _ConstraintsStep(
          events: events,
          pace: pace,
          companion: companion,
          notes: notes,
          onAddEvent: _addEvent,
          onDeleteEvent: (index) => setState(() => events.removeAt(index)),
          onPace: (value) => setState(() => pace = value),
          onCompanion: (value) => setState(() => companion = value),
          onBack: () => setState(() => step = 0),
          onGenerate: _generate,
        ),
        2 => _GeneratingStep(onCancel: widget.controller.cancelTripGeneration),
        _ => _ReviewStep(
          plan: draft!,
          onChanged: (value) => setState(() => draft = value),
          onBack: () => setState(() => step = 1),
          onSave: _save,
        ),
      },
    ),
  );
}

class _BasicsStep extends StatelessWidget {
  const _BasicsStep({
    required this.destination,
    required this.date,
    required this.arrival,
    required this.departure,
    required this.onNext,
  });
  final TextEditingController destination;
  final TextEditingController date;
  final TextEditingController arrival;
  final TextEditingController departure;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '今天去哪里？',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'AI 会根据目的地生成景点资料、路线与讲解，不依赖预置资源包。',
        style: TextStyle(color: GuideColors.muted, height: 1.5),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: destination,
        decoration: const InputDecoration(
          labelText: '目的地',
          hintText: '例如：只有河南 · 戏剧幻城',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: date,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(
          labelText: '游玩日期',
          hintText: 'YYYY-MM-DD',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: arrival,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: '到达',
                hintText: '10:00',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: departure,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: '离开',
                hintText: '19:00',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: GuideColors.red,
        ),
        onPressed: onNext,
        child: const Text('下一步 · 添加确定场次'),
      ),
    ],
  );
}

class _ConstraintsStep extends StatelessWidget {
  const _ConstraintsStep({
    required this.events,
    required this.pace,
    required this.companion,
    required this.notes,
    required this.onAddEvent,
    required this.onDeleteEvent,
    required this.onPace,
    required this.onCompanion,
    required this.onBack,
    required this.onGenerate,
  });
  final List<ConfirmedEvent> events;
  final TripPace pace;
  final String companion;
  final TextEditingController notes;
  final VoidCallback onAddEvent;
  final ValueChanged<int> onDeleteEvent;
  final ValueChanged<TripPace> onPace;
  final ValueChanged<String> onCompanion;
  final VoidCallback onBack;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '哪些时间不能动？',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '把门票、演出或预约时间告诉 AI。它们会作为硬约束原样保留。',
        style: TextStyle(color: GuideColors.muted, height: 1.5),
      ),
      const SizedBox(height: 17),
      for (final entry in events.indexed)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.lock_clock),
            title: Text(entry.$2.name),
            subtitle: const Text('用户确认 · AI 不得修改'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.$2.time,
                  style: const TextStyle(
                    color: GuideColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: '删除场次',
                  onPressed: () => onDeleteEvent(entry.$1),
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: onAddEvent,
        icon: const Icon(Icons.add),
        label: const Text('添加确定场次'),
      ),
      const SizedBox(height: 20),
      const Text('游玩节奏', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final value in TripPace.values)
            ChoiceChip(
              label: Text(value.label),
              selected: pace == value,
              onSelected: (_) => onPace(value),
            ),
        ],
      ),
      const SizedBox(height: 17),
      const Text('同行情况', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final value in const ['成人', '带儿童', '少走路'])
            ChoiceChip(
              label: Text(value),
              selected: companion == value,
              onSelected: (_) => onCompanion(value),
            ),
        ],
      ),
      const SizedBox(height: 17),
      TextField(
        controller: notes,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: '补充偏好（可选）',
          hintText: '例如想留出午餐时间、对建筑更感兴趣',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GuideColors.mint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          '下一步只调用一次 AI：同时生成候选站点、路线、摘要、完整讲解稿和待核对事项。',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      const SizedBox(height: 17),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: onBack, child: const Text('上一步')),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: GuideColors.red),
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成路线草案'),
            ),
          ),
        ],
      ),
    ],
  );
}

class _GeneratingStep extends StatefulWidget {
  const _GeneratingStep({required this.onCancel});
  final VoidCallback onCancel;

  @override
  State<_GeneratingStep> createState() => _GeneratingStepState();
}

class _GeneratingStepState extends State<_GeneratingStep> {
  Timer? timer;
  int elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => elapsedSeconds += 1);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String get detail {
    if (elapsedSeconds >= 90) {
      return '正在生成完整讲解稿，服务响应较慢，但仍在继续';
    }
    if (elapsedSeconds >= 30) {
      return '正在补充各站讲解与现场提示';
    }
    return '先固定场次，再安排游览、休息与讲解';
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: GuideColors.green),
          const SizedBox(height: 25),
          const Text(
            '正在编排路线',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 9),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GuideColors.muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            '已等待 ${elapsedSeconds}s',
            style: const TextStyle(
              color: GuideColors.muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: widget.onCancel, child: const Text('取消生成')),
        ],
      ),
    ),
  );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.plan,
    required this.onChanged,
    required this.onBack,
    required this.onSave,
  });
  final TripPlan plan;
  final ValueChanged<TripPlan> onChanged;
  final VoidCallback onBack;
  final VoidCallback onSave;

  void _move(int from, int delta) {
    final target = from + delta;
    if (target < 0 || target >= plan.stops.length) return;
    final stops = [...plan.stops];
    final item = stops.removeAt(from);
    stops.insert(target, item);
    onChanged(plan.copyWith(stops: stops));
  }

  void _remove(int index) {
    final stops = [...plan.stops]..removeAt(index);
    onChanged(plan.copyWith(stops: stops));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '这只是草案\n由你定稿',
        style: TextStyle(
          fontSize: 28,
          height: 1.12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        plan.summary,
        style: const TextStyle(color: GuideColors.muted, height: 1.5),
      ),
      if (plan.verificationItems.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xfff3e4c5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '仍需核对\n${plan.verificationItems.map((item) => '• $item').join('\n')}',
            style: const TextStyle(height: 1.5),
          ),
        ),
      ],
      const SizedBox(height: 17),
      for (final entry in plan.stops.indexed)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: SizedBox(
              width: 42,
              child: Text(
                entry.$2.time,
                style: const TextStyle(
                  color: GuideColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(entry.$2.name),
            subtitle: Text(
              '${entry.$2.durationMinutes} 分钟 · '
              '${entry.$2.fixed ? "已确认场次" : "AI 建议"}',
            ),
            trailing: entry.$2.fixed
                ? const Icon(Icons.lock_outline)
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'up') _move(entry.$1, -1);
                      if (value == 'down') _move(entry.$1, 1);
                      if (value == 'remove') _remove(entry.$1);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'up', child: Text('向前移动')),
                      PopupMenuItem(value: 'down', child: Text('向后移动')),
                      PopupMenuItem(value: 'remove', child: Text('删除站点')),
                    ],
                  ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.$2.summary),
                    const SizedBox(height: 10),
                    Text(
                      entry.$2.guideScript,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GuideColors.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GuideColors.mint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          '保存后路线会写入手机。语音不会自动生成，可在“离线包”中主动缓存，避免无谓调用 TTS。',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      const SizedBox(height: 17),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: onBack, child: const Text('调整条件')),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: GuideColors.red),
              onPressed: plan.stops.length < 2 ? null : onSave,
              icon: const Icon(Icons.save_outlined),
              label: const Text('确认并保存'),
            ),
          ),
        ],
      ),
    ],
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial});
  final AiSettings initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Map<String, TextEditingController> fields;
  late final Set<String> secretFields;

  @override
  void initState() {
    super.initState();
    fields = {
      '方舟模型 / Endpoint': TextEditingController(text: widget.initial.arkModel),
      '方舟 API Key': TextEditingController(text: widget.initial.arkApiKey),
      'Speech Appkey': TextEditingController(text: widget.initial.speechAppId),
      'Speech AK': TextEditingController(text: widget.initial.speechAccessKey),
      'Speech SK': TextEditingController(text: widget.initial.speechSecretKey),
    };
    secretFields = {'方舟 API Key', 'Speech AK', 'Speech SK'};
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 服务设置')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'CN 区域的语音端点和默认音色已内置。密钥只保存在本机安全存储。',
          style: TextStyle(color: GuideColors.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        for (final entry in fields.entries) ...[
          TextField(
            controller: entry.value,
            obscureText: secretFields.contains(entry.key),
            autocorrect: false,
            decoration: InputDecoration(
              labelText: entry.key,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            AiSettings(
              arkModel: fields['方舟模型 / Endpoint']!.text.trim(),
              arkApiKey: fields['方舟 API Key']!.text.trim(),
              speechAppId: fields['Speech Appkey']!.text.trim(),
              speechAccessKey: fields['Speech AK']!.text.trim(),
              speechSecretKey: fields['Speech SK']!.text.trim(),
            ),
          ),
          child: const Text('保存设置'),
        ),
      ],
    ),
  );
}
