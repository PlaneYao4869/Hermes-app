import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

/// Voice input button with fallback to text input.
/// Short press = text input dialog (always works)
/// Long press = voice input (speech_to_text)
class VoiceInputButton extends StatefulWidget {
  final ValueChanged<String> onResult;
  const VoiceInputButton({super.key, required this.onResult});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;
  bool _initAttempted = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _tryInitSpeech() async {
    if (_initAttempted) return;
    _initAttempted = true;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能使用语音输入')),
          );
        }
        return;
      }
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
            _pulseController.stop();
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
          _pulseController.stop();
        },
      );
      if (mounted) setState(() => _isAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _isAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    if (!_initAttempted) await _tryInitSpeech();

    if (!_isAvailable) {
      _showTextInput();
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
        _pulseController.stop();
      }
    } else {
      try {
        if (mounted) setState(() => _isListening = true);
        _pulseController.repeat(reverse: true);
        await _speech.listen(
          onResult: (result) {
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              widget.onResult(result.recognizedWords);
            }
          },
          localeId: 'zh_CN',
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _isListening = false);
          _pulseController.stop();
          _showTextInput();
        }
      }
    }
  }

  void _showTextInput() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '输入你的消息...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  widget.onResult(text.trim());
                  Navigator.pop(ctx);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      widget.onResult(text);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _toggleListening,
      child: IconButton(
        onPressed: _showTextInput,
        icon: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: _isListening ? 1.0 + _pulseController.value * 0.15 : 1.0,
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.red : Theme.of(context).colorScheme.primary,
              ),
            );
          },
        ),
        tooltip: _isListening ? '停止录音' : '文字输入（长按语音）',
      ),
    );
  }
}
