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
  String _customEmptyMessage = '当前业务项下暂无记录流水。';

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

  // [无差别穿透过滤引擎] 彻底击碎各插件的命名壁垒
  bool _isItemRelatedToUser(Map<String, dynamic> item) {
    final userId = widget.user.id;
    final rels = item['relationships'] ?? {};
    final attrs = item['attributes'] ?? {};

    // 扫描所有深层关联节点
    for (var val in rels.values) {
      if (val is Map && val['data'] is Map) {
        if (val['data']['id'].toString() == userId) return true;
      }
      if (val is Map && val['data'] is List) {
        for (var v in val['data']) {
          if (v is Map && v['id'].toString() == userId) return true;
        }
      }
    }
    
    // 扫描所有显式暴露的属性节点
    if (attrs.values.any((v) => v.toString() == userId)) return true;
    
    return false;
  }

  void _filterAndSetData(Map<String, dynamic> res) {
    final rawItems = res['data'] as List<dynamic>? ?? [];
    _included = res['included'] as List<dynamic>? ?? [];

    if (widget.activityType == 'discussions' || widget.activityType == 'posts') {
       _items = rawItems;
    } else {
       // 采用智能匹配：只要发现该笔流水有你的印记，立刻展示
       _items = rawItems.where((i) => _isItemRelatedToUser(i as Map<String, dynamic>)).toList();
    }
    
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
          _customEmptyMessage = '该系统实体暂未建立任何主题档案。';
          _filterAndSetData(res);
          break;
        case 'posts':
          res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
          _customEmptyMessage = '该系统实体暂无交互回复明细。';
          _filterAndSetData(res);
          break;
        case 'warnings':
          res = await _robustFetch(['/api/warnings', '/api/user-warnings'], {'filter[user]': widget.user.id}, 'addedByUser,post,post.discussion');
          _customEmptyMessage = '核查完毕：该实体名下暂无站务违规处理记录。';
          _filterAndSetData(res);
          break;
        case 'tips':
          res = await _robustFetch(['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/money-transfers'], {'filter[user]': widget.user.id}, 'sender,recipient,post,post.discussion');
          _customEmptyMessage = '核查完毕：该实体名下暂无资产流通或打赏流水。';
          _filterAndSetData(res);
          break;
        default:
          throw Exception('未知的业务映射流');
      }
      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '系统校验驳回：当前权限配置不满足查阅要求';
          } else {
             _error = '远端服务异常，请核对网络通信状态';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '本地引擎反序列化失败'; _isLoading = false; });
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
            FilledButton.tonal(onPressed: _loadData, child: const Text('重试通信链接')),
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
    final discussionTitle = discussion?['attributes']?['title'] ?? '缺失关联凭证';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '基于安全条例审计下发。';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '业务时间缺失';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8), 
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
          Text('记务考核：$strikes分 | 归档：$timeDisplay', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          
          const SizedBox(height: 16),
          Text('关联业务实体', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
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
          Text('行政批注内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
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

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final amount = attrs['amount']?.toString() ?? '0';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '业务时间缺失';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '匿名实体';
    final senderAvatar = sender?['attributes']?['avatarUrl'];

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '匿名实体';
    final recipientAvatar = recipient?['attributes']?['avatarUrl'];

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final postNumber = post?['attributes']?['number'] ?? 1;

    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '缺失关联项';

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
              Text('汇出方', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: senderAvatar != null ? NetworkImage(senderAvatar) : null),
              Text(senderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              Text('注资于', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: recipientAvatar != null ? NetworkImage(recipientAvatar) : null),
              Text(recipientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('对实体档案「$discussionTitle」项下的 #$postNumber 记录发起支持', style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    String discussionTitle = '系统核心配置实体';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '系统核心配置实体';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('于「$discussionTitle」业务项下进行交互批注', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(8)),
            child: HtmlWidget(attrs['contentHtml'] ?? attrs['content'] ?? '', textStyle: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5)),
          ),
          const SizedBox(height: 8),
          Text('归档日志：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
          Text(attrs['title'] ?? '核心交互项记录', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text('记录产生周期：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
