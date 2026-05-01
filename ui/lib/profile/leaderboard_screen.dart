import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../api/stats_api.dart';
import '../app_settings.dart';
import 'stats_widgets.dart';
import 'user_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  final AppSettings settings;

  const LeaderboardScreen({super.key, required this.settings});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  static const _sortOptions = [
    ('wins', 'Победы'),
    ('games_played', 'Партии'),
    ('winrate', 'Винрейт'),
    ('losses', 'Поражения'),
    ('draws', 'Ничьи'),
  ];

  String _sort = 'wins';
  final List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  int _totalGames = 0;
  int _onlineUsers = 0;

  late final StatsApi _api;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _api = StatsApi(ApiClient(widget.settings.baseHttpUrl));
    _scrollCtrl.addListener(_onScroll);
    _loadServerStats();
    _loadMore();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadServerStats() async {
    try {
      final s = await _api.getServerStats();
      if (mounted) {
        setState(() {
          _totalGames = s['total_games'] as int? ?? 0;
          _onlineUsers = s['online_users'] as int? ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _reload() async {
    _items.clear();
    _hasMore = true;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final data = await _api.getLeaderboard(
        sort: _sort,
        order: 'desc',
        limit: 50,
        offset: _items.length,
      );
      final items = (data['items'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      if (mounted) {
        setState(() {
          _total = data['total'] as int? ?? 0;
          _items.addAll(items);
          _hasMore = _items.length < _total;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeSort(String? sort) {
    if (sort == null || sort == _sort) return;
    setState(() { _sort = sort; _items.clear(); _hasMore = true; });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лидерборд'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text('Игр: $_totalGames  •  Онлайн: $_onlineUsers',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                DropdownButton<String>(
                  value: _sort,
                  isDense: true,
                  items: _sortOptions
                      .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                      .toList(),
                  onChanged: _changeSort,
                ),
              ],
            ),
          ),
        ),
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildItem(_items[i]);
                },
              ),
            ),
    );
  }

  Widget _buildItem(Map<String, dynamic> entry) {
    final rank = entry['rank'] as int;
    final user = entry['user'] as Map<String, dynamic>;
    final stats = entry['stats'] as Map<String, dynamic>;
    final avatarUrl = user['avatar_url'] as String?;
    final baseUrl = widget.settings.baseHttpUrl;

    String metric;
    switch (_sort) {
      case 'winrate':
        final wr = statsWinrate(stats);
        metric = wr == null ? '—' : '${(wr * 100).toStringAsFixed(1)}%';
      case 'losses':
        metric = '${statsLosses(stats)} пор.';
      case 'draws':
        metric = '${statsDraws(stats)} ничьих';
      case 'games_played':
        metric = '${statsGames(stats)} партий';
      default:
        metric = '${statsWins(stats)} побед';
    }

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider('$baseUrl$avatarUrl')
                : null,
            child: avatarUrl == null ? const Icon(Icons.person, size: 18) : null,
          ),
        ],
      ),
      title: Text(user['username'] as String),
      trailing: Text(metric, style: const TextStyle(color: Colors.grey)),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userId: user['id'] as int,
            baseUrl: baseUrl,
          ),
        ),
      ),
    );
  }
}
