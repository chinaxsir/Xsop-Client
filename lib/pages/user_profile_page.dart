// 文件位置: lib/pages/user_profile_page.dart

import 'package:flutter/material.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';

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

  @override
  void initState() {
    super.initState();
    _checkIfCurrentUser();
  }

  Future<void> _checkIfCurrentUser() async {
    final currentUserId = await widget.api.getUserId();
    if (mounted) {
      setState(() {
        _isCurrentUser = currentUserId != null && currentUserId.toString() == widget.user.id;
      });
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该功能界面正在开发中...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // iOS 风格的底层灰
      appBar: AppBar(
        title: const Text('个人中心', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          // 头部个人信息卡片
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
          
          // 列表区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
              child: Column(
                children: [
                  _buildSectionGroup(
                    title: '论坛交流',
                    items: [
                      _MenuItem(icon: Icons.article_outlined, color: Colors.blueAccent, title: '发布的主题', onTap: _showComingSoon),
                      _MenuItem(icon: Icons.chat_bubble_outline, color: Colors.lightBlue, title: '我的回复', onTap: _showComingSoon),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  _buildSectionGroup(
                    title: '个人资产',
                    items: [
                      _MenuItem(icon: Icons.thumb_up_alt_outlined, color: Colors.orange, title: '收到的点赞', trailingText: widget.user.likesReceived, onTap: _showComingSoon),
                      _MenuItem(icon: Icons.account_balance_wallet_outlined, color: Colors.amber, title: 'XSD 余额', trailingText: '${widget.user.money} XSD', onTap: _showComingSoon),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionGroup(
                    title: '打赏详情',
                    items: [
                      _MenuItem(icon: Icons.card_giftcard, color: Colors.redAccent, title: '收到的打赏', onTap: _showComingSoon),
                      _MenuItem(icon: Icons.outbox, color: Colors.pinkAccent, title: '发出的打赏', onTap: _showComingSoon),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionGroup(
                    title: '站务警告',
                    items: [
                      _MenuItem(icon: Icons.warning_amber_rounded, color: Colors.red, title: '收到的警告', onTap: _showComingSoon),
                      // 仅针对管理层或特定需求展示“发出的警告”
                      _MenuItem(icon: Icons.gavel, color: Colors.brown, title: '发出的警告', onTap: _showComingSoon),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 仅当前用户本人可见的设置项
                  if (_isCurrentUser)
                    _buildSectionGroup(
                      title: '系统设置',
                      items: [
                        _MenuItem(icon: Icons.settings_outlined, color: Colors.grey.shade700, title: '账号设置', onTap: _showComingSoon),
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
                  
                  const SizedBox(height: 40), // 底部留白
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建头像
  Widget _buildAvatar() {
    final name = widget.user.displayName.isNotEmpty ? widget.user.displayName : widget.user.username;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: 46,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: widget.user.avatarUrl != null ? NetworkImage(widget.user.avatarUrl!) : null,
      child: widget.user.avatarUrl == null
          ? Text(letter, style: TextStyle(fontSize: 32, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))
          : null,
    );
  }

  // 构建用户信息（昵称、用户名、徽章）
  Widget _buildUserInfo() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.user.displayName.isNotEmpty ? widget.user.displayName : widget.user.username,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            if (widget.user.groups.isNotEmpty) ...[
              const SizedBox(width: 8),
              buildUserBadges(widget.user.groups),
            ]
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '@${widget.user.username}',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // 构建资产胶囊（完美还原图片中的深色块 UI）
  Widget _buildAssetPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4A4A4A), // 深灰色底
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(widget.user.badgesCount, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          
          const Icon(Icons.thumb_up, size: 14, color: Colors.orangeAccent),
          const SizedBox(width: 4),
          Text(widget.user.likesReceived, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          
          Text('${widget.user.money} XSD', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // 构建分组卡片
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

// 菜单项数据模型
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
