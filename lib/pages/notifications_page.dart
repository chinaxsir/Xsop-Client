// 文件位置: lib/pages/notifications_page.dart

import 'dart:async'; // 引入定时器库
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
  
  // 声明定时器
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _loadData();
    
    // [核心修复 3：设置 15 秒的心跳轮询，当用户在该页面时，实现通知的实时同步]
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // 退出页面时立即销毁定时器，防止内存泄漏
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
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    
    try {
      final res = await widget.api.getNotifications();
      final data = res['data'] as List<dynamic>? ?? [];
      
      if (mounted) {
        setState(() {
          _notifications = data;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = '无法加载通知，请检查网络';
          _isLoading = false;
        });
      }
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
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
              onPressed: () => _loadData(),
              child: const Text('点击重试')
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
                  Text('暂无新通知', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
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
        final contentType = attrs['contentType'] ?? '系统通知';
        final timeStr = attrs['createdAt'];
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            child: Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary, size: 20),
          ),
          title: Text(contentType, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          subtitle: timeStr != null 
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(formatRelativeTime(DateTime.parse(timeStr)), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                )
              : null,
          onTap: () {
            // 点击可拓展相关操作
          },
        );
      },
    );
  }
}
