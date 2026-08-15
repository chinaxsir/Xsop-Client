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
  String _customEmptyMessage = '当前业务项暂无相关核验记录。';

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
        _customEmptyMessage = '该系统账户暂未发布任何授权主题。';
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
           // [致命灰屏彻底修复]：强制剥离所有非文本的系统级交互记录！
           // Flarum 管理员的系统操作（如改名、锁定）其 content 会返回数组结构，若不加剔除，将引发客户端强转崩溃。
           if (type != 'comment') return false; 
           
           final relUserId = p['relationships']?['user']?['data']?['id']?.toString();
           final attrUserId = p['attributes']?['userId']?.toString();
           
           // 严格匹配归属关系，杜绝不同账户的越权展示
           if (relUserId != null && relUserId != uid) return false;
           if (attrUserId != null && attrUserId != uid) return false;
           
           return true; 
        }).toList();
        
        _included = [..._extractData(r1['included']), ..._extractData(r2['included'])];
        _customEmptyMessage = '暂无符合常规阅读类型的回复数据。';
      } 
      else if (widget.activityType == 'warnings') {
        final endpoints = ['/api/warnings/$uid', '/api/warnings', '/api/users/$uid/warnings', '/api/user-warnings'];
        final Map<String, dynamic> uniqueMap = {};
        
        for (var ep in endpoints) {
          // [管理员专治修复]：除了拉取“别人警告我”的数据，也要拉取“我警告别人”的数据 (addedByUser)
          final r1 = await _safeFetch(ep, {'filter[user]': uid, 'include': 'addedByUser,user,post'});
          final r2 = await _safeFetch(ep, {'filter[addedByUser]': uid, 'include': 'addedByUser,user,post'}); 
          final r3 = await _safeFetch(ep, {}); 
          
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data']), ..._extractData(r3['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(r1['included']));
          _included.addAll(_extractData(r2['included']));
          _included.addAll(_extractData(r3['included']));
        }
        
        final rUser = await _safeFetch('/api/users/$uid', {'include': 'warnings'});
        _included.addAll(_extractData(rUser['included']));
        for (var i in _extractData(rUser['included'])) {
           if (i['type'] == 'warnings') uniqueMap[i['id'].toString()] = i;
        }
        _items = uniqueMap.values.toList();
        _customEmptyMessage = '当前业务项暂无站务违规记录流转。';
      } 
      else if (widget.activityType == 'tips') {
        final endpoints = [
          '/api/users/$uid/money-rewards', 
          '/api/tips', 
          '/api/rewards', 
          '/api/users/$uid/tips'
        ];
        final Map<String, dynamic> uniqueMap = {};
        
        for (var ep in endpoints) {
          final r1 = await _safeFetch(ep, {'filter[user]': uid, 'include': 'sender,recipient,post'});
          final r2 = await _safeFetch(ep, {'filter[sender]': uid});
          final r3 = await _safeFetch(ep, {'filter[recipient]': uid});
          final r4 = await _safeFetch(ep, {}); 
          
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data']), ..._extractData(r3['data']), ..._extractData(r4['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(r1['included']));
        }
        
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
        _customEmptyMessage = '暂未探测到有效的打赏交互节点。';
      }
      else if (widget.activityType == 'money') {
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
        _customEmptyMessage = '当前环境暂无相关资产变动明细。';
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
               _error = '环境鉴权拦截：系统权限不足，阻断展示。';
            } else {
               _error = '底层链路通信故障，数据提取受阻。';
            }
          } else {
             _error = '核心解析引擎触发防崩溃：${e.toString()}';
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
              child: const Text('重建数据会话连接')
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
        
        // [极度安全的组件派发器]：不再信任混乱的 item['type']，直接基于业务板块绝对派发
        if (widget.activityType == 'warnings') return _buildWarningItem(item);
        if (widget.activityType == 'tips') return _buildTipItem(item);
        if (widget.activityType == 'money') return _buildMoneyItem(item);
        if (widget.activityType == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item); // 兜底安全栅栏
      },
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString() ?? attrs['addedByUserId']?.toString();
    final targetUserId = item['relationships']?['user']?['data']?['id']?.toString() ?? attrs['userId']?.toString();
    
    final addedByUser = _getIncluded('users', addedByUserId);
    final targetUser = _getIncluded('users', targetUserId);
    
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '系统管理员';
    final targetName = targetUser?['attributes']?['displayName'] ?? targetUser?['attributes']?['username'] ?? '被执行人';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '触发了安全通报条款。';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '环境时间戳丢失';
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
              Text('警告记入 $strikes 违规分', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text(comment, style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('发起端：$adminName  |  接收端：$targetName', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('节点时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    // 获取价格的多维兼容
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? attrs['value']?.toString() ?? attrs['reward']?.toString() ?? '0';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '未知业务时间';
    if (timeStr != null) {
      try { timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString() ?? attrs['fromUserId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '关联账户';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString() ?? attrs['toUserId']?.toString();
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
              Text('打赏资源流转 ($amount XSD)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text('交互链路：$senderName  →  $recipientName', style: const TextStyle(color: Colors.black87, fontSize: 14)),
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

    String discussionTitle = '原主题数据提取核查中...';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '未知授权主题';
    }
    
    // [致命类型拦截]：绝不信任 raw content，只渲染严格的 String 数据，防止强转触发灰屏！
    final rawHtml = attrs['contentHtml'];
    final rawContent = attrs['content'];
    
    String safeHtmlContent = '';
    if (rawHtml is String && rawHtml.isNotEmpty) {
      safeHtmlContent = rawHtml;
    } else if (rawContent is String) {
      safeHtmlContent = rawContent;
    } else {
      safeHtmlContent = '<p style="color: grey;">[当前数据包含非阅读属性的环境参数，已自动隐藏处理]</p>';
    }

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
                    const TextSpan(text: '」主题系统中的常规回复', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ],
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: HtmlWidget(
              safeHtmlContent, 
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
          Text(attrs['title'] ?? attrs['description'] ?? attrs['reason'] ?? '基础底层环境记录交互', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
