import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ai/ai_gateway.dart';
import 'ai/ai_settings.dart';
import 'ai/sentence_chunker.dart';
import 'audio/guide_audio_cache.dart';
import 'audio/mobile_voice.dart';
import 'audio/timed_text_reveal.dart';
import 'audio/wav_codec.dart';
import 'ble/guide_ble_session.dart';
import 'platform/background_execution.dart';
import 'protocol/guide_protocol.dart';
import 'protocol/ima_adpcm.dart';
import 'protocol/passport_operation.dart';
import 'protocol/trip_protocol.dart';
import 'trip/trip_plan.dart';
import 'trip/trip_planner.dart';

final class GuideController extends ChangeNotifier {
  GuideController({
    AiSettingsStore? store,
    TripPlanStore? tripStore,
    GuideAudioCache? audioCache,
    BackgroundExecution? backgroundExecution,
  }) : store = store ?? AiSettingsStore(),
       tripStore = tripStore ?? TripPlanStore(),
       audioCache = audioCache ?? GuideAudioCache(),
       backgroundExecution = backgroundExecution ?? IosBackgroundExecution() {
    ble = GuideBleSession(onPacket: _onPacket, onState: _onBleState);
    mobileVoice = MobileVoice();
  }

  final AiSettingsStore store;
  final TripPlanStore tripStore;
  final GuideAudioCache audioCache;
  final BackgroundExecution backgroundExecution;
  final TripPlanner tripPlanner = const TripPlanner();
  late final GuideBleSession ble;
  late final MobileVoice mobileVoice;
  AiSettings settings = const AiSettings();
  TripPlan trip = TripPlan.empty;
  List<TripPlan> trips = const [];
  int selectedTripIndex = 0;
  TripPlan? tripDraft;
  GuideConnectionState connection = GuideConnectionState.disconnected;
  String status = 'Load settings, then connect your Passport';
  String tripStatus = 'Offline route is ready';
  String voiceStatus = 'Ready to talk';
  String? voiceError;
  String transcript = '';
  String answer = '';
  bool busy = false;
  bool phoneRecording = false;
  bool slowResponse = false;
  bool retryAvailable = false;
  bool preparingOfflineGuides = false;
  int cachedGuideCount = 0;
  final List<Int16List> _recording = [];
  final List<Map<String, String>> _history = [];
  int _sampleRate = 16000;
  int _operationId = 0;
  final PassportOperationState _passportOperation = PassportOperationState();
  Timer? _slowResponseTimer;
  AiGateway? _activeGateway;
  bool _tripGenerationCancelled = false;
  bool _disposed = false;
  Future<bool>? _passportBackgroundLease;

  bool get canCancel => busy && !phoneRecording;
  bool get hasTrip => !trip.isEmpty;
  TripStop? get currentStop =>
      trip.isEmpty ? null : trip.stops[trip.currentIndex];
  int get completedStopCount =>
      trip.stops.where((stop) => stop.completed).length;

  Future<void> load() async {
    try {
      await ble.initialize();
    } catch (error) {
      debugPrint('BLE initialization unavailable: $error');
    }
    final values = await Future.wait<Object>([
      store.load(),
      tripStore.loadLibrary(),
    ]);
    settings = values[0] as AiSettings;
    final library = values[1] as TripLibrary;
    trips = library.trips;
    selectedTripIndex = library.selectedIndex;
    trip = library.selectedTrip;
    await _refreshCacheCount();
    notifyListeners();
    try {
      await ble.restoreConnection();
    } catch (error) {
      // Bluetooth may be unavailable or denied during launch. Manual connect
      // remains available and reports its own actionable error.
      debugPrint('BLE state restoration unavailable: $error');
    }
  }

  Future<TripPlan?> generateTripDraft(TripRequest request) async {
    if (busy) return null;
    busy = true;
    _tripGenerationCancelled = false;
    tripStatus = '正在生成路线草案…';
    notifyListeners();
    final gateway = AiGateway(settings);
    _activeGateway = gateway;
    try {
      tripDraft = await tripPlanner.generate(gateway, request);
      tripStatus = '草案已生成，请逐项审核';
      return tripDraft;
    } on TripPlanningConflict catch (error) {
      tripStatus = '固定场次存在冲突：$error';
      tripDraft = null;
      return null;
    } on TimeoutException {
      tripStatus = '路线内容较多，AI 等待超时。请检查网络后重试，已填写内容不会丢失。';
      tripDraft = null;
      return null;
    } catch (error) {
      tripStatus = _tripGenerationCancelled
          ? '已取消生成，填写的内容仍然保留'
          : '路线生成失败：$error';
      tripDraft = null;
      return null;
    } finally {
      gateway.close();
      _activeGateway = null;
      busy = false;
      notifyListeners();
    }
  }

