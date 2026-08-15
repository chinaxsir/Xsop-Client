// 文件位置: lib/pages/user_activity_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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
  String _customEmptyMessage = '无相关功能记录。';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Map<String, dynamic>> _safeFetch(String endpoint, Map<String, dynamic> query) async {
    try {
      return await widget.api.getDynamicList(endpoint, queryParameters: query);
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404 || e.response?.statusCode == 405) return {'data': []};
        if (e.response?.statusCode == 400 || e.response?.statusCode == 500) {
           try {
             final q = Map<String, dynamic>.from(query)..remove('include');
             return await widget.api.getDynamicList(endpoint, queryParameters: q);
           } catch (_) {}
        }
      }
      return {'data': []}; 
    }
  }

  List<dynamic> _extractData(dynamic responseData) {
    if (responseData == null) return [];
    if (responseData is List) return responseData;
    if (responseData is Map && responseData.containsKey('id')) return [responseData];
    return [];
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    
    try {
      final uid = widget.user.id;
      final uname = widget.user.username;
      
      if (widget.activityType == 'discussions') {
        final res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:$uname'});
        _items = res['data'] ?? [];
        _included = res['included'] ?? [];
        _customEmptyMessage = '该账号暂未发布任何主题。';
      } 
      else if (widget.activityType == 'posts') {
        final r1 = await _safeFetch('/api/posts', {'filter[user]': uid, 'include': 'discussion,user'});
        final r2 = await _safeFetch('/api/posts', {'filter[author]': uname, 'include': 'discussion,user'});
        
        final Map<String, dynamic> uniqueMap = {};
        for(var i in [..._extractData(r1['data']), ..._extractData(r2['data'])]) {
          if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
        }
        
        _items = uniqueMap.values.where((p) {
           final type = p['attributes']?['contentType'];
           // [灰屏修复] 如果不是 comment（比如是管理员的删帖日志），我们放行，不强制拦截，让它显示为 DefaultItem
           if (type != null && type != 'comment' && type != 'discussionRenamed') {
              // do nothing, let it pass
           }
           
           final relUserId = p['relationships']?['user']?['data']?['id']?.toString();
           final attrUserId = p['attributes']?['userId']?.toString();
           
           // 必须属于当前被查看的人，否则就是串号的脏数据
           if (relUserId != null && relUserId != uid) return false;
           if (attrUserId != null && attrUserId != uid) return false;
           return true; 
        }).toList();
        
        _included = [..._extractData(r1['included']), ..._extractData(r2['included'])];
        _customEmptyMessage = '无相关功能记录。';
      } 
      else if (widget.activityType == 'warnings') {
        // [核心修复：完美应用您截图中的真实路由 /api/warnings/4]
        final endpoints = ['/api/warnings/$uid', '/api/warnings', '/api/users/$uid/warnings', '/api/user-warnings'];
        final Map<String, dynamic> uniqueMap = {};
        
        for (var ep in endpoints) {
          final r1 = await _safeFetch(ep, {'filter[user]': uid, 'include': 'addedByUser,post'});
          final r2 = await _safeFetch(ep, {'filter[user]': uid}); 
          final r3 = await _safeFetch(ep, {}); // 直接针对 /api/warnings/{id} 发起无参数请求
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data']), ..._extractData(r3['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(r1['included']));
          _included.addAll(_extractData(r2['included']));
          _included.addAll(_extractData(r3['included']));
        }
        
        // 【防遗漏】：如果上面都拉不到，拉取全部数据，手动筛选该用户的警告（这对系统管理员很有用）
        if (uniqueMap.isEmpty) {
           final rAll = await _safeFetch('/api/warnings', {'include': 'addedByUser,post'});
           for(var i in _extractData(rAll['data'])) {
              final relUserId = i['relationships']?['user']?['data']?['id']?.toString();
              if (relUserId == uid) {
                  uniqueMap[i['id'].toString()] = i;
              }
           }
           _included.addAll(_extractData(rAll['included']));
        }

        _items = uniqueMap.values.toList();
        _customEmptyMessage = '暂无符合权限校验的警告通报。';
      } 
      else if (widget.activityType == 'tips') {
        // [核心修复：引入基于前次截图的 /api/users/{id}/money-rewards 真实路由]
        final endpoints = [
          '/api/users/$uid/money-rewards', 
          '/api/tips', 
          '/api/rewards', 
          '/api/users/$uid/tips'
        ];
        final Map<String, dynamic> uniqueMap = {};
        
        for (var ep in endpoints) {
          final r1 = await _safeFetch(ep, {'filter[user]': uid, 'include': 'sender,recipient,post'});
          final r2 = await _safeFetch(ep, {'filter[user]': uid});
          final r3 = await _safeFetch(ep, {'filter[sender]': uid});
          final r4 = await _safeFetch(ep, {'filter[recipient]': uid});
          final r5 = await _safeFetch(ep, {}); 
          
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data']), ..._extractData(r3['data']), ..._extractData(r4['data']), ..._extractData(r5['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(r1['included']));
          _included.addAll(_extractData(r2['included']));
          _included.addAll(_extractData(r5['included']));
        }
        
        // 【防遗漏】：探测 User 属性绑定的各种扩展节点
        for (var inc in ['tips', 'rewards', 'tips_given', 'tips_received', 'moneyRewards']) {
            final rUser = await _safeFetch('/api/users/$uid', {'include': inc});
            _included.addAll(_extractData(rUser['included']));
            for (var i in _extractData(rUser['included'])) {
               if (i['type'] == 'tips' || i['type'] == 'rewards' || i['type'] == 'post_tips' || i['type'] == 'moneyRewards') {
                   uniqueMap[i['id'].toString()] = i;
               }
            }
        }
        _items = uniqueMap.values.toList();
        _customEmptyMessage = '无相关功能记录。';
      }
      else if (widget.activityType == 'money') {
        // [资金明细探针重塑]
        final endpoints = ['/api/users/$uid/money-transactions', '/api/user-money-histories', '/api/moneyHistory', '/api/users/$uid/moneyHistory', '/api/money-transfers', '/api/transactions'];
        final Map<String, dynamic> uniqueMap = {};
        for (var ep in endpoints) {
          final r1 = await _safeFetch(ep, {'filter[user]': uid});
          final r2 = await _safeFetch(ep, {});
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
        }
        
        for (var inc in ['moneyHistory', 'userMoneyHistories', 'transactions', 'moneyTransactions']) {
            final rUser = await _safeFetch('/api/users/$uid', {'include': inc});
            _included.addAll(_extractData(rUser['included']));
            for (var i in _extractData(rUser['included'])) {
               if (i['type'] == 'moneyHistory' || i['type'] == 'user-money-histories' || i['type'] == 'transactions' || i['type'] == 'moneyTransactions') {
                   uniqueMap[i['id'].toString()] = i;
               }
            }
        }
        _items = uniqueMap.values.toList();
        _customEmptyMessage = '无相关功能记录。';
      }

      if (_items.isNotEmpty) {
        _items.sort((a, b) {
          final timeAStr = a['attributes']?['createdAt']?.toString();
          final timeBStr = b['attributes']?['createdAt']?.toString();
          DateTime dateA = DateTime.fromMillisecondsSinceEpoch(0);
          DateTime dateB = DateTime.fromMillisecondsSinceEpoch(0);
          if (timeAStr != null) { try { dateA = DateTime.parse(timeAStr); } catch (_) {} }
          if (timeBStr != null) { try { dateB = DateTime.parse(timeBStr); } catch (_) {} }
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
             _error = '内部渲染防崩溃：${e.toString()}';
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
              child: const Text('重新加载网络数据')
            ),
          ],
        ),
      );
    }
    
    // [灰屏修复：无论 items 为空还是类型不匹配，只要执行到这里就一定要渲染占位图，绝不白板！]
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
        if (type == 'tips' || type == 'rewards' || type == 'post_tips' || type == 'moneyRewards' || type == 'money-rewards') return _buildTipItem(item);
        if (type == 'moneyHistory' || type == 'user-money-histories' || type == 'money_transfers' || type == 'transactions' || type == 'moneyTransactions') return _buildMoneyItem(item);
        if (type == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item); // 兜底渲染系统记录（图2）
      },
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString();
    final addedByUser = _getIncluded('users', addedByUserId);
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '系统管理员';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '违规操作通报。';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '记录时间丢失';
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
          Text('下发处理人：$adminName  |  $timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '未知业务时间';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '关联账户';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '资源接收方';

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
              Text('打赏流水 ($amount XSD)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text('资金流向：$senderName  →  $recipientName', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('业务时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMoneyItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? attrs['balance_delta']?.toString() ?? '0';
    final desc = attrs['description']?.toString() ?? attrs['reason']?.toString() ?? attrs['source']?.toString() ?? '系统自动变动明细';
    
    final timeStr = attrs['createdAt']?.toString();
    String timeDisplay = '系统校验时间失败';
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
                  Text('资产结算流水', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Text('${isIncome && amount != "0" && !amount.startsWith("+") ? "+" : ""}$amount XSD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.green : Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('核验事由：$desc', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('系统入账：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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

    String discussionTitle = '原主题数据核查失败...';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '未知授权主题';
    }
    
    final htmlContent = attrs['contentHtml'] ?? attrs['content'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
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
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50.withOpacity(0.3),
                border: Border.all(color: Colors.red.shade100, width: 1.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '在「', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                    TextSpan(text: discussionTitle, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                    const TextSpan(text: '」主题系统中的回复', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ],
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: HtmlWidget(
              htmlContent, 
              textStyle: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.6)
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text('业务流转时间：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ),
        ],
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
          // 兜底日志显示，防止报错导致整个列表不可见
          Text(attrs['title'] ?? attrs['description'] ?? attrs['reason'] ?? '系统底层数据交互', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
