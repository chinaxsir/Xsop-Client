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
  String _customEmptyMessage = '暂无记录。';

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
        _customEmptyMessage = '未发布任何主题。';
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
           if (type != 'comment') return false; 
           
           final relUserId = p['relationships']?['user']?['data']?['id']?.toString();
           final attrUserId = p['attributes']?['userId']?.toString();
           
           if (relUserId != null && relUserId != uid) return false;
           if (attrUserId != null && attrUserId != uid) return false;
           return true; 
        }).toList();
        
        _included = [..._extractData(r1['included']), ..._extractData(r2['included'])];
        _customEmptyMessage = '无回复记录。';
      } 
      else if (widget.activityType == 'warnings') {
        final endpoints = ['/api/warnings/$uid', '/api/warnings', '/api/users/$uid/warnings', '/api/user-warnings'];
        final Map<String, dynamic> uniqueMap = {};
        
        for (var ep in endpoints) {
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
        _customEmptyMessage = '暂无站务警告。';
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
          final r2 = await _safeFetch(ep, {'filter[sender]': uid, 'include': 'sender,recipient,post'});
          final r3 = await _safeFetch(ep, {'filter[recipient]': uid, 'include': 'sender,recipient,post'});
          final r4 = await _safeFetch(ep, {}); 
          
          for(var i in [..._extractData(r1['data']), ..._extractData(r2['data']), ..._extractData(r3['data']), ..._extractData(r4['data'])]) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(r1['included']));
          _included.addAll(_extractData(r2['included']));
          _included.addAll(_extractData(r3['included']));
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
        
        if (uniqueMap.isEmpty) {
           final rAll = await _safeFetch('/api/users/4/money-rewards', {}); 
           for(var i in _extractData(rAll['data'])) {
               uniqueMap[i['id'].toString()] = i;
           }
           _included.addAll(_extractData(rAll['included']));
        }

        _items = uniqueMap.values.toList();
        _customEmptyMessage = '暂无打赏记录。';
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
        _customEmptyMessage = '暂无资金明细。';
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
               _error = '权限不足：无法查阅该数据。';
            } else {
               _error = '网络请求失败，请稍后重试。';
            }
          } else {
             _error = '系统错误：${e.toString()}';
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
              child: const Text('重新加载')
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
        
        if (widget.activityType == 'warnings') return _buildWarningItem(item);
        if (widget.activityType == 'tips' || type == 'rewards' || type == 'post_tips' || type == 'moneyRewards') return _TipItemWidget(item: item, api: widget.api, included: _included, profileUser: widget.user);
        if (widget.activityType == 'moneyHistory' || type == 'user-money-histories' || type == 'money_transfers' || type == 'transactions' || type == 'moneyTransactions') return _buildMoneyItem(item);
        if (widget.activityType == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item);
      },
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString() ?? attrs['addedByUserId']?.toString();
    final targetUserId = item['relationships']?['user']?['data']?['id']?.toString() ?? attrs['userId']?.toString();
    
    final addedByUser = _getIncluded('users', addedByUserId);
    final targetUser = _getIncluded('users', targetUserId);
    
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '管理员';
    final targetName = targetUser?['attributes']?['displayName'] ?? targetUser?['attributes']?['username'] ?? '用户';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '违规操作。';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '未知';
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
          Text('$adminName 警告了 $targetName', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMoneyItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? attrs['balance_delta']?.toString() ?? '0';
    final desc = attrs['description']?.toString() ?? attrs['reason']?.toString() ?? attrs['source']?.toString() ?? '系统变动';
    
    final timeStr = attrs['createdAt']?.toString();
    String timeDisplay = '未知';
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
                  Text('资金明细', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Text('${isIncome && amount != "0" && !amount.startsWith("+") ? "+" : ""}$amount XSD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.green : Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Text('事由：$desc', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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

    String discussionTitle = '未知帖子';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '未知帖子';
    }
    
    final rawHtml = attrs['contentHtml'];
    final rawContent = attrs['content'];
    
    String safeHtmlContent = '';
    if (rawHtml is String && rawHtml.isNotEmpty) {
      safeHtmlContent = rawHtml;
    } else if (rawContent is String) {
      safeHtmlContent = rawContent;
    } else {
      safeHtmlContent = '<p style="color: grey;">[内容已隐藏]</p>';
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
                    const TextSpan(text: '」主题中的回复', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
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
            child: Text('时间：$timeDisplay', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
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
          Text(attrs['title'] ?? attrs['description'] ?? attrs['reason'] ?? '基础记录', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// [全功能重塑的打赏渲染组件：彻底消灭“未知用户”]
class _TipItemWidget extends StatefulWidget {
  final Map<String, dynamic> item;
  final ApiClient api;
  final List<dynamic> included;
  final FlarumUser profileUser; // 引入个人中心的主角数据作为锚点

  const _TipItemWidget({
    required this.item, 
    required this.api, 
    required this.included, 
    required this.profileUser
  });

  @override
  State<_TipItemWidget> createState() => _TipItemWidgetState();
}

class _TipItemWidgetState extends State<_TipItemWidget> {
  String _senderName = '加载中...';
  String _recipientName = '加载中...';
  String _discussionTitle = '';
  String? _discussionId;
  String _amount = '0';
  String _timeDisplay = '未知';
  String? _balance;

  @override
  void initState() {
    super.initState();
    _parseInitialData();
    _fetchMissingNames();
  }

  Map<String, dynamic>? _getIncluded(String type, String? id) {
    if (id == null) return null;
    try {
      return widget.included.firstWhere((e) => e['type'] == type && e['id'].toString() == id);
    } catch (_) { return null; }
  }

  void _parseInitialData() {
    final attrs = widget.item['attributes'] ?? {};
    _amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? attrs['value']?.toString() ?? attrs['reward']?.toString() ?? '0';
    _balance = attrs['balance']?.toString() ?? attrs['currentBalance']?.toString();
    
    final timeStr = attrs['createdAt']?.toString();
    if (timeStr != null) {
      try { _timeDisplay = formatRelativeTime(DateTime.parse(timeStr)); } catch (_) {}
    }

    final postId = widget.item['relationships']?['post']?['data']?['id']?.toString() ?? attrs['postId']?.toString();
    if (postId != null) {
      final postNode = _getIncluded('posts', postId);
      if (postNode != null) {
         _discussionId = postNode['relationships']?['discussion']?['data']?['id']?.toString();
      }
    }
    _discussionId ??= widget.item['relationships']?['discussion']?['data']?['id']?.toString();
    
    if (_discussionId != null) {
      final dNode = _getIncluded('discussions', _discussionId);
      if (dNode != null) {
         _discussionTitle = dNode['attributes']?['title'] ?? '未知帖子';
      }
    }
  }

  // 强大的 ID 转用户名解析器
  Future<String> _resolveUserName(String? id, String defaultName) async {
    if (id == null) return defaultName;
    
    // 1. 本地缓存里找
    final node = _getIncluded('users', id);
    if (node != null) {
        return node['attributes']?['displayName'] ?? node['attributes']?['username'] ?? defaultName;
    }
    
    // 2. 强制去服务器查
    try {
        final res = await widget.api.getUser(int.parse(id));
        return res['data']?['attributes']?['displayName'] ?? res['data']?['attributes']?['username'] ?? defaultName;
    } catch (_) {
        return defaultName;
    }
  }

  // [无敌推断引擎] 彻底解决 Flarum 数据缺失导致系统/未知用户的问题
  Future<void> _fetchMissingNames() async {
    final attrs = widget.item['attributes'] ?? {};
    final rels = widget.item['relationships'] ?? {};
    
    // 获取正在查看页面的主角 ID 和 名字
    final String profileUid = widget.profileUser.id;
    final String profileName = widget.profileUser.displayName.isNotEmpty ? widget.profileUser.displayName : widget.profileUser.username;

    // 尝试提取明确给定的发送方和接收方
    String? explicitSender = rels['sender']?['data']?['id']?.toString() ?? 
                             rels['fromUser']?['data']?['id']?.toString() ?? 
                             attrs['senderId']?.toString() ?? 
                             attrs['fromUserId']?.toString();

    String? explicitRecipient = rels['recipient']?['data']?['id']?.toString() ?? 
                                rels['toUser']?['data']?['id']?.toString() ?? 
                                attrs['recipientId']?.toString() ?? 
                                attrs['toUserId']?.toString();
    
    String? sId = explicitSender;
    String? rId = explicitRecipient;

    // 搜刮整条记录里牵涉到的所有人（除了主角以外的人）
    List<String> otherUsers = [];
    rels.forEach((k, v) {
        if (v is Map && v['data'] is Map) {
            var d = v['data'];
            if (d['type'] == 'users' && d['id'] != null && d['id'].toString() != profileUid) {
                otherUsers.add(d['id'].toString());
            }
        } else if (v is Map && v['data'] is List) {
            for (var e in v['data']) {
                if (e is Map && e['type'] == 'users' && e['id'] != null && e['id'].toString() != profileUid) {
                    otherUsers.add(e['id'].toString());
                }
            }
        }
    });

    // 绝杀逻辑：如果服务器连个发送人/接收人都没给
    if (sId == null && rId == null) {
        // 根据钱是加了还是扣了，推断谁收谁付！
        double amt = double.tryParse(_amount.replaceAll(RegExp(r'[^0-9\.\-]'), '')) ?? 0.0;
        if (amt < 0) {
            sId = profileUid; // 钱少了，主角是付款人
            rId = otherUsers.isNotEmpty ? otherUsers.first : null;
        } else {
            rId = profileUid; // 钱多了，主角是收款人
            sId = otherUsers.isNotEmpty ? otherUsers.first : null;
        }
    } else if (sId == null && rId != null) {
        if (rId != profileUid) sId = profileUid;
        else sId = otherUsers.isNotEmpty ? otherUsers.first : null;
    } else if (rId == null && sId != null) {
        if (sId != profileUid) rId = profileUid;
        else rId = otherUsers.isNotEmpty ? otherUsers.first : null;
    }

    // 系统下发的补贴兜底
    sId ??= attrs['actorId']?.toString();

    // 如果还没有收款人，尝试去原帖子里找楼主！
    if (rId == null) {
       final postId = rels['post']?['data']?['id']?.toString() ?? attrs['postId']?.toString();
       if (postId != null) {
            final pNode = _getIncluded('posts', postId);
            if (pNode != null) {
                rId = pNode['relationships']?['user']?['data']?['id']?.toString();
            } else {
                try {
                    final pRes = await widget.api.getDynamicList('/api/posts/$postId');
                    rId = pRes['data']?['relationships']?['user']?['data']?['id']?.toString();
                } catch (_) {}
            }
       }
    }

    // 最终解析名字：是主角就直接用主角名字，不是就去数据库查
    String resolvedSender = sId == profileUid ? profileName : await _resolveUserName(sId, sId == null ? '系统' : '未知用户');
    String resolvedRecipient = rId == profileUid ? profileName : await _resolveUserName(rId, rId == null ? '系统' : '未知用户');

    if (mounted) {
        setState(() {
            _senderName = resolvedSender;
            _recipientName = resolvedRecipient;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _discussionId != null ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DiscussionDetailPage(
              api: widget.api,
              discussion: Discussion(
                id: _discussionId!, 
                title: _discussionTitle,
                commentCount: 0, 
                createdAt: DateTime.now(),
                tags: const [], 
              ),
            ),
          ),
        );
      } : null,
      child: Container(
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
                Text('打赏记录 ($_amount XSD)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '打赏用户：', style: TextStyle(color: Colors.grey)),
                  TextSpan(text: _senderName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
                  const TextSpan(text: '  →  ', style: TextStyle(color: Colors.grey)),
                  TextSpan(text: _recipientName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
                ],
              ),
              style: const TextStyle(fontSize: 14),
            ),
            if (_balance != null) ...[
              const SizedBox(height: 8),
              Text('当前余额：$_balance XSD', style: const TextStyle(color: Colors.black87, fontSize: 14)),
            ],
            if (_discussionTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '相关帖子：', style: TextStyle(color: Colors.grey)),
                    TextSpan(text: _discussionTitle, style: const TextStyle(color: Colors.blueAccent)),
                  ],
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            Text('时间：$_timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
