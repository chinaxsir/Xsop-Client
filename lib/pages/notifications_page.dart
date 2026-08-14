// 文件位置: lib/pages/notifications_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/pages/home_page.dart' show formatRelativeTime;

class NotificationsPage extends StatefulWidget {
  final ApiClient api;
  const NotificationsPage({super.key, required this.api});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _notifications = [];
  List<dynamic> _included = []; // 引入关联数据池
  
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _loadData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); 
    WidgetsBinding.instance.removeObserver(this); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData(silent: true);
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _error = null; });
    
    try {
      final res = await widget.api.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = res['data'] as List<dynamic>? ?? [];
          _included = res['included'] as List<dynamic>? ?? [];
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() { _error = '数据同步异常，请检视网络状态'; _isLoading = false; });
    }
  }

  // [动态匹配引擎：从 included 池中捕获触发动作的用户信息]
  Map<String, dynamic>? _getFromUser(Map<String, dynamic> notif) {
    final fromUserId = notif['relationships']?['fromUser']?['data']?['id']?.toString();
    if (fromUserId == null) return null;
    try {
      return _included.firstWhere((e) => e['type'] == 'users' && e['id'].toString() == fromUserId);
    } catch (_) {
      return null;
    }
  }

  // [官方语言格式化引擎：将系统的动作代码转化为官方描述模板]
  String _formatNotificationContent(String contentType, String? fromUserName) {
    final name = fromUserName ?? '系统';
    switch (contentType) {
      case 'warning':
        return '系统已下发来自 $name 的站务违规处理通报';
      case 'postLiked':
        return '$name 肯定并点赞了您的发言';
      case 'postMentioned':
        return '$name 在交互记录中提及了您';
      case 'newPost':
        return '$name 对您的主题进行了跟进回复';
      case 'discussionRenamed':
        return '$name 对关联主题的名称进行了修订';
      default:
        return '接收到新的系统事务状态变动 ($contentType)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('通知中心', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: () => _loadData(), child: const Text('重新建立链接')),
          ],
        ),
      );
    }
    if (_notifications.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('当前业务列表暂无新通知', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final attrs = notif['attributes'] ?? {};
        final contentType = attrs['contentType'] ?? '系统事务';
        final timeStr = attrs['createdAt'];
        
        final fromUser = _getFromUser(notif);
        final fromUserName = fromUser?['attributes']?['displayName'] ?? fromUser?['attributes']?['username'];
        final fromUserAvatar = fromUser?['attributes']?['avatarUrl'];
        
        final displayTitle = _formatNotificationContent(contentType, fromUserName);
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            backgroundImage: fromUserAvatar != null ? NetworkImage(fromUserAvatar) : null,
            child: fromUserAvatar == null 
              ? Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary, size: 20)
              : null,
          ),
          title: Text(displayTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
          subtitle: timeStr != null 
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(formatRelativeTime(DateTime.parse(timeStr)), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                )
              : null,
          onTap: () {
            // [预留扩展接口] 针对各项事务的细则进行跳转
          },
        );
      },
    );
  }
}
