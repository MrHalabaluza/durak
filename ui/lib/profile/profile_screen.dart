import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/me_api.dart';
import '../app_settings.dart';
import '../auth/auth_gate_screen.dart';
import 'stats_widgets.dart';

class ProfileScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const ProfileScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _uploading = false;

  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _load();
  }

  Future<void> _load() async {
    try {
      final api = MeApi(ApiClient(_settings.baseHttpUrl)..token = _settings.token);
      final data = await api.getMe();
      if (mounted) setState(() { _data = data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _uploading = true);
    try {
      final api = MeApi(ApiClient(_settings.baseHttpUrl)..token = _settings.token);
      final avatarUrl = await api.uploadAvatar(
          Uint8List.fromList(bytes), picked.name, contentType);
      if (avatarUrl != null) {
        await _settings.saveAuth(
          token: _settings.token!,
          userId: _settings.userId!,
          username: _settings.username!,
          avatarUrl: avatarUrl,
        );
        final updated = _settings.copyWith(avatarUrl: avatarUrl);
        setState(() => _settings = updated);
        widget.onSettingsChanged(updated);
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _logout() async {
    try {
      final api = AuthApi(ApiClient(_settings.baseHttpUrl)..token = _settings.token);
      await api.logout();
    } catch (_) {}
    await AppSettings.clearAuth();
    if (!mounted) return;
    // Navigate to auth gate, clearing the back stack
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AuthGateScreen(settings: _settings),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _data?['user'] as Map<String, dynamic>?;
    final stats = _data?['stats'] as Map<String, dynamic>?;
    final avatarUrl = user?['avatar_url'] as String? ?? _settings.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: _logout,
          ),
        ],
      ),
      body: _data == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            _AvatarWidget(
                              avatarUrl: avatarUrl,
                              baseUrl: _settings.baseHttpUrl,
                              radius: 52,
                            ),
                            if (_uploading)
                              const Positioned.fill(
                                child: CircleAvatar(
                                  backgroundColor: Colors.black45,
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: _uploading ? null : _pickAndUploadAvatar,
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('Сменить аватарку'),
                        ),
                      ),
                      Center(
                        child: Text(
                          user?['username'] as String? ?? _settings.username ?? '',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(child: WinrateBadge(winrate: statsWinrate(stats ?? {}))),
                      const SizedBox(height: 24),
                      StatsCardGrid(
                        games: statsGames(stats ?? {}),
                        wins: statsWins(stats ?? {}),
                        losses: statsLosses(stats ?? {}),
                        draws: statsDraws(stats ?? {}),
                        winrate: statsWinrate(stats ?? {}),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String baseUrl;
  final double radius;

  const _AvatarWidget({
    required this.avatarUrl,
    required this.baseUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl == null) {
      return CircleAvatar(radius: radius, child: Icon(Icons.person, size: radius));
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: CachedNetworkImageProvider('$baseUrl$avatarUrl'),
    );
  }
}
