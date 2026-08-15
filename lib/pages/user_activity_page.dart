// 文件位置: lib/pages/user_activity_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
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
  String _customEmptyMessage = '经核查，系统未匹配到该实体名下的相关事务流水记录。';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool _isItemRelatedToUser(Map<String, dynamic> item) {
    final userId = widget.user.id;
    final rels = item['relationships'] ?? {};
    final attrs = item['attributes'] ?? {};

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
    if (attrs.values.any((v) => v.toString() == userId)) return true;
    return false;
  }

  // [全量聚合探针：通过交叉轮询不同的关联键值，彻底击破第三方插件的参数屏蔽现象]
  Future<void> _aggressiveFetch(List<String> endpoints, String includes) async {
    List<dynamic> allData = [];
    List<dynamic> allIncluded = [];
    final uid = widget.user.id;
    
    final queries = [
      {'filter[user]': uid, 'include': includes},
      {'filter[recipient]': uid, 'include': includes},
      {'filter[sender]': uid, 'include': includes},
      {'include': includes} 
    ];

    for (final ep in endpoints) {
      for (final q in queries) {
        try {
          final res = await widget.api.getDynamicList(ep, queryParameters: q);
          allData.addAll(res['data'] ?? []);
          allIncluded.addAll(res['included'] ?? []);
        } catch (_) {}
      }
    }
    
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
    _items = uniqueData.values.where((i) => _isItemRelatedToUser(i as Map<String, dynamic>)).toList();
    
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
        _customEmptyMessage = '该系统实体暂未建立任何核心事务档案。';
      } else if (widget.activityType == 'posts') {
        final res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id, 'include': 'discussion'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '该系统实体暂无相关的交互回应明细。';
      } else if (widget.activityType == 'warnings') {
        await _aggressiveFetch(['/api/warnings', '/api/user-warnings'], 'addedByUser,post,post.discussion');
        _customEmptyMessage = '审计系统核查完毕：该实体名下暂无站务违规处理记录。';
      } else if (widget.activityType == 'tips') {
        await _aggressiveFetch(['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/money-transfers', '/api/transactions'], 'sender,recipient,post,post.discussion');
        _customEmptyMessage = '审计系统核查完毕：该实体名下暂无任何资产流通或打赏流水。';
      } else {
        throw Exception('调用的业务流映射不存在');
      }

      if (_items.isEmpty) {
        _error = null; 
      }
      
      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '安全审计系统已拦截：当前鉴权配置不满足查阅要求。';
          } else {
             _error = '远端系统服务异常，请核对网络通信链路状态。';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '本地引擎在反序列化过程中触发异常拦截。'; _isLoading = false; });
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
              child: const Text('重新发起通信请求')
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
        if (type == 'tips' || type == 'rewards' || type == 'money_transfers' || type == 'moneyHistory' || type == 'transactions') return _buildTipItem(item);
        if (type == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item);
      },
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString();
    final addedByUser = _getIncluded('users', addedByUserId);
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '系统核心组件';
    final adminAvatar = addedByUser?['attributes']?['avatarUrl'];

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '缺失关联系统凭证';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '基于系统安全强制条例，审计处理下发完毕。';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '业务时间源缺失';

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
          Text('记务考核扣除：$strikes分 | 归档周期：$timeDisplay', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          
          const SizedBox(height: 16),
          Text('关联业务实体追溯', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
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
          Text('行政批注处理内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade600)),
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
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '业务时间源缺失';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '匿名接入实体';
    final senderAvatar = sender?['attributes']?['avatarUrl'];

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '匿名接收实体';
    final recipientAvatar = recipient?['attributes']?['avatarUrl'];

    final postId = item['relationships']?['post']?['data']?['id']?.toString();
    final post = _getIncluded('posts', postId);
    final postNumber = post?['attributes']?['number'] ?? 1;

    final discussionId = post?['relationships']?['discussion']?['data']?['id']?.toString();
    final discussion = _getIncluded('discussions', discussionId);
    final discussionTitle = discussion?['attributes']?['title'] ?? '系统丢失该关联追踪项';

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
              Text('出资方实体', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: senderAvatar != null ? NetworkImage(senderAvatar) : null),
              Text(senderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              Text('清算并注资于', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade200, backgroundImage: recipientAvatar != null ? NetworkImage(recipientAvatar) : null),
              Text(recipientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('对业务档案「$discussionTitle」关联下的第 $postNumber 项执行资金支持流转', style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  // [严格对齐图 3 需求：彻底移除冗余的 Markdown 富文本区块]
  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '日志时间异常';

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
          Text('在「$discussionTitle」业务项下登记了交互回复', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.blueAccent)),
          const SizedBox(height: 8),
          Text('系统日志归档于：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildDefaultItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '时间追踪标识异常';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attrs['title'] ?? '核心基础流水日志', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text('数据链生成追踪溯源：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
