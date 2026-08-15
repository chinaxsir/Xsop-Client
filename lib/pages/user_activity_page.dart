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

  // [无畏降级探针] 先带 include 请求，遇到服务器 400（比如不兼容的插件结构）自动去掉 include 进行纯净版保底请求
  Future<Map<String, dynamic>> _safeFetch(String endpoint, Map<String, dynamic> query) async {
    try {
      return await widget.api.getDynamicList(endpoint, queryParameters: query);
    } catch (e) {
      if (e is DioException && (e.response?.statusCode == 400 || e.response?.statusCode == 500)) {
         try {
           final q = Map<String, dynamic>.from(query)..remove('include');
           return await widget.api.getDynamicList(endpoint, queryParameters: q);
         } catch (_) {}
      }
      return {'data': []}; 
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    
    try {
      final uid = widget.user.id;
      
      if (widget.activityType == 'discussions') {
        final res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '该账号暂未发布任何主题。';
      } 
      else if (widget.activityType == 'posts') {
        // [极度安全的回复提取机制：强制包含 user 用于本地二次拦截防串号]
        final res = await _safeFetch('/api/posts', {
            'filter[user]': uid, 
            'filter[type]': 'comment',
            'include': 'discussion,user'
        });
        
        final rawPosts = res['data'] as List<dynamic>? ?? [];
        _items = rawPosts.where((p) {
           // 本地强制拦截：帖子归属人必须是当前正在看的这个 userId！
           final relUserId = p['relationships']?['user']?['data']?['id']?.toString();
           if (relUserId != null && relUserId != uid) return false;
           return true; 
        }).toList();
        
        _included = res['included'] ?? [];
        _customEmptyMessage = '该账号无回复记录。';
      } 
      else if (widget.activityType == 'warnings') {
        // [修复死循环：把所有可能的 Flarum 警告记录全部收拢]
        final res1 = await _safeFetch('/api/warnings', {'filter[user]': uid, 'include': 'addedByUser,post'});
        final res2 = await _safeFetch('/api/users/$uid/warnings', {'include': 'addedByUser,post'});
        final res3 = await _safeFetch('/api/user-warnings', {'filter[user]': uid});
        
        final Map<String, dynamic> uniqueMap = {};
        for(var i in [...(res1['data'] ?? []), ...(res2['data'] ?? []), ...(res3['data'] ?? [])]) {
          if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
        }
        _items = uniqueMap.values.toList();
        _included = [...(res1['included'] ?? []), ...(res2['included'] ?? []), ...(res3['included'] ?? [])];
        _customEmptyMessage = '暂无任何站务违规记录。';
      } 
      else if (widget.activityType == 'tips') {
        // 请求常规的基于贴子的打赏
        final res1 = await _safeFetch('/api/tips', {'filter[user]': uid, 'include': 'sender,recipient,post'});
        final res2 = await _safeFetch('/api/users/$uid/tips', {'include': 'sender,recipient,post'});
        
        final Map<String, dynamic> uniqueMap = {};
        for(var i in [...(res1['data'] ?? []), ...(res2['data'] ?? [])]) {
          if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
        }
        _items = uniqueMap.values.toList();
        _included = [...(res1['included'] ?? []), ...(res2['included'] ?? [])];
        _customEmptyMessage = '暂无打赏记录。';
      }
      else if (widget.activityType == 'money') {
        // [新增需求：XSD 资金流水与消费记录]
        final res1 = await _safeFetch('/api/moneyHistory', {'filter[user]': uid});
        final res2 = await _safeFetch('/api/users/$uid/moneyHistory', {});
        final res3 = await _safeFetch('/api/money-transfers', {'filter[user]': uid});
        
        final Map<String, dynamic> uniqueMap = {};
        for(var i in [...(res1['data'] ?? []), ...(res2['data'] ?? []), ...(res3['data'] ?? [])]) {
          if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
        }
        _items = uniqueMap.values.toList();
        _included = [...(res1['included'] ?? []), ...(res2['included'] ?? []), ...(res3['included'] ?? [])];
        _customEmptyMessage = '暂无资金变动明细。';
      }

      // [核心修复点：极其保守的容错排序，只要 DateTime 解析失败，全部当成时间 0 处理，杜绝转圈死循环！]
      if (_items.isNotEmpty) {
        _items.sort((a, b) {
          final timeAStr = a['attributes']?['createdAt']?.toString();
          final timeBStr = b['attributes']?['createdAt']?.toString();
          
          DateTime dateA = DateTime.fromMillisecondsSinceEpoch(0);
          DateTime dateB = DateTime.fromMillisecondsSinceEpoch(0);
          
          if (timeAStr != null) {
            try { dateA = DateTime.parse(timeAStr); } catch (_) {}
          }
          if (timeBStr != null) {
            try { dateB = DateTime.parse(timeBStr); } catch (_) {}
          }
          
          return dateB.compareTo(dateA);
        });
      }

      if (mounted) setState(() => _isLoading = false);
      
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is DioException) {
            if (e.response?.statusCode == 404) {
               _items = []; _error = null; 
            } else if (e.response?.statusCode == 403) {
               _error = '服务器拦截：无权查看这些数据。';
            } else {
               _error = '网络传输发生故障。';
            }
          } else {
             _error = '本地引擎发生故障：${e.toString()}';
          }
          _isLoading = false;
        });
      }
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
              child: const Text('重新加载数据')
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _items[index];
        final type = item['type'];
        
        if (type == 'warnings') return _buildWarningItem(item);
        if (type == 'tips' || type == 'post_tips') return _buildTipItem(item);
        if (type == 'moneyHistory' || type == 'money_transfers' || type == 'transactions') return _buildMoneyItem(item);
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
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '违规操作。';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '时间丢失';
    if (timeStr != null) {
      try {
        timeDisplay = formatRelativeTime(DateTime.parse(timeStr));
      } catch (_) {}
    }

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
          const SizedBox(height: 12),
          Text(comment, style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('处理人：$adminName  |  时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '未知';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '某位用户';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '楼主';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.orange.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Text('打赏 ($amount XSD)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text('记录：$senderName  →  $recipientName', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('打赏时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  // [全新组件：资金明细专用卡片，展现绿色账本风格]
  Widget _buildMoneyItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final desc = attrs['description']?.toString() ?? attrs['reason']?.toString() ?? '系统变动';
    
    final timeStr = attrs['createdAt']?.toString();
    String timeDisplay = '未知时间';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }
    
    final isIncome = !amount.startsWith('-');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.green.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet, size: 18, color: isIncome ? Colors.green : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text('资产流水', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Text('${isIncome ? '+' : ''}$amount XSD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.green : Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('事由：$desc', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('记账时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

    String discussionTitle = '帖子详情加载中...';
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
                discussion: Discussion(
                  id: discussionId, 
                  title: discussionTitle,
                  commentCount: 0, 
                  createdAt: DateTime.now(),
                  tags: const [], 
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
          color: Colors.white,
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
    final timeStr = attrs['createdAt']?.toString();
    String timeDisplay = '';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

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
