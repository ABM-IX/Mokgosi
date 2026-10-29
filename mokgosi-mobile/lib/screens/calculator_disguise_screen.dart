import 'dart:async';
import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import '../services/motion_telemetry.dart';
import 'app_home_screen.dart';

/// A plain, working calculator. Typing the safe PIN then "=" opens the app; typing the duress PIN
/// then "=" quietly sends an alert and simply shows the result, like any other sum.
class CalculatorDisguiseScreen extends StatefulWidget {
  const CalculatorDisguiseScreen({
    super.key,
    this.safePin = MokgosiConfig.safePin,
    this.duressPin = MokgosiConfig.duressPin,
  });

  final String safePin;
  final String duressPin;

  @override
  State<CalculatorDisguiseScreen> createState() => _CalculatorDisguiseScreenState();
}

// Deliberately not Mokgosi's colours: this screen has to look like any calculator.
const _background = Color(0xFFF3F3F1);
const _digitKey = Color(0xFFFFFFFF);
const _functionKey = Color(0xFFE4E3DF);
const _operatorKey = Color(0xFFD7DCE1);
const _equalsKey = Color(0xFF2F3A45);
const _keyText = Color(0xFF22262A);
const _faintText = Color(0xFF7A7F85);

const _operators = {'+', '−', '×', '÷'};

class _CalculatorDisguiseScreenState extends State<CalculatorDisguiseScreen> {
  final List<String> _tokens = <String>[]; // numbers and operators, e.g. ['12', '×', '3']
  String _result = ''; // shown large after "="
  bool _justEvaluated = false;
  // Raw keys since the last clear or "=", for PIN matching. Kept apart from _tokens because the
  // display drops leading zeros ("0852" shows as 852) and the PIN check must not.
  String _keys = '';

  bool get _endsWithNumber => _tokens.isNotEmpty && !_operators.contains(_tokens.last);

  void _onDigit(String digit) {
    setState(() {
      if (_justEvaluated) {
        _tokens.clear();
        _result = '';
        _justEvaluated = false;
      }
      _keys += digit;
      if (_endsWithNumber) {
        final current = _tokens.last;
        _tokens[_tokens.length - 1] = current == '0' ? digit : current + digit;
      } else {
        _tokens.add(digit);
      }
    });
  }

  void _onDot() {
    setState(() {
      if (_justEvaluated) {
        _tokens.clear();
        _result = '';
        _justEvaluated = false;
      }
      _keys += '.';
      if (!_endsWithNumber) {
        _tokens.add('0.');
      } else if (!_tokens.last.contains('.')) {
        _tokens[_tokens.length - 1] = '${_tokens.last}.';
      }
    });
  }

  void _onOperator(String op) {
    setState(() {
      if (_justEvaluated) {
        _tokens
          ..clear()
          ..add(_result == 'Error' ? '0' : _result);
        _result = '';
        _justEvaluated = false;
      }
      if (_tokens.isEmpty) {
        _tokens.add('0');
      }
      _keys += op;
      if (_endsWithNumber) {
        _tokens.add(op);
      } else {
        _tokens[_tokens.length - 1] = op;
      }
    });
  }

  void _onClear() {
    setState(_onClearState);
  }

  void _onBackspace() {
    setState(() {
      if (_justEvaluated) {
        _onClearState();
        return;
      }
      if (_keys.isNotEmpty) _keys = _keys.substring(0, _keys.length - 1);
      if (_tokens.isEmpty) return;
      final last = _tokens.last;
      if (_operators.contains(last) || last.length <= 1 || (last.length == 2 && last.startsWith('-'))) {
        _tokens.removeLast();
      } else {
        _tokens[_tokens.length - 1] = last.substring(0, last.length - 1);
      }
    });
  }

  void _onClearState() {
    _tokens.clear();
    _result = '';
    _justEvaluated = false;
    _keys = '';
  }

  void _onPercent() {
    if (!_endsWithNumber) return;
    setState(() {
      final value = double.tryParse(_tokens.last) ?? 0;
      _tokens[_tokens.length - 1] = _format(value / 100);
      _keys += '%';
    });
  }

  void _onSign() {
    if (!_endsWithNumber) return;
    setState(() {
      final current = _tokens.last;
      _tokens[_tokens.length - 1] = current.startsWith('-') ? current.substring(1) : '-$current';
      _keys += '±';
    });
  }

