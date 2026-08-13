// 文件位置: lib/pages/user_profile_page.dart

import 'package:flutter/material.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/api/api_client.dart'; 
import 'package:xsop_forum/main.dart'; 

import 'package:xsop_forum/pages/discussion_detail_page.dart'; 
import 'package:xsop_forum/pages/home_page.dart' show formatRelativeTime; 

class UserProfilePage extends StatefulWidget {
  final FlarumUser user;
  final ApiClient api;

  const UserProfilePage({super.key, required this.user, required this.api});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late FlarumUser _currentUser;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _syncLatestUserData();
  }

  Future<void> _syncLatestUserData() async {
    setState(() => _isRefreshing = true);
    try {
      final res = await widget.api.getUser(int.parse(_currentUser.id));
      if (mounted) {
        setState(() {
          _currentUser = parseUser(res, widget.api.baseUrl);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('个人中心', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            color: Colors.white,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.grey.shade100,
                      backgroundImage: _currentUser.avatarUrl != null
                          ? NetworkImage(_currentUser.avatarUrl!)
                          : null,
                      child: _currentUser.avatarUrl == null
                          ? Icon(Icons.person, size: 50, color: scheme.primary)
                          : null,
                    ),
                    if (_isRefreshing)
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _currentUser.displayName.isNotEmpty ? _currentUser.displayName : _currentUser.username,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_currentUser.groups.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      buildUserBadges(_currentUser.groups),
                    ]
                  ],
                ),
                
                const SizedBox(height: 4),
                Text(
                  '@${_currentUser.username}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.outline,
                      ),
                ),
                const SizedBox(height: 16),
                
                // [核心修复：完美对齐网页截图，展示 `徽章 - 7 - 大拇指 - 金币`]
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B4844), 
                    borderRadius: BorderRadius.circular(4), 
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.military_tech, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(_currentUser.likesReceived, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 4),
                      const Icon(Icons.thumb_up, size: 14, color: Colors.amber),
                      
                      const SizedBox(width: 16),
                      Text('${_currentUser.money} XSD', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('社区互动'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserDiscussionsPage(user: _currentUser),
                ),
              );
            },
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA), indent: 56),
          
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class UserDiscussionsPage extends StatefulWidget {
  final FlarumUser user;

  const UserDiscussionsPage({super.key, required this.user});

  @override
  State<UserDiscussionsPage> createState() => _UserDiscussionsPageState();
}

class _UserDiscussionsPageState extends State<UserDiscussionsPage> {
  final List<Discussion> _discussions = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _page = 1;
      final res = await apiClient.getDiscussions(page: 1, author: widget.user.username);
      final list = parseDiscussionList(res, apiClient.baseUrl);
      if (mounted) {
        setState(() {
          _discussions
            ..clear()
            ..addAll(list.items);
          _hasMore = list.hasMore;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _error = '加载失败，请检查网络';
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        !_isLoading &&
        _hasMore &&
        _error == null) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final res = await apiClient.getDiscussions(page: _page + 1, author: widget.user.username);
      final list = parseDiscussionList(res, apiClient.baseUrl);
      if (mounted) {
        setState(() {
          _discussions.addAll(list.items);
          _hasMore = list.hasMore;
          _page += 1;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('社区互动', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _discussions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _discussions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_discussions.isEmpty) {
      return const Center(child: Text('暂无互动记录', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: _discussions.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
      itemBuilder: (context, index) {
        if (index == _discussions.length) {
          return _loadingMore
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : const SizedBox(height: 24);
        }
        
        final discussion = _discussions[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DiscussionDetailPage(api: apiClient, discussion: discussion)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discussion.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.3),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text('${discussion.commentCount}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    const SizedBox(width: 16),
                    Icon(Icons.schedule, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(formatRelativeTime(discussion.createdAt), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  title: const Text('退出登录'),
                  content: const Text('确定要退出当前账号吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消', style: TextStyle(color: Colors.grey)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        await apiClient.logout();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const XSOPForumApp()),
                            (route) => false,
                          );
                        }
                      },
                      child: const Text('确定退出'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