  void cancelTripGeneration() {
    if (!busy || _activeGateway == null) return;
    _tripGenerationCancelled = true;
    tripStatus = '正在取消…';
    _activeGateway?.close();
    notifyListeners();
  }

  Future<void> saveTripDraft(TripPlan value) async {
    trip = value.copyWith(currentIndex: 0);
    trips = [...trips, trip];
    selectedTripIndex = trips.length - 1;
    tripDraft = null;
    await _saveTripLibrary();
    await _refreshCacheCount();
    tripStatus = '路线已保存到手机';
    notifyListeners();
    if (connection == GuideConnectionState.connected) await syncTrip();
  }

  Future<void> selectTrip(int index) async {
    if (index < 0 || index >= trips.length || index == selectedTripIndex) {
      return;
    }
    selectedTripIndex = index;
    trip = trips[index];
    await _saveTripLibrary();
    await _refreshCacheCount();
    tripStatus = '已切换到「${trip.title}」';
    notifyListeners();
    if (connection == GuideConnectionState.connected) await syncTrip();
  }

  Future<void> _saveTripLibrary() async {
    if (trips.isNotEmpty && selectedTripIndex < trips.length) {
      final updated = [...trips];
      updated[selectedTripIndex] = trip;
      trips = updated;
    }
    await tripStore.saveLibrary(
      TripLibrary(trips: trips, selectedIndex: selectedTripIndex),
    );
  }

  Future<void> saveSettings(AiSettings value) async {
    settings = value;
    await store.save(value);
    status = 'Settings saved';
    notifyListeners();
  }

  Future<void> connect() async {
    try {
      await ble.connect();
    } catch (error) {
      status = 'Bluetooth error: $error';
      connection = GuideConnectionState.disconnected;
      notifyListeners();
      await ble.disconnect();
    }
  }

  void _onBleState(GuideConnectionState value, String detail) {
    if (_disposed) return;
    connection = value;
    status = detail;
    notifyListeners();
    if (value == GuideConnectionState.connected) {
      unawaited(syncTrip());
    } else if (value == GuideConnectionState.disconnected) {
      unawaited(_endPassportBackgroundLease());
    }
  }

  void _onPacket(Uint8List packet) {
    if (_disposed || packet.isEmpty) return;
    switch (packet.first) {
      case GuidePacketType.recordingStart:
        if (packet.length >= 3) {
          _sampleRate = packet[1] | (packet[2] << 8);
        }
        _recording.clear();
        transcript = '';
        answer = '';
        status = 'Listening…';
        _passportBackgroundLease ??= backgroundExecution.begin(
          'Passport voice question',
        );
        notifyListeners();
      case GuidePacketType.recordingAudio:
        final decoded = ImaAdpcm.decode(Uint8List.sublistView(packet, 1));
        if (decoded.isNotEmpty) {
          _recording.add(
            Int16List.sublistView(decoded, 0, decoded.length.clamp(0, 320)),
          );
        }
      case GuidePacketType.recordingEnd:
        if (_recording.isEmpty) {
          unawaited(_endPassportBackgroundLease());
        } else {
          unawaited(_processRecording());
        }
      case GuidePacketType.tripSelect:
        if (packet.length >= 2) {
          unawaited(selectStop(packet[1], sync: false));
        }
      case GuidePacketType.tripCompletion:
        if (packet.length >= 3) {
          unawaited(setStopCompleted(packet[1], packet[2] != 0, sync: false));
        }
      case GuidePacketType.tripPlayRequest:
        if (packet.length >= 2) {
          unawaited(playOfflineGuide(packet[1]));
        }
      case GuidePacketType.tripPlayCancel:
        _cancelPassportOperation();
      case GuidePacketType.error:
        status = String.fromCharCodes(packet.skip(1));
        notifyListeners();
    }
  }

