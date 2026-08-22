// 文件位置: lib/pages/user_center_page.dart

import 'package:flutter/material.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/pages/user_activity_page.dart';

class UserCenterPage extends StatefulWidget {
  final ApiClient api;

  const UserCenterPage({super.key, required this.api});

  @override
  State<UserCenterPage> createState() => _UserCenterPageState();
}

class _UserCenterPageState extends State<UserCenterPage> {
  bool _isLoading = true;
  FlarumUser? _user;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = await widget.api.getUserId();
      if (userId == null) {
        setState(() {
          _error = '请先登录';
          _isLoading = false;
        });
        return;
      }
      final data = await widget.api.getUser(userId);
      if (mounted) {
        setState(() {
          _user = parseUser(data, widget.api.baseUrl);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '无法加载用户信息，请检查网络';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToActivity(String title, String type) {
    if (_user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserActivityPage(
          api: widget.api,
          user: _user!,
          title: title,
          activityType: type,
        ),
      ),
    );
  }

  void _logout() async {
    await widget.api.logout();
    if (mounted) {
      Navigator.pop(context, true); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('个人中心', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error ?? '未知错误', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadUserProfile, child: const Text('重试')),
          ],
        ),
      );
    }

    final displayName = _user!.displayName.isNotEmpty ? _user!.displayName : _user!.username;
    
    // 提取余额数据 (XSD)
    String balance = '0';
    if (_user!.attributes.containsKey('money')) {
      balance = _user!.attributes['money'].toString();
    }

    return ListView(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade100,
                backgroundImage: _user!.avatarUrl != null ? NetworkImage(_user!.avatarUrl!) : null,
                child: _user!.avatarUrl == null
                    ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (_user!.groups.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    buildUserBadges(_user!.groups),
                  ]
                ],
              ),
              const SizedBox(height: 4),
              Text('@${_user!.username}', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              
              // 余额信息牌
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.thumb_up, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    const Text('0', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Text('$balance XSD', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        _buildSectionTitle('论坛交流'),
        _buildMenuGroup([
          _MenuAction(icon: Icons.article_outlined, title: '发布的主题', color: Colors.blue, onTap: () => _navigateToActivity('发布的主题', 'discussions')),
          _MenuAction(icon: Icons.chat_bubble_outline, title: '我的回复', color: Colors.lightBlue, onTap: () => _navigateToActivity('我的回复', 'posts')),
        ]),

        const SizedBox(height: 12),
        _buildSectionTitle('个人记录'),
        _buildMenuGroup([
          // [核心修改]：将“打赏记录”替换为“积分记录”，并指向全新的 activityType: money-log
          _MenuAction(icon: Icons.payments_outlined, title: '积分记录', color: Colors.amber, onTap: () => _navigateToActivity('积分记录', 'money-log')),
          _MenuAction(icon: Icons.warning_amber_rounded, title: '站务警告', color: Colors.red, onTap: () => _navigateToActivity('站务警告', 'warnings')),
        ]),

        const SizedBox(height: 12),
        _buildSectionTitle('系统设置'),
        _buildMenuGroup([
          _MenuAction(icon: Icons.settings_outlined, title: '账号设置', color: Colors.grey.shade700, onTap: () {}),
          _MenuAction(icon: Icons.exit_to_app, title: '退出登录', color: Colors.red, onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                title: const Text('退出登录'),
                content: const Text('确定要注销当前账号吗？'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(ctx); _logout(); }, child: const Text('确定')),
                ],
              )
            );
          }),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
    );
  }

  Widget _buildMenuGroup(List<_MenuAction> actions) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: actions.asMap().entries.map((entry) {
          final int idx = entry.key;
          final _MenuAction action = entry.value;
          return Column(
            children: [
              ListTile(
                leading: Icon(action.icon, color: action.color, size: 22),
                title: Text(action.title, style: TextStyle(fontSize: 15, color: action.title == '退出登录' ? Colors.red : Colors.black87)),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                onTap: action.onTap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              if (idx < actions.length - 1)
                const Divider(height: 1, thickness: 0.5, indent: 52),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MenuAction {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  _MenuAction({required this.icon, required this.title, required this.color, required this.onTap});
}
