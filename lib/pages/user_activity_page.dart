// 文件位置: lib/pages/user_activity_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/pages/home_page.dart' show formatRelativeTime;
import 'package:xsop_forum/pages/discussion_detail_page.dart';

class UserActivityPage extends StatefulWidget {
  final ApiClient api;
  final FlarumUser user;
  final String title;
  final String activityType;

  const UserActivityPage({
    super.key,
    required this.api,
    required this.user,
    required this.title,
    required this.activityType,
  });

  @override
  State<UserActivityPage> createState() => _UserActivityPageState();
}

class _UserActivityPageState extends State<UserActivityPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _items = [];
  List<dynamic> _included = [];
  String _customEmptyMessage = '暂无相关记录。';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Map<String, dynamic>> _safeFetch(String endpoint, Map<String, dynamic> query) async {
    try {
      return await widget.api.getDynamicList(endpoint, queryParameters: query);
    } catch (e) {
      return {'data': []}; 
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      if (widget.activityType == 'discussions') {
        final res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '未发布任何主题。';
      } else if (widget.activityType == 'posts') {
        final res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '无回复记录。';
      } else if (widget.activityType == 'warnings') {
        final res = await _safeFetch('/api/warnings', {'filter[user]': widget.user.id, 'include': 'addedByUser,post'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '暂无站务警告记录。';
      } else if (widget.activityType == 'tips') {
        final r1 = await _safeFetch('/api/tips', {'filter[user]': widget.user.id, 'include': 'sender,recipient,post'});
        final r2 = await _safeFetch('/api/moneyHistory', {'filter[user]': widget.user.id});
        
        List<dynamic> combined = [];
        combined.addAll(r1['data'] ?? []);
        combined.addAll(r2['data'] ?? []);
        
        _included.addAll(r1['included'] ?? []);
        _included.addAll(r2['included'] ?? []);
        _items = combined;
        _customEmptyMessage = '暂无打赏或资产流水。';
      }

      if (_items.isNotEmpty) {
        _items.sort((a, b) {
          final timeA = a['attributes']?['createdAt'];
          final timeB = b['attributes']?['createdAt'];
          if (timeA == null) return 1;
          if (timeB == null) return -1;
          return DateTime.parse(timeB).compareTo(DateTime.parse(timeA));
        });
      }

      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '权限不足：无法查阅该数据流。';
          } else {
             _error = '远端系统服务异常。';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '本地引擎解析拦截。'; _isLoading = false; });
    }
  }

  Map<String, dynamic>? _getIncluded(String type, String? id) {
    if (id == null) return null;
    try {
      return _included.firstWhere((e) => e['type'] == type && e['id'].toString() == id);
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
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
              child: const Text('重试通信')
            ),
          ],
        ),
      );
    }
    
    if (_items.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(_customEmptyMessage, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      padding: const EdgeInsets.symmetric(vertical: 12),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = _items[index];
        final type = item['type'];
        
        if (type == 'warnings') return _buildWarningItem(item);
        if (type == 'tips' || type == 'moneyHistory' || type == 'money_transfers' || type == 'transactions') return _buildTipItem(item);
        if (type == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item);
      },
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString();
    final addedByUser = _getIncluded('users', addedByUserId);
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '管理员';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '由于违规操作被处理。';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '时间缺失';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade400, size: 18),
              const SizedBox(width: 8),
              Text('警告记 $strikes 分', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Text(comment, style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('由 $adminName 下发于 $timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '未知';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '账户体系';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '关联对象';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text('打赏 $amount XSD', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Text('流向记录：$senderName 给 $recipientName', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('生成于 $timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    String discussionTitle = '未知主题';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '未知主题';
    }

    return InkWell(
      onTap: () {
        if (discussionId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DiscussionDetailPage(
                api: widget.api,
                // [核心修复点] 补全所有缺失的必需参数：id, title, commentCount, 和 createdAt
                discussion: Discussion(
                  id: discussionId, 
                  title: discussionTitle,
                  commentCount: 0, 
                  createdAt: timeStr != null ? DateTime.tryParse(timeStr) ?? DateTime.now() : DateTime.now(),
                ),
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.red.shade100, width: 2), 
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '在「', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  TextSpan(text: discussionTitle, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                  const TextSpan(text: '」主题中的回复', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                ],
              ),
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text('回复于 $timeDisplay (点击可跳转)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attrs['title'] ?? '基础日志', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