  Future<void> syncTrip() async {
    if (connection != GuideConnectionState.connected || trip.stops.isEmpty) {
      return;
    }
    try {
      await ble.send(
        GuidePacketType.tripBegin,
        TripProtocol.begin(trip).sublist(1),
      );
      await ble.sendText(GuidePacketType.tripTitle, trip.title);
      for (var index = 0; index < trip.stops.length; index++) {
        final value = TripProtocol.stop(index, trip.stops[index]);
        await ble.send(value.first, value.sublist(1));
      }
      await ble.send(GuidePacketType.tripCommit);
      tripStatus = 'Route synced to Passport';
    } catch (error) {
      tripStatus = 'Route sync failed: $error';
    }
    notifyListeners();
  }

  Future<void> selectStop(int index, {bool sync = true}) async {
    if (index < 0 || index >= trip.stops.length) return;
    trip = trip.copyWith(currentIndex: index);
    await _saveTripLibrary();
    tripStatus = '${trip.stops[index].name} selected';
    notifyListeners();
    if (sync) await syncTrip();
  }

  Future<void> setStopCompleted(
    int index,
    bool completed, {
    bool sync = true,
  }) async {
    if (index < 0 || index >= trip.stops.length) return;
    final stops = [...trip.stops];
    stops[index] = stops[index].copyWith(completed: completed);
    trip = trip.copyWith(stops: stops, currentIndex: index);
    await _saveTripLibrary();
    tripStatus = completed ? 'Stop completed' : 'Stop reopened';
    notifyListeners();
    if (sync) await syncTrip();
  }

  String _guideCacheKey(TripStop stop) =>
      '${settings.ttsVoice}\n${stop.name}\n'
      '${stop.guideScript.isEmpty ? stop.summary : stop.guideScript}';

  Future<void> _refreshCacheCount() async {
    var count = 0;
    for (final stop in trip.stops) {
      if (await audioCache.contains(_guideCacheKey(stop))) count += 1;
    }
    cachedGuideCount = count;
  }

  Future<void> prepareOfflineGuides() async {
    if (preparingOfflineGuides || busy) return;
    preparingOfflineGuides = true;
    tripStatus = 'Preparing offline guides…';
    notifyListeners();
    final gateway = AiGateway(settings);
    try {
      for (var index = 0; index < trip.stops.length; index++) {
        final stop = trip.stops[index];
        final key = _guideCacheKey(stop);
        if (await audioCache.contains(key)) continue;
        tripStatus = 'Caching guide ${index + 1}/${trip.stops.length}';
        notifyListeners();
        final audio = await gateway.synthesize(stop.guideNarration);
        await audioCache.write(key, audio);
      }
      await _refreshCacheCount();
      tripStatus = 'All guides available offline';
    } catch (error) {
      await _refreshCacheCount();
      tripStatus = 'Cached $cachedGuideCount/${trip.stops.length}: $error';
    } finally {
      gateway.close();
      preparingOfflineGuides = false;
      notifyListeners();
    }
  }

