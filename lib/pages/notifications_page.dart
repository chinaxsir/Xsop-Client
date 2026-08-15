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
  List<dynamic> _included = []; 
  
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
      if (mounted && !silent) setState(() { _error = '数据同步异常，请下拉重试。'; _isLoading = false; });
    }
  }

  Map<String, dynamic>? _getIncluded(String type, String? id) {
    if (id == null) return null;
    try {
      return _included.firstWhere((e) => e['type'] == type && e['id'].toString() == id);
    } catch (_) { return null; }
  }

  // [图4/图5 修复点：动态提取警告实体里的积分与详细原因]
  String _formatNotificationContent(Map<String, dynamic> notif, String? fromUserName) {
    final contentType = notif['attributes']?['contentType'] ?? '';
    final name = fromUserName ?? '系统';
    
    if (contentType == 'warning') {
       final subjectId = notif['relationships']?['subject']?['data']?['id']?.toString();
       final warningObj = _getIncluded('warnings', subjectId);
       final strikes = warningObj?['attributes']?['strikes'] ?? 0;
       return '收到来自 $name 的警告并记 $strikes 分';
    } else if (contentType == 'postLiked') {
       return '$name 赞了您的帖子';
    } else if (contentType == 'postMentioned') {
       return '$name 提到了您';
    } else if (contentType == 'newPost') {
       return '$name 回复了您的主题';
    } else if (contentType == 'discussionRenamed') {
       return '$name 修改了主题标题';
    } else {
       return '收到一条新的 $contentType 事务通知';
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
            FilledButton.tonal(
              onPressed: () async {
                setState(() { _isLoading = true; _error = null; });
                await Future.delayed(const Duration(milliseconds: 400));
                _loadData();
              }, 
              child: const Text('重新连接')
            ),
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
                  Text('暂无新通知。', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
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
        final timeStr = attrs['createdAt'];
        
        final fromUser = _getIncluded('users', notif['relationships']?['fromUser']?['data']?['id']?.toString());
        final fromUserName = fromUser?['attributes']?['displayName'] ?? fromUser?['attributes']?['username'];
        final fromUserAvatar = fromUser?['attributes']?['avatarUrl'];
        
        final displayTitle = _formatNotificationContent(notif, fromUserName);
        
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
        );
      },
    );
  }
}
