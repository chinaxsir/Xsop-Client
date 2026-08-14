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

  // [暴力容错引擎] 自动尝试带有完整 Include 的 API 路径，如果遭遇 400 则自动降级重试并在本地进行数据清洗。
  Future<Map<String, dynamic>> _robustFetch(List<String> endpoints, Map<String, dynamic> query, String includes) async {
    for (final ep in endpoints) {
      try {
        final q = Map<String, dynamic>.from(query);
        q['include'] = includes;
        return await widget.api.getDynamicList(ep, queryParameters: q);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) continue; 
        if (e.response?.statusCode == 400 || e.response?.statusCode == 500) {
           // 如果服务器不支持某些关联或过滤参数，去掉复杂参数保底重试
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
    // 全部失败则抛出 404，由外层接管展示完美的“空数据”提示
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(requestOptions: RequestOptions(path: ''), statusCode: 404),
    );
  }

  void _filterAndSetData(Map<String, dynamic> res) {
    final rawItems = res['data'] as List<dynamic>? ?? [];
    _included = res['included'] as List<dynamic>? ?? [];

    // 本地终极清洗：确保就算服务器忽略了过滤参数，客户端依然只显示正确的数据
    if (widget.activityType == 'warnings_sent') {
       _items = rawItems.where((i) => i['relationships']?['addedByUser']?['data']?['id']?.toString() == widget.user.id).toList();
    } else if (widget.activityType == 'warnings_received') {
       _items = rawItems.where((i) => i['relationships']?['user']?['data']?['id']?.toString() == widget.user.id).toList();
    } else if (widget.activityType == 'tips_sent') {
       _items = rawItems.where((i) => i['relationships']?['sender']?['data']?['id']?.toString() == widget.user.id).toList();
    } else if (widget.activityType == 'tips_received') {
       _items = rawItems.where((i) => i['relationships']?['recipient']?['data']?['id']?.toString() == widget.user.id).toList();
    } else {
       _items = rawItems;
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
          break;
        case 'posts':
          res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
          _customEmptyMessage = '该用户暂未发表任何回复。';
          break;
        case 'warnings_received':
          res = await _robustFetch(['/api/warnings', '/api/user-warnings'], {'filter[user]': widget.user.id}, 'addedByUser,post,post.discussion');
          _customEmptyMessage = '该用户暂未收到任何警告。';
          break;
        case 'warnings_sent':
          res = await _robustFetch(['/api/warnings', '/api/user-warnings'], {'filter[addedByUser]': widget.user.id}, 'user,post,post.discussion');
          _customEmptyMessage = '该用户暂未发出任何警告。';
          break;
        case 'tips_received':
          res = await _robustFetch(['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/money-transfers'], {'filter[recipient]': widget.user.id}, 'sender,recipient,post,post.discussion');
          _customEmptyMessage = '暂无收到的打赏记录。';
          break;
        case 'tips_sent':
          res = await _robustFetch(['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/money-transfers'], {'filter[sender]': widget.user.id}, 'sender,recipient,post,post.discussion');
          _customEmptyMessage = '暂无发出的打赏记录。';
          break;
        default:
          throw Exception('未知的活动类型');
      }
      
      if (mounted) {
        setState(() {
          _filterAndSetData(res);
          _isLoading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; // 优雅空占位
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

  // 从 included 中快速捞取关联数据
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
    
    // 完美复刻网页版空数据占位符
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
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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

  // [完美还原图 1] 站务警告专属精美卡片
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.lightBlue.shade200, width: 2), // 网页版蓝色描边
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('站务警告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          Divider(height: 24, color: Colors.grey.shade200),
          Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: Colors.grey.shade200, backgroundImage: adminAvatar != null ? NetworkImage(adminAvatar) : null, child: adminAvatar == null ? const Icon(Icons.person, size: 14) : null),
              const SizedBox(width: 8),
              Text(adminName, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),
          Text('记$strikes分, $timeDisplay', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 16),
          
          Text('关联帖子', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                const Icon(Icons.chat, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(discussionTitle, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text('警告', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)),
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

  // [完美还原图 4 & 图 7] 打赏专属精美卡片（支持头像穿插排版）
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.blue.shade300, width: 1.5), // 网页版蓝色浅描边
        borderRadius: BorderRadius.circular(4),
      ),
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
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: senderAvatar != null ? NetworkImage(senderAvatar) : null),
              Text(senderName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
              Text('给', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: recipientAvatar != null ? NetworkImage(recipientAvatar) : null),
              Text(recipientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 10),
          Text('给「$discussionTitle」主题的 #$postNumber 帖', style: const TextStyle(color: Colors.black87, fontSize: 14)),
        ],
      ),
    );
  }

  // [修复图 2 问题] 动态获取回复所在的真实帖子标题
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

  // 兜底基础卡片（防止主题数据异常）
  Widget _buildDefaultItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