  Future<void> playOfflineGuide([int? requestedIndex]) async {
    if (busy) {
      tripStatus = 'Another task is running · try OK again shortly';
      notifyListeners();
      if (connection == GuideConnectionState.connected) {
        try {
          await ble.sendText(
            GuidePacketType.error,
            'Phone is busy. Press OK again shortly.',
          );
        } catch (_) {}
      }
      return;
    }
    final index = requestedIndex ?? trip.currentIndex;
    if (index < 0 || index >= trip.stops.length) {
      tripStatus = 'Route is not ready · sync it from the phone';
      notifyListeners();
      if (connection == GuideConnectionState.connected) {
        try {
          await ble.sendText(
            GuidePacketType.error,
            'Route is not ready. Sync it from the phone.',
          );
        } catch (_) {}
      }
      return;
    }
    if (index != trip.currentIndex) await selectStop(index, sync: false);
    final stop = trip.stops[index];
    final audio = await audioCache.read(_guideCacheKey(stop));
    if (audio == null) {
      tripStatus = 'Guide not cached · prepare it on the phone first';
      notifyListeners();
      if (connection == GuideConnectionState.connected) {
        try {
          await ble.sendText(
            GuidePacketType.error,
            'Guide not cached. Prepare offline guides on the phone.',
          );
        } catch (_) {}
      }
      return;
    }
    busy = true;
    final operation = ++_operationId;
    final playOnPassport = connection == GuideConnectionState.connected;
    if (playOnPassport) {
      _passportOperation.start(
        operation,
        PassportOperationKind.offlinePlayback,
      );
    }
    tripStatus = playOnPassport
        ? '正在 Passport 播放缓存讲解 · 未使用网络'
        : '正在手机播放缓存讲解 · 未使用网络';
    notifyListeners();
    try {
      if (playOnPassport) {
        final wave = _audioAsPcm(audio);
        await ble.send(GuidePacketType.playbackStart, [
          wave.sampleRate & 0xff,
          wave.sampleRate >> 8,
        ]);
        await _sendWaveToPassport(
          wave,
          operation,
          revealedText: stop.guideNarration,
        );
        if (operation == _operationId) {
          await ble.send(GuidePacketType.responseEnd);
        }
      } else {
        await mobileVoice.playWavAndWait(audio);
      }
    } catch (error) {
      tripStatus = 'Offline playback failed: $error';
    } finally {
      _passportOperation.finish(operation);
      if (operation == _operationId) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _cancelPassportOperation() {
    final operation = _operationId;
    if (!busy) return;
    final kind = _passportOperation.cancel(operation);
    if (kind == null) return;
    _operationId += 1;
    _slowResponseTimer?.cancel();
    _activeGateway?.close();
    _activeGateway = null;
    unawaited(mobileVoice.stopPlayback());
    unawaited(_endPassportBackgroundLease());
    _recording.clear();
    busy = false;
    slowResponse = false;
    if (kind == PassportOperationKind.conversation) {
      status = 'Stopped · hold OK to ask again';
      voiceStatus = 'Ready · hold OK to ask again';
      retryAvailable = transcript.isNotEmpty;
    } else {
      tripStatus = 'Passport playback stopped';
    }
    notifyListeners();
  }

  String _contextualPrompt(String question) {
    final stop = currentStop;
    if (stop == null) {
      return '用户还没有创建路线。请简洁回答这个旅行问题，并提醒实时开放和票务信息需要核对：$question';
    }
    final completed = trip.stops
        .where((stop) => stop.completed)
        .map((stop) => stop.name)
        .join('、');
    return '当前旅程：${trip.title}；当前站点：${stop.name}；'
        '站点简介：${stop.summary}；'
        '已完成：${completed.isEmpty ? "暂无" : completed}。'
        '请结合当前地点简洁回答游客的问题：$question';
  }

  Future<void> startPhoneConversation() async {
    if (busy || phoneRecording) return;
    if (!await mobileVoice.ensurePermission()) {
      voiceError = 'Microphone permission is required';
      voiceStatus = voiceError!;
      notifyListeners();
      return;
    }
    transcript = '';
    answer = '';
    voiceError = null;
    slowResponse = false;
    retryAvailable = false;
    phoneRecording = true;
    voiceStatus = 'Listening… release to send';
    notifyListeners();
    await mobileVoice.startRecording();
  }

  Future<void> stopAndProcessPhoneConversation() async {
    if (!phoneRecording || busy) return;
    phoneRecording = false;
    busy = true;
    voiceError = null;
    slowResponse = false;
    retryAvailable = false;
    voiceStatus = 'Transcribing…';
    notifyListeners();
    final gateway = AiGateway(settings);
    _activeGateway = gateway;
    final operation = ++_operationId;
    try {
      final pcm = await mobileVoice.stopRecordingPcm();
      if (operation != _operationId) return;
      transcript = await gateway.transcribePcm(pcm);
      if (operation != _operationId) return;
      await _streamPhoneAnswer(gateway, operation);
    } catch (error) {
      if (operation == _operationId) _setPhoneError(error);
    } finally {
      gateway.close();
      if (operation == _operationId) {
        _activeGateway = null;
        _slowResponseTimer?.cancel();
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryLastConversation() async {
    if (busy || transcript.isEmpty) return;
    busy = true;
    voiceError = null;
    slowResponse = false;
    retryAvailable = false;
    answer = '';
    final gateway = AiGateway(settings);
    _activeGateway = gateway;
    final operation = ++_operationId;
    try {
      await _streamPhoneAnswer(gateway, operation);
    } catch (error) {
      if (operation == _operationId) _setPhoneError(error);
    } finally {
      gateway.close();
      if (operation == _operationId) {
        _activeGateway = null;
        _slowResponseTimer?.cancel();
        busy = false;
        notifyListeners();
      }
    }
  }

  void cancelConversation() {
    if (!busy) return;
    _operationId += 1;
    _slowResponseTimer?.cancel();
    _activeGateway?.close();
    _activeGateway = null;
    unawaited(mobileVoice.stopPlayback());
    busy = false;
    slowResponse = false;
    retryAvailable = transcript.isNotEmpty;
    voiceError = null;
    voiceStatus = retryAvailable
        ? 'Cancelled · retry without recording again'
        : 'Cancelled';
    notifyListeners();
  }

  Future<void> _streamPhoneAnswer(AiGateway gateway, int operation) async {
    answer = '';
    voiceStatus = 'Thinking…';
    notifyListeners();
    _slowResponseTimer?.cancel();
    var thinkingSeconds = 0;
    _slowResponseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (operation != _operationId || answer.isNotEmpty || _disposed) return;
      thinkingSeconds += 1;
      slowResponse = thinkingSeconds >= 12;
      voiceStatus = slowResponse
          ? 'Still thinking… ${thinkingSeconds}s · keep waiting or cancel'
          : 'Thinking… ${thinkingSeconds}s';
      notifyListeners();
    });

    final sentences = SentenceChunker();
    var speechStarted = false;
    Object? speechError;
    StackTrace? speechStack;
    Future<void> synthesisTail = Future.value();
    Future<void> speechTail = Future.value();
    DateTime? lastTtsStart;

    void queueSpeech(String phrase) {
      // SAIL currently allows two TTS requests per second. Serialize synthesis
      // starts and keep a small gap between them, while retaining a separate
      // playback queue so synthesis can overlap the preceding phrase's audio.
      final synthesis = Completer<Uint8List?>();
      synthesisTail = synthesisTail.then((_) async {
        if (operation != _operationId || speechError != null) {
          synthesis.complete(null);
          return;
        }

        final previousStart = lastTtsStart;
        if (previousStart != null) {
          const minimumGap = Duration(milliseconds: 550);
          final elapsed = DateTime.now().difference(previousStart);
          if (elapsed < minimumGap) {
            await Future<void>.delayed(minimumGap - elapsed);
          }
        }
        if (operation != _operationId) {
          synthesis.complete(null);
          return;
        }

        lastTtsStart = DateTime.now();
        try {
          synthesis.complete(await gateway.synthesize(phrase));
        } catch (error, stack) {
          speechError ??= error;
          speechStack ??= stack;
          synthesis.complete(null);
        }
      });
      if (!speechStarted) {
        voiceStatus = 'Preparing first voice…';
        notifyListeners();
      }
      speechTail = speechTail.then((_) async {
        if (operation != _operationId || speechError != null) return;
        final audio = await synthesis.future;
        if (audio == null || operation != _operationId) return;
        try {
          speechStarted = true;
          voiceStatus = 'Speaking while the answer continues…';
          notifyListeners();
          await mobileVoice.playWavAndWait(audio);
        } catch (error, stack) {
          speechError ??= error;
          speechStack ??= stack;
        }
      });
    }

    await for (final delta in gateway.chatStream(
      _contextualPrompt(transcript),
      history: _history,
    )) {
      if (operation != _operationId) return;
      if (answer.isEmpty) {
        _slowResponseTimer?.cancel();
        slowResponse = false;
      }
      answer += delta;
      voiceStatus = speechStarted
          ? 'Speaking while the answer continues…'
          : 'Answering…';
      for (final phrase in sentences.add(delta)) {
        queueSpeech(phrase);
      }
      notifyListeners();
    }

    if (operation != _operationId) return;
    final remaining = sentences.flush();
    if (remaining.isNotEmpty) queueSpeech(remaining);
    if (answer.trim().isEmpty) {
      throw const FormatException('AI returned an empty answer');
    }
    _history
      ..add({'role': 'user', 'content': transcript})
      ..add({'role': 'assistant', 'content': answer});
    if (_history.length > 8) _history.removeRange(0, _history.length - 8);
    voiceStatus = speechStarted ? 'Finishing voice…' : 'Creating voice…';
    notifyListeners();
    await speechTail;
    if (speechError != null) {
      Error.throwWithStackTrace(speechError!, speechStack!);
    }
    if (operation != _operationId) return;
    voiceStatus = 'Ready · hold the mic to ask again';
    retryAvailable = false;
    notifyListeners();
  }

  void _setPhoneError(Object error) {
    final message = error is TimeoutException
        ? transcript.isEmpty
              ? 'Speech recognition timed out'
              : 'AI did not respond for 90 seconds'
        : '$error';
    voiceError = message;
    voiceStatus = 'Request failed · retry or ask again';
    retryAvailable = transcript.isNotEmpty;
    slowResponse = false;
    notifyListeners();
  }

  Future<void> _processRecording() async {
    if (busy || _recording.isEmpty) {
      await _endPassportBackgroundLease();
      return;
    }
    _passportBackgroundLease ??= backgroundExecution.begin(
      'Passport voice question',
    );
    try {
      await _passportBackgroundLease;
    } catch (error) {
      debugPrint('Could not begin iOS background task: $error');
    }
    busy = true;
    status = 'Transcribing…';
    notifyListeners();
    final gateway = AiGateway(settings);
    _activeGateway = gateway;
    final operation = ++_operationId;
    _passportOperation.start(operation, PassportOperationKind.conversation);
    try {
      final pcm = _pcmBytes(_recording);
      transcript = await gateway.transcribePcm(pcm, sampleRate: _sampleRate);
      if (operation != _operationId) return;
      await ble.sendText(GuidePacketType.transcript, transcript);
      status = 'Asking AI…';
      notifyListeners();
      await _streamPassportAnswer(gateway, operation);
      if (operation != _operationId) return;
      status = 'Ready · hold OK to ask again';
    } catch (error) {
      if (operation != _operationId) return;
      status = 'Request failed: $error';
      try {
        await ble.sendText(GuidePacketType.error, status);
      } catch (_) {
        // Preserve the original request error when BLE also disconnected.
      }
    } finally {
      _passportOperation.finish(operation);
      _recording.clear();
      gateway.close();
      await _endPassportBackgroundLease();
      if (operation == _operationId) {
        _activeGateway = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _endPassportBackgroundLease() async {
    final lease = _passportBackgroundLease;
    _passportBackgroundLease = null;
    if (lease == null) return;
    try {
      await lease;
      await backgroundExecution.end();
    } catch (error) {
      debugPrint('Could not end iOS background task: $error');
    }
  }

  Future<void> _streamPassportAnswer(AiGateway gateway, int operation) async {
    answer = '';
    final sentences = SentenceChunker();
    Object? speechError;
    StackTrace? speechStack;
    Future<void> synthesisTail = Future.value();
    Future<void> playbackTail = Future.value();
    DateTime? lastTtsStart;
    var playbackStarted = false;

    void queueSpeech(String phrase) {
      final synthesis = Completer<Uint8List?>();
      synthesisTail = synthesisTail.then((_) async {
        if (operation != _operationId || speechError != null) {
          synthesis.complete(null);
          return;
        }
        final previousStart = lastTtsStart;
        if (previousStart != null) {
          const minimumGap = Duration(milliseconds: 550);
          final elapsed = DateTime.now().difference(previousStart);
          if (elapsed < minimumGap) {
            await Future<void>.delayed(minimumGap - elapsed);
          }
        }
        if (operation != _operationId) {
          synthesis.complete(null);
          return;
        }
        lastTtsStart = DateTime.now();
        try {
          synthesis.complete(await gateway.synthesize(phrase));
        } catch (error, stack) {
          speechError ??= error;
          speechStack ??= stack;
          synthesis.complete(null);
        }
      });

      playbackTail = playbackTail.then((_) async {
        final audio = await synthesis.future;
        if (audio == null || operation != _operationId) return;
        try {
          final wave = _audioAsPcm(audio);
          if (!playbackStarted) {
            playbackStarted = true;
            await ble.send(GuidePacketType.playbackStart, [
              wave.sampleRate & 0xff,
              wave.sampleRate >> 8,
            ]);
          }
          /*
           * Keep Passport's visible answer on the same sentence as playback.
           * Sending text from the LLM stream makes the display race ahead
           * while TTS synthesis is still queued.
           */
          status = 'Playing answer on Passport…';
          notifyListeners();
          await _sendWaveToPassport(wave, operation, revealedText: phrase);
        } catch (error, stack) {
          speechError ??= error;
          speechStack ??= stack;
        }
      });
    }

    await for (final delta in gateway.chatStream(
      _contextualPrompt(transcript),
      history: _history,
    )) {
      if (operation != _operationId) return;
      answer += delta;
      for (final phrase in sentences.add(delta)) {
        queueSpeech(phrase);
      }
      notifyListeners();
    }

    if (operation != _operationId) return;
    final remaining = sentences.flush();
    if (remaining.isNotEmpty) {
      queueSpeech(remaining);
    }
    if (answer.trim().isEmpty) {
      throw const FormatException('AI returned an empty answer');
    }
    _history
      ..add({'role': 'user', 'content': transcript})
      ..add({'role': 'assistant', 'content': answer});
    if (_history.length > 8) _history.removeRange(0, _history.length - 8);

    status = playbackStarted ? 'Finishing playback…' : 'Creating voice…';
    notifyListeners();
    await playbackTail;
    if (speechError != null) {
      Error.throwWithStackTrace(speechError!, speechStack!);
    }
    if (operation == _operationId) {
      await ble.send(GuidePacketType.responseEnd);
    }
  }

  Future<void> _sendWaveToPassport(
    PcmWave wave,
    int operation, {
    String revealedText = '',
  }) async {
    const blockSamples = 320;
    const transmissionHeadroom = 0.98;
    final totalBlocks =
        (wave.samples.length + blockSamples - 1) ~/ blockSamples;
    final textReveal = TimedTextReveal(revealedText, totalSteps: totalBlocks);
    final clock = Stopwatch()..start();
    final encoder = ImaAdpcmEncoder();
    var blocksSent = 0;
    for (var offset = 0; offset < wave.samples.length; offset += blockSamples) {
      if (operation != _operationId) return;
      final end = (offset + blockSamples).clamp(0, wave.samples.length);
      final chunk = Int16List(blockSamples);
      chunk.setRange(0, end - offset, wave.samples, offset);
      await ble.sendAudio(encoder.encode(chunk));
      blocksSent += 1;
      final textChunk = textReveal.takeStep(blocksSent);
      if (textChunk.isNotEmpty && operation == _operationId) {
        await ble.sendText(GuidePacketType.answerText, textChunk);
      }
      final target = Duration(
        microseconds:
            blocksSent *
            blockSamples *
            1000000 *
            transmissionHeadroom ~/
            wave.sampleRate,
      );
      final remaining = target - clock.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    }
  }

  static Uint8List _pcmBytes(List<Int16List> blocks) {
    final length = blocks.fold<int>(0, (sum, block) => sum + block.length * 2);
    final output = Uint8List(length);
    final view = ByteData.sublistView(output);
    var offset = 0;
    for (final block in blocks) {
      for (final sample in block) {
        view.setInt16(offset, sample, Endian.little);
        offset += 2;
      }
    }
    return output;
  }

  PcmWave _audioAsPcm(Uint8List audio) {
    final wavIndex = audio.indexOf(0x52);
    final startsWithRiff =
        audio.length >= 4 &&
        audio[0] == 0x52 &&
        audio[1] == 0x49 &&
        audio[2] == 0x46 &&
        audio[3] == 0x46;
    if (!startsWithRiff && wavIndex > 0) {
      return WavCodec.decodeMonoPcm16(Uint8List.sublistView(audio, wavIndex));
    }
    if (startsWithRiff) return WavCodec.decodeMonoPcm16(audio);
    if (audio.length.isEven) {
      final samples = Int16List(audio.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = ByteData.sublistView(audio).getInt16(i * 2, Endian.little);
      }
      return PcmWave(sampleRate: 16000, samples: samples);
    }
    throw const FormatException('TTS audio is not 16-bit PCM/WAV');
  }

  @override
  void dispose() {
    _disposed = true;
    _operationId += 1;
    _slowResponseTimer?.cancel();
    _activeGateway?.close();
    unawaited(_endPassportBackgroundLease());
    unawaited(ble.disconnect());
    unawaited(mobileVoice.dispose());
    super.dispose();
  }
}