  void _onEquals() {
    final typed = _keys;
    _keys = '';
    if (typed.endsWith(widget.safePin)) {
      _onClear();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppHomeScreen()),
      );
      return;
    }
    if (typed.endsWith(widget.duressPin)) {
      // Nothing on screen changes beyond the ordinary result.
      unawaited(_sendCovertAlert());
    }
    if (_tokens.isEmpty) return;
    final value = _evaluate(_tokens);
    setState(() {
      _result = value == null ? 'Error' : _format(value);
      _justEvaluated = true;
    });
  }

  Future<void> _sendCovertAlert() async {
    final fix = await MotionTelemetry().resolveCurrentFix(
      pinToGaboroneDemoCbd: MokgosiConfig.demoMode,
      requestPermission: false,
    );
    await IncidentApi.trigger('COVERT_SOS', category: 'GBV_DOMESTIC', lat: fix.lat, lng: fix.lng);
  }

  /// × and ÷ before + and −; returns null for division by zero.
  static double? _evaluate(List<String> tokens) {
    final items = List<String>.from(tokens);
    if (items.isNotEmpty && _operators.contains(items.last)) items.removeLast();
    if (items.isEmpty) return 0;
    final values = <double>[double.tryParse(items.first) ?? 0];
    final pending = <String>[];
    for (var i = 1; i + 1 < items.length; i += 2) {
      final op = items[i];
      final next = double.tryParse(items[i + 1]) ?? 0;
      if (op == '×') {
        values[values.length - 1] *= next;
      } else if (op == '÷') {
        if (next == 0) return null;
        values[values.length - 1] /= next;
      } else {
        pending.add(op);
        values.add(next);
      }
    }
    var total = values.first;
    for (var i = 0; i < pending.length; i++) {
      total = pending[i] == '+' ? total + values[i + 1] : total - values[i + 1];
    }
    return total;
  }

  static String _format(double value) {
    if (value.isInfinite || value.isNaN) return 'Error';
    if (value == value.roundToDouble() && value.abs() < 1e15) return value.toInt().toString();
    var text = value.toStringAsPrecision(12);
    if (text.contains('e')) return text;
    text = text.replaceFirst(RegExp(r'0+$'), '');
    return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  }

  String _preview() {
    if (_justEvaluated || _tokens.length < 3) return '';
    final value = _evaluate(_tokens);
    return value == null ? 'Can’t divide by 0' : _format(value);
  }

  Widget _key(String label, VoidCallback onTap,
      {Key? key, Color color = _digitKey, Color text = _keyText, double size = 28, IconData? icon}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: AspectRatio(
          aspectRatio: 1.15,
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: size, color: text, semanticLabel: label)
                    : Text(label, style: TextStyle(fontSize: size, color: text, fontWeight: FontWeight.w400)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final main = _justEvaluated ? _result : (_tokens.isEmpty ? '0' : _tokens.join(' '));
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_justEvaluated && _tokens.length > 1)
                      Text(_tokens.join(' '), style: const TextStyle(fontSize: 22, color: _faintText)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        main,
                        key: const Key('calculator_display'),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 60, color: _keyText, fontWeight: FontWeight.w300),
                      ),
                    ),
                    SizedBox(
                      height: 30,
                      child: Text(_preview(), style: const TextStyle(fontSize: 22, color: _faintText)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                children: [
                  Row(children: [
                    _key('AC', _onClear, key: const Key('calc_btn_clear'), color: _functionKey, size: 22),
                    _key('Delete', _onBackspace,
                        key: const Key('calc_btn_backspace'), color: _functionKey, size: 24, icon: Icons.backspace_outlined),
                    _key('%', _onPercent, key: const Key('calc_btn_percent'), color: _functionKey, size: 24),
                    _key('÷', () => _onOperator('÷'), key: const Key('calc_btn_div'), color: _operatorKey),
                  ]),
                  Row(children: [
                    _key('7', () => _onDigit('7'), key: const Key('calc_btn_7')),
                    _key('8', () => _onDigit('8'), key: const Key('calc_btn_8')),
                    _key('9', () => _onDigit('9'), key: const Key('calc_btn_9')),
                    _key('×', () => _onOperator('×'), key: const Key('calc_btn_mult'), color: _operatorKey),
                  ]),
                  Row(children: [
                    _key('4', () => _onDigit('4'), key: const Key('calc_btn_4')),
                    _key('5', () => _onDigit('5'), key: const Key('calc_btn_5')),
                    _key('6', () => _onDigit('6'), key: const Key('calc_btn_6')),
                    _key('−', () => _onOperator('−'), key: const Key('calc_btn_sub'), color: _operatorKey),
                  ]),
                  Row(children: [
                    _key('1', () => _onDigit('1'), key: const Key('calc_btn_1')),
                    _key('2', () => _onDigit('2'), key: const Key('calc_btn_2')),
                    _key('3', () => _onDigit('3'), key: const Key('calc_btn_3')),
                    _key('+', () => _onOperator('+'), key: const Key('calc_btn_add'), color: _operatorKey),
                  ]),
                  Row(children: [
                    _key('±', _onSign, key: const Key('calc_btn_sign'), color: _functionKey, size: 24),
                    _key('0', () => _onDigit('0'), key: const Key('calc_btn_0')),
                    _key('.', _onDot, key: const Key('calc_btn_dot')),
                    _key('=', _onEquals, key: const Key('calc_btn_equals'), color: _equalsKey, text: Colors.white),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
