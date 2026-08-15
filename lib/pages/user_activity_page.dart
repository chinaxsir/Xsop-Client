// 文件位置: lib/pages/user_activity_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/pages/home_page.dart' show formatRelativeTime;

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

  // [精准嗅探引擎] 针对 Flarum Money 等特殊插件，只要 API 返回了 data 数组，就不再做严苛的本地丢弃
  Future<void> _fetchSpecialRecords(List<String> endpoints, Map<String, dynamic> query, String includes) async {
    List<dynamic> allData = [];
    List<dynamic> allIncluded = [];

    for (final ep in endpoints) {
      try {
        final q = Map<String, dynamic>.from(query);
        q['include'] = includes;
        final res = await widget.api.getDynamicList(ep, queryParameters: q);
        if (res['data'] != null && res['data'] is List) {
          allData.addAll(res['data']);
        }
        if (res['included'] != null && res['included'] is List) {
          allIncluded.addAll(res['included']);
        }
      } catch (_) {}
    }

    // 去重
    final Map<String, dynamic> uniqueData = {};
    for (var item in allData) {
      if (item != null && item['id'] != null) uniqueData[item['id'].toString()] = item;
    }
    
    final Map<String, dynamic> uniqueIncluded = {};
    for (var item in allIncluded) {
      if (item != null && item['id'] != null && item['type'] != null) {
        uniqueIncluded['${item['type']}_${item['id']}'] = item;
      }
    }

    _included = uniqueIncluded.values.toList();
    _items = uniqueData.values.toList(); // 移除严苛的本地拦截，相信服务端的返回
    
    _items.sort((a, b) {
      final timeA = a['attributes']?['createdAt'];
      final timeB = b['attributes']?['createdAt'];
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return DateTime.parse(timeB).compareTo(DateTime.parse(timeA));
    });
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      if (widget.activityType == 'discussions') {
        final res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '该用户暂未发布任何主题。';
      } else if (widget.activityType == 'posts') {
        final res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '该用户暂无回帖记录。';
      } else if (widget.activityType == 'warnings') {
        await _fetchSpecialRecords(['/api/warnings'], {'filter[user]': widget.user.id}, 'addedByUser,post,post.discussion');
        _customEmptyMessage = '该用户暂未收到任何站务警告。';
      } else if (widget.activityType == 'tips') {
        // [修复核心] 加入 /api/moneyHistory 等 Flarum Money 插件常用接口
        await _fetchSpecialRecords(['/api/tips', '/api/moneyHistory', '/api/money-transfers', '/api/transactions'], {'filter[user]': widget.user.id}, 'sender,recipient,post,post.discussion');
        _customEmptyMessage = '该用户暂无打赏或财富变动记录。';
      }

      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '权限不足：您无法查看此记录。';
          } else {
             _error = '网络异常，请下拉重试。';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '数据解析异常。'; _isLoading = false; });
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
            FilledButton.tonal(onPressed: _loadData, child: const Text('重试')),
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
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
    final adminAvatar = addedByUser?['attributes']?['avatarUrl'];

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '违反社区规定';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.lightBlue.shade200, width: 2), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('站务警告', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          Divider(height: 24, color: Colors.grey.shade200),
          Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: Colors.grey.shade200, backgroundImage: adminAvatar != null ? NetworkImage(adminAvatar) : null, child: adminAvatar == null ? const Icon(Icons.person, size: 14) : null),
              const SizedBox(width: 8),
              Text(adminName, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),
          Text('记 $strikes 分, $timeDisplay', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 16),
          Text('警告内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
            child: Text(comment, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '系统/匿名';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '用户';

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '未知主题';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade300, width: 1.5), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Icon(Icons.card_giftcard, size: 16, color: Colors.grey.shade600),
              Text(timeDisplay, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(width: 4),
              Text('$amount XSD', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
              Text('来自', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              Text(senderName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
              Text('给', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              Text(recipientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 10),
          Text('给「$discussionTitle」主题的回复', style: const TextStyle(color: Colors.black87, fontSize: 14)),
        ],
      ),
    );
  }

  // [重点修复：完美恢复回帖记录的原始形态（保留上方红框标题，显示下方真实回帖内容）]
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 还原红框：带有标题引用的头部
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '在「', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  TextSpan(text: discussionTitle, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                  const TextSpan(text: '」主题中的回复', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                ],
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // 还原蓝框：真实的 HTML 回帖内容
          Padding(
            padding: const EdgeInsets.all(16),
            child: HtmlWidget(attrs['contentHtml'] ?? attrs['content'] ?? '', textStyle: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.6)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text('回复于 $timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ),
        ],
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
          Text(attrs['title'] ?? '活动记录', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
