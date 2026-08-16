// 文件位置: lib/pages/user_profile_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/pages/user_activity_page.dart';

class UserProfilePage extends StatefulWidget {
  final FlarumUser user;
  final ApiClient api;

  const UserProfilePage({
    super.key,
    required this.user,
    required this.api,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isCurrentUser = false;
  late FlarumUser _currentUserData;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _currentUserData = widget.user;
    _checkIfCurrentUser();
    _refreshUserData(); 
  }

  Future<void> _checkIfCurrentUser() async {
    final currentUserId = await widget.api.getUserId();
    if (mounted) {
      setState(() {
        _isCurrentUser = currentUserId != null && currentUserId.toString() == _currentUserData.id;
      });
    }
  }

  Future<void> _refreshUserData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final res = await widget.api.getUser(int.parse(_currentUserData.id));
      if (mounted) {
        setState(() {
          _currentUserData = parseUser(res, widget.api.baseUrl);
        });
      }
    } catch (e) {
      // 忽略网络波动，保持旧数据展示
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _navigateToActivity(String title, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserActivityPage(
          api: widget.api,
          user: _currentUserData,
          title: title,
          activityType: type,
        ),
      ),
    );
  }

  // 严格采用 Flarum 官方“站务警告”逻辑
  Future<void> _showAdminWarnDialog() async {
    final strikesCtrl = TextEditingController(text: '1');
    final publicCtrl = TextEditingController();
    final privateCtrl = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text('警告 ${_currentUserData.username}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('严重程度：记几分？', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: strikesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 16),
                const Text('用户批注（对用户可见）', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: publicCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
                const SizedBox(height: 16),
                const Text('管理员备注（仅管理员可见）', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: privateCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.grey))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: isSubmitting ? null : () async {
                setStateDialog(() => isSubmitting = true);
                try {
                  await widget.api.warnUser(
                    int.parse(_currentUserData.id),
                    strikes: int.tryParse(strikesCtrl.text) ?? 0,
                    publicComment: publicCtrl.text.trim(),
                    privateComment: privateCtrl.text.trim(),
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('警告已发送')));
                  }
                } on DioException catch (e) {
                  String errMsg = '操作失败：权限不足';
                  if (e.response?.statusCode == 403) errMsg = '权限不足：您无权执行此操作';
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
                } finally {
                  if (mounted) setStateDialog(() => isSubmitting = false);
                }
              },
              child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('发送警告'),
            )
          ],
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('个人中心', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (!_isCurrentUser)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              onSelected: (val) {
                if (val == 'warn') _showAdminWarnDialog();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'warn', child: Row(children: [Icon(Icons.warning_amber, color: Colors.redAccent, size: 20), SizedBox(width: 8), Text('站务警告', style: TextStyle(color: Colors.redAccent))])),
              ],
            )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUserData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.only(top: 24, bottom: 32),
                child: Column(
                  children: [
                    _buildAvatar(),
                    const SizedBox(height: 16),
                    _buildUserInfo(),
                    const SizedBox(height: 16),
                    _buildAssetPill(),
                  ],
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                child: Column(
                  children: [
                    _buildSectionGroup(
                      title: '论坛交流',
                      items: [
                        _MenuItem(icon: Icons.article_outlined, color: Colors.blueAccent, title: '发布的主题', onTap: () => _navigateToActivity('发布的主题', 'discussions')),
                        _MenuItem(icon: Icons.chat_bubble_outline, color: Colors.lightBlue, title: '我的回复', onTap: () => _navigateToActivity('我的回复', 'posts')),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // [核心修复：已经取消了多余的资金明细，仅保留 Flarum 核心的打赏记录和警告]
                    _buildSectionGroup(
                      title: '个人记录',
                      items: [
                        _MenuItem(icon: Icons.card_giftcard, color: Colors.orange, title: '打赏记录', onTap: () => _navigateToActivity('打赏记录', 'tips')),
                        _MenuItem(icon: Icons.warning_amber_rounded, color: Colors.red, title: '站务警告', onTap: () => _navigateToActivity('站务警告', 'warnings')),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (_isCurrentUser)
                      _buildSectionGroup(
                        title: '系统设置',
                        items: [
                          _MenuItem(icon: Icons.settings_outlined, color: Colors.grey.shade700, title: '账号设置', onTap: () {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请前往网页版进行账号设置')));
                          }),
                          _MenuItem(
                            icon: Icons.exit_to_app, 
                            color: Colors.red, 
                            title: '退出登录', 
                            textColor: Colors.red,
                            hideArrow: true,
                            onTap: () async {
                              await widget.api.logout();
                              if (mounted) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            },
                          ),
                        ],
                      ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final name = _currentUserData.displayName.isNotEmpty ? _currentUserData.displayName : _currentUserData.username;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: 46,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: _currentUserData.avatarUrl != null ? NetworkImage(_currentUserData.avatarUrl!) : null,
      child: _currentUserData.avatarUrl == null
          ? Text(letter, style: TextStyle(fontSize: 32, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))
          : null,
    );
  }

  Widget _buildUserInfo() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _currentUserData.displayName.isNotEmpty ? _currentUserData.displayName : _currentUserData.username,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            if (_currentUserData.groups.isNotEmpty) ...[
              const SizedBox(width: 8),
              buildUserBadges(_currentUserData.groups),
            ]
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '@${_currentUserData.username}',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildAssetPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4A4A4A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.thumb_up, size: 14, color: Colors.orangeAccent),
          const SizedBox(width: 4),
          Text(_currentUserData.likesReceived, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Text('${_currentUserData.money} XSD', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSectionGroup({required String title, required List<_MenuItem> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: List.generate(items.length, (index) {
              final item = items[index];
              return Column(
                children: [
                  ListTile(
                    onTap: item.onTap,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Icon(item.icon, color: item.color, size: 24),
                    title: Text(item.title, style: TextStyle(fontSize: 15, color: item.textColor ?? Colors.black87, fontWeight: FontWeight.w500)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.trailingText != null)
                          Text(item.trailingText!, style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                        if (item.trailingText != null && !item.hideArrow)
                          const SizedBox(width: 8),
                        if (!item.hideArrow)
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                  if (index < items.length - 1)
                    Divider(height: 1, thickness: 0.5, color: Colors.grey.shade200, indent: 56),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color color;
  final String title;
  final String? trailingText;
  final Color? textColor;
  final bool hideArrow;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.color,
    required this.title,
    this.trailingText,
    this.textColor,
    this.hideArrow = false,
    required this.onTap,
  });
}
