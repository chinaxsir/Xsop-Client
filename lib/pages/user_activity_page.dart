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
  String _customEmptyMessage = '空空如也';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Map<String, dynamic>> _robustFetch(List<String> endpoints, Map<String, dynamic> query, String includes) async {
    for (final ep in endpoints) {
      try {
        final q = Map<String, dynamic>.from(query);
        q['include'] = includes;
        return await widget.api.getDynamicList(ep, queryParameters: q);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) continue; 
        if (e.response?.statusCode == 400 || e.response?.statusCode == 500) {
           try {
             return await widget.api.getDynamicList(ep, queryParameters: query);
           } catch (_) {
             try {
               return await widget.api.getDynamicList(ep);
             } catch (_) { continue; }
           }
        }
      }
    }
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(requestOptions: RequestOptions(path: ''), statusCode: 404),
    );
  }

  void _filterAndSetData(Map<String, dynamic> res) {
    final rawItems = res['data'] as List<dynamic>? ?? [];
    _included = res['included'] as List<dynamic>? ?? [];

    // [核心修复：利用 filter[user] 一次性拉取用户所有的相关流水（发出和收到），并在本地剔除无关垃圾数据]
    if (widget.activityType == 'warnings') {
       _items = rawItems.where((i) => i['relationships']?['user']?['data']?['id']?.toString() == widget.user.id || i['relationships']?['addedByUser']?['data']?['id']?.toString() == widget.user.id).toList();
    } else if (widget.activityType == 'tips') {
       _items = rawItems.where((i) => i['relationships']?['recipient']?['data']?['id']?.toString() == widget.user.id || i['relationships']?['sender']?['data']?['id']?.toString() == widget.user.id).toList();
    } else {
       _items = rawItems;
    }
    
    // 如果没有数据抛异常由下层接管
    if (_items.isEmpty) {
        throw DioException(requestOptions: RequestOptions(path: ''), response: Response(requestOptions: RequestOptions(path: ''), statusCode: 404));
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      Map<String, dynamic> res;
      switch (widget.activityType) {
        case 'discussions':
          res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
          _customEmptyMessage = '该用户暂未发布任何主题。';
          _filterAndSetData(res);
          break;
        case 'posts':
          res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
          _customEmptyMessage = '该用户暂未发表任何回复。';
          _filterAndSetData(res);
          break;
        case 'warnings':
          res = await _robustFetch(['/api/warnings', '/api/user-warnings'], {'filter[user]': widget.user.id}, 'addedByUser,post,post.discussion');
          _customEmptyMessage = '该用户暂未收到任何警告。';
          _filterAndSetData(res);
          break;
        case 'tips':
          res = await _robustFetch(['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/money-transfers'], {'filter[user]': widget.user.id}, 'sender,recipient,post,post.discussion');
          _customEmptyMessage = '该用户暂无任何打赏记录。';
          _filterAndSetData(res);
          break;
        default:
          throw Exception('未知的活动类型');
      }
      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '权限不足：您无法查看此详情';
          } else {
             _error = '加载失败，请检查网络';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '解析数据发生异常'; _isLoading = false; });
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
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = _items[index];
        final type = item['type'];
        
        if (type == 'warnings') return _buildWarningItem(item);
        if (type == 'tips' || type == 'rewards' || type == 'money_transfers' || type == 'moneyHistory') return _buildTipItem(item);
        if (type == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item);
      },
    );
  }

  // [完美还原图 1] 站务警告专属卡片：浅灰色大背景、头像名字穿插排版
  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString();
    final addedByUser = _getIncluded('users', addedByUserId);
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '系统管理员';
    final adminAvatar = addedByUser?['attributes']?['avatarUrl'];

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '未知帖子';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '由于违反社区规定，已被管理员记录。';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '未知时间';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8), // 网页版淡淡的浅蓝灰底色
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: Colors.grey.shade200, backgroundImage: adminAvatar != null ? NetworkImage(adminAvatar) : null, child: adminAvatar == null ? Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.primary) : null),
              const SizedBox(width: 8),
              Text(adminName, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text('记$strikes分, $timeDisplay', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          
          const SizedBox(height: 16),
          Text('关联帖子', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                const Icon(Icons.chat, size: 18, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(discussionTitle, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          Text('警告', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
            child: Text(comment, style: const TextStyle(color: Colors.black87, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // [完美还原图 4 - 7] 打赏专属卡片：显示发送人/接收人头像与资金流向
  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final amount = attrs['amount']?.toString() ?? '0';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '未知时间';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '未知用户';
    final senderAvatar = sender?['attributes']?['avatarUrl'];

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '未知用户';
    final recipientAvatar = recipient?['attributes']?['avatarUrl'];

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final postNumber = post?['attributes']?['number'] ?? 1;

    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '未知主题';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200, width: 1.5), 
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 8,
            children: [
              Icon(Icons.card_giftcard, size: 16, color: Colors.grey.shade600),
              Text(timeDisplay, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(width: 8),
              Text('$amount XSD', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
              const SizedBox(width: 8),
              Text('来自', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: senderAvatar != null ? NetworkImage(senderAvatar) : null),
              Text(senderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              Text('给', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: recipientAvatar != null ? NetworkImage(recipientAvatar) : null),
              Text(recipientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('给「$discussionTitle」主题的 #$postNumber 帖', style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  // 渲染我的回复
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('在「$discussionTitle」主题中的回复', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(8)),
            child: HtmlWidget(attrs['contentHtml'] ?? attrs['content'] ?? '', textStyle: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5)),
          ),
          const SizedBox(height: 8),
          Text('回复于 $timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attrs['title'] ?? '记录详情', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text('发生于 $timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
