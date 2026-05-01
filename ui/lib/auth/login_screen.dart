import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../app_settings.dart';
import 'password_hash.dart';

class LoginScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onSuccess;

  const LoginScreen({super.key, required this.settings, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = ApiClient(widget.settings.baseHttpUrl);
      final api = AuthApi(client);
      final res = await api.login(
        _userCtrl.text.trim(),
        clientPasswordHash(_userCtrl.text.trim(), _passCtrl.text),
      );
      await widget.settings.saveAuth(
        token: res.token,
        userId: res.userId,
        username: res.username,
        avatarUrl: res.avatarUrl,
      );
      if (mounted) widget.onSuccess();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.code == 'bad_credentials'
                ? 'Неверное имя пользователя или пароль'
                : e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка соединения: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: 'Имя пользователя',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Введите имя пользователя' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Пароль',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Введите пароль' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Войти'),
          ),
        ],
      ),
    );
  }
}
