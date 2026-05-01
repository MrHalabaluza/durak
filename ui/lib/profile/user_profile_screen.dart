import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../api/users_api.dart';
import 'stats_widgets.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;
  final String baseUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.baseUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = UsersApi(ApiClient(widget.baseUrl));
      final data = await api.getUser(widget.userId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _data?['user'] as Map<String, dynamic>?;
    final stats = _data?['stats'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: Text(user?['username'] as String? ?? 'Профиль')),
      body: _data == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: _AvatarWidget(
                        avatarUrl: user?['avatar_url'] as String?,
                        baseUrl: widget.baseUrl,
                        radius: 48,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        user?['username'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
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
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.person, size: radius),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage:
          CachedNetworkImageProvider('$baseUrl$avatarUrl'),
    );
  }
}
