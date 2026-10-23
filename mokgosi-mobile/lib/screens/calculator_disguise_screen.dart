import 'package:flutter/material.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import 'app_home_screen.dart';

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

class _CalculatorDisguiseScreenState extends State<CalculatorDisguiseScreen> {
  String _display = '0';
  String _inputBuffer = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;

  void _onDigit(String digit) {
    setState(() {
      _inputBuffer += digit;
      if (_display == '0' || _shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        _display += digit;
      }
    });
  }

  void _onOperator(String op) {
    setState(() {
      _inputBuffer += op;
      _firstOperand = double.tryParse(_display);
      _operator = op;
      _shouldResetDisplay = true;
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _inputBuffer = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = false;
    });
  }

  void _onEquals() {
    // Check for Safe PIN secret entry
    if (_inputBuffer.endsWith(widget.safePin)) {
      _inputBuffer = '';
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppHomeScreen()),
      );
      return;
    }

    // Check for Duress PIN secret entry
    if (_inputBuffer.endsWith(widget.duressPin)) {
      _inputBuffer = '';
      // Silently dispatch covert SOS without any sound, vibration, or alert notification
      IncidentApi.trigger('COVERT_SOS', category: 'GBV_DOMESTIC');
      setState(() {
        _display = '0';
        _shouldResetDisplay = true;
      });
      return;
    }

    // Regular calculator math evaluation
    if (_operator != null && _firstOperand != null) {
      final secondOperand = double.tryParse(_display) ?? 0.0;
      double result = 0.0;
      switch (_operator) {
        case '+':
          result = _firstOperand! + secondOperand;
          break;
        case '-':
          result = _firstOperand! - secondOperand;
          break;
        case '×':
          result = _firstOperand! * secondOperand;
          break;
        case '÷':
          result = secondOperand != 0 ? _firstOperand! / secondOperand : 0.0;
          break;
      }
      setState(() {
        _display = result % 1 == 0 ? result.toInt().toString() : result.toStringAsFixed(2);
        _inputBuffer = '';
        _firstOperand = null;
        _operator = null;
        _shouldResetDisplay = true;
      });
    }
  }

  Widget _buildButton(
    String label, {
    Color? bgColor,
    Color? fgColor,
    VoidCallback? onTap,
    Key? key,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: ElevatedButton(
            key: key,
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor ?? const Color(0xff2d3748),
              foregroundColor: fgColor ?? Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              elevation: 0,
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff171923),
      body: SafeArea(
        child: Column(
          children: [
            // Calculator Output Area
            Expanded(
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text(
                  _display,
                  key: const Key('calculator_display'),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 54,
                    color: Colors.white,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
            const Divider(color: Color(0xff2d3748), height: 1),
            // Calculator Keypad Grid
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildButton('C', bgColor: const Color(0xff4a5568), onTap: _onClear, key: const Key('calc_btn_clear')),
                      _buildButton('±', bgColor: const Color(0xff4a5568), onTap: () {
                        setState(() {
                          if (_display.startsWith('-')) {
                            _display = _display.substring(1);
                          } else if (_display != '0') {
                            _display = '-$_display';
                          }
                        });
                      }),
                      _buildButton('%', bgColor: const Color(0xff4a5568), onTap: () {
                        final val = double.tryParse(_display) ?? 0.0;
                        setState(() => _display = (val / 100).toString());
                      }),
                      _buildButton('÷', bgColor: const Color(0xffed8936), onTap: () => _onOperator('÷'), key: const Key('calc_btn_div')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton('7', onTap: () => _onDigit('7'), key: const Key('calc_btn_7')),
                      _buildButton('8', onTap: () => _onDigit('8'), key: const Key('calc_btn_8')),
                      _buildButton('9', onTap: () => _onDigit('9'), key: const Key('calc_btn_9')),
                      _buildButton('×', bgColor: const Color(0xffed8936), onTap: () => _onOperator('×'), key: const Key('calc_btn_mult')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton('4', onTap: () => _onDigit('4'), key: const Key('calc_btn_4')),
                      _buildButton('5', onTap: () => _onDigit('5'), key: const Key('calc_btn_5')),
                      _buildButton('6', onTap: () => _onDigit('6'), key: const Key('calc_btn_6')),
                      _buildButton('-', bgColor: const Color(0xffed8936), onTap: () => _onOperator('-'), key: const Key('calc_btn_sub')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton('1', onTap: () => _onDigit('1'), key: const Key('calc_btn_1')),
                      _buildButton('2', onTap: () => _onDigit('2'), key: const Key('calc_btn_2')),
                      _buildButton('3', onTap: () => _onDigit('3'), key: const Key('calc_btn_3')),
                      _buildButton('+', bgColor: const Color(0xffed8936), onTap: () => _onOperator('+'), key: const Key('calc_btn_add')),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton('0', onTap: () => _onDigit('0'), key: const Key('calc_btn_0')),
                      _buildButton('.', onTap: () => _onDigit('.'), key: const Key('calc_btn_dot')),
                      _buildButton('=', bgColor: const Color(0xff38a169), onTap: _onEquals, key: const Key('calc_btn_equals')),
                    ],
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
