import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class VoiceInputButton extends StatefulWidget {
  final ValueChanged<String> onResult;
  const VoiceInputButton({super.key, required this.onResult});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => setState(() => _isListening = false),
    );
    setState(() => _isAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_isAvailable) {
      // Request permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      await _initSpeech();
      if (!_isAvailable) return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            widget.onResult(result.recognizedWords);
          }
        },
        localeId: 'zh_CN',
        listenMode: stt.ListenMode.dictation,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggleListening,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          key: ValueKey(_isListening),
          color: _isListening ? Colors.red : Colors.grey,
        ),
      ),
      tooltip: _isListening ? '停止录音' : '语音输入',
    );
  }
}
