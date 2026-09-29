import 'package:flutter/material.dart';

import 'ai/ai_settings.dart';
import 'ble/guide_ble_session.dart';
import 'guide_controller.dart';

void main() => runApp(const GuideCompanionApp());

class GuideCompanionApp extends StatelessWidget {
  const GuideCompanionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Passport Guide',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff246b5f),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff4f0e6),
      useMaterial3: true,
    ),
    home: const GuideHomePage(),
  );
}

class GuideHomePage extends StatefulWidget {
  const GuideHomePage({super.key});

  @override
  State<GuideHomePage> createState() => _GuideHomePageState();
}

class _GuideHomePageState extends State<GuideHomePage> {
  late final GuideController controller;

  @override
  void initState() {
    super.initState();
    controller = GuideController()..addListener(_refresh);
    controller.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = controller.connection == GuideConnectionState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passport Guide'),
        actions: [
          IconButton(
            tooltip: 'AI settings',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              final value = await Navigator.of(context).push<AiSettings>(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(initial: controller.settings),
                ),
              );
              if (value != null) await controller.saveSettings(value);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xffd9eee8)
                    : const Color(0xfffff8df),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        connected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_searching,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        connected ? 'Passport connected' : 'Connect Passport',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(controller.status),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        controller.connection ==
                                GuideConnectionState.scanning ||
                            controller.connection ==
                                GuideConnectionState.connecting
                        ? null
                        : connected
                        ? controller.ble.disconnect
                        : controller.connect,
                    icon: Icon(connected ? Icons.link_off : Icons.bluetooth),
                    label: Text(connected ? 'Disconnect' : 'Scan and connect'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _StepCard(
              icon: Icons.mic,
              title: 'Hold OK and speak',
              body:
                  'Release OK to send. The phone uses its own network or VPN '
                  'for speech recognition and AI.',
            ),
            const SizedBox(height: 18),
            _ConversationCard(
              label: 'YOU',
              text: controller.transcript.isEmpty
                  ? 'Your transcript appears here.'
                  : controller.transcript,
            ),
            const SizedBox(height: 12),
            _ConversationCard(
              label: 'GUIDE',
              text: controller.answer.isEmpty
                  ? 'The guide response appears here and plays on Passport.'
                  : controller.answer,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(text),
      ],
    ),
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

  @override
  void initState() {
    super.initState();
    fields = {
      'Base URL': TextEditingController(text: widget.initial.baseUrl),
      'STT path': TextEditingController(text: widget.initial.sttPath),
      'Chat path': TextEditingController(text: widget.initial.chatPath),
      'TTS path': TextEditingController(text: widget.initial.ttsPath),
      'Chat model': TextEditingController(text: widget.initial.chatModel),
      'STT model': TextEditingController(text: widget.initial.sttModel),
      'TTS model': TextEditingController(text: widget.initial.ttsModel),
      'Voice': TextEditingController(text: widget.initial.voice),
      'API key': TextEditingController(text: widget.initial.apiKey),
    };
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
    appBar: AppBar(title: const Text('AI service settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Use OpenAI-compatible STT, chat, and TTS endpoints. '
          'The API key stays in the phone secure storage. '
          'TTS must return 16 kHz mono PCM WAV.',
        ),
        const SizedBox(height: 18),
        for (final entry in fields.entries) ...[
          TextField(
            controller: entry.value,
            obscureText: entry.key == 'API key',
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
              baseUrl: fields['Base URL']!.text.trim(),
              sttPath: fields['STT path']!.text.trim(),
              chatPath: fields['Chat path']!.text.trim(),
              ttsPath: fields['TTS path']!.text.trim(),
              chatModel: fields['Chat model']!.text.trim(),
              sttModel: fields['STT model']!.text.trim(),
              ttsModel: fields['TTS model']!.text.trim(),
              voice: fields['Voice']!.text.trim(),
              apiKey: fields['API key']!.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
