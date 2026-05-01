import 'package:flutter/material.dart';
import '../app_settings.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class AuthGateScreen extends StatefulWidget {
  final AppSettings settings;

  const AuthGateScreen({super.key, required this.settings});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onAuthSuccess() {
    // Pop back to main — main.dart will reload settings and show SetupScreen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DTFool'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Войти'),
            Tab(text: 'Регистрация'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          LoginScreen(settings: widget.settings, onSuccess: _onAuthSuccess),
          RegisterScreen(settings: widget.settings, onSuccess: _onAuthSuccess),
        ],
      ),
    );
  }
}
