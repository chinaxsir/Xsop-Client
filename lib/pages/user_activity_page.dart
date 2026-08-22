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

  DateTime? _parseFlexibleDate(String? s) {
    if (s == null || s.trim().isEmpty || s == 'null') return null;
    final num = int.tryParse(s);
    if (num != null) {
      if (s.length == 10) return DateTime.fromMillisecondsSinceEpoch(num * 1000);
      return DateTime.fromMillisecondsSinceEpoch(num);
    }
    return DateTime.tryParse(s);
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
        final results = await Future.wait([
          _safeFetch('/api/posts', {'filter[user]': uid, 'include': 'discussion,user'}),
          _safeFetch('/api/posts', {'filter[author]': uname, 'include': 'discussion,user'}),
        ]);
        
        final Map<String, dynamic> uniqueMap = {};
        for (var res in results) {
          for(var i in _extractData(res['data'])) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(res['included']));
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
        
        _customEmptyMessage = '无回复记录。';
      } 
      else if (widget.activityType == 'warnings') {
        // [数据隔离引擎重构]：剔除管理员“发给别人”的无关警告，只精准请求“别人发给我”的真实自身警告！
        final results = await Future.wait([
          _safeFetch('/api/warnings', {'filter[user]': uid, 'include': 'addedByUser,user,post'}),
          _safeFetch('/api/users/$uid', {'include': 'warnings,warnings.addedByUser,warnings.post'}),
        ]);

        final Map<String, dynamic> uniqueMap = {};
        for (var res in results) {
          for(var i in _extractData(res['data'])) {
            if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
          }
          _included.addAll(_extractData(res['included']));
          for (var i in _extractData(res['included'])) {
             if (i['type'] == 'warnings') uniqueMap[i['id'].toString()] = i;
          }
        }

        // 第二道防线：即使服务器发来了混杂数据，客户端强行剔除那些 targetUser 不是当前账号的警告。
        final List<dynamic> finalItems = [];
        for (var item in uniqueMap.values) {
           final targetUserId = item['relationships']?['user']?['data']?['id']?.toString() ?? item['attributes']?['userId']?.toString();
           if (targetUserId == uid) {
              finalItems.add(item);
           }
        }
        
        _items = finalItems;
        _customEmptyMessage = '暂无站务警告记录。';
      } 
      else if (widget.activityType == 'money-log') {
        final endpoints = ['/api/money-log', '/api/users/$uid/moneyHistory', '/api/moneyHistory'];
        
        List<Future<Map<String, dynamic>>> tasks = [];
        for (var ep in endpoints) {
           tasks.add(_safeFetch(ep, {'page[offset]': 0})); 
           tasks.add(_safeFetch(ep, {'filter[user]': uid}));
        }

        final results = await Future.wait(tasks);
        final Map<String, dynamic> uniqueMap = {};
        
        for (var res in results) {
           for(var i in _extractData(res['data'])) {
             if (i['id'] != null) uniqueMap[i['id'].toString()] = i;
           }
           _included.addAll(_extractData(res['included']));
        }

        final List<dynamic> finalItems = [];
        final Set<String> seenKeys = {}; 
        
        for (var item in uniqueMap.values) {
           final attrs = item['attributes'] ?? {};
           
           final timeStr = attrs['createdAt']?.toString() ?? '';
           final parsedDate = _parseFlexibleDate(timeStr);
           if (parsedDate == null) continue;
           
           final fingerprint = '${item['id']}_${parsedDate.millisecondsSinceEpoch}';
           if (!seenKeys.contains(fingerprint)) {
               seenKeys.add(fingerprint);
               finalItems.add(item);
           }
        }
        
        _items = finalItems;
        _customEmptyMessage = '暂无积分记录。';
      }

      if (_items.isNotEmpty) {
        _items.sort((a, b) {
          final timeAStr = a['attributes']?['createdAt']?.toString();
          final timeBStr = b['attributes']?['createdAt']?.toString();
          final dtA = _parseFlexibleDate(timeAStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dtB = _parseFlexibleDate(timeBStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dtB.compareTo(dtA);
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
        
        if (widget.activityType == 'warnings') return _buildWarningItem(item);
        if (widget.activityType == 'money-log') return _buildMoneyLogItem(item); 
        if (widget.activityType == 'posts') return _buildPostItem(item);
        
        return _buildDefaultItem(item);
      },
    );
  }

  Widget _buildMoneyLogItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final amountStr = attrs['money']?.toString() ?? attrs['amount']?.toString() ?? attrs['balance_delta']?.toString() ?? '0';
    final balanceStr = attrs['balance']?.toString() ?? attrs['currentBalance']?.toString() ?? '-';
    final reason = attrs['reason']?.toString() ?? attrs['description']?.toString() ?? attrs['source']?.toString() ?? '系统操作';
    
    final timeStr = attrs['createdAt']?.toString();
    String dateDisplay = '未知时间';
    if (timeStr != null) {
      final parsedDate = _parseFlexibleDate(timeStr);
      if (parsedDate != null) {
        dateDisplay = '${parsedDate.year}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.day.toString().padLeft(2, '0')} ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}:${parsedDate.second.toString().padLeft(2, '0')}';
      }
    }
    
    final double amountValue = double.tryParse(amountStr.replaceAll(RegExp(r'[^0-9\.\-]'), '')) ?? 0.0;
    final bool isIncome = amountValue > 0;
    final bool isZero = amountValue == 0;

    Color amountColor = isZero ? Colors.black87 : (isIncome ? Colors.green.shade700 : Colors.red.shade600);
    String amountPrefix = (isIncome && !amountStr.startsWith('+')) ? '+' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        border: Border.all(color: Colors.grey.shade200), 
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: isZero ? Colors.grey.shade100 : (isIncome ? Colors.green.shade50 : Colors.red.shade50), shape: BoxShape.circle),
                child: Icon(
                  isZero ? Icons.info_outline : (isIncome ? Icons.add_card : Icons.payment), 
                  size: 20, 
                  color: amountColor
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reason, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87, height: 1.4)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(dateDisplay, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$amountPrefix$amountStr', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: amountColor)),
                  const SizedBox(height: 4),
                  if (balanceStr != '-')
                    Text('余额: $balanceStr', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarningItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    
    final addedByUserId = item['relationships']?['addedByUser']?['data']?['id']?.toString() ?? attrs['addedByUserId']?.toString();
    final targetUserId = item['relationships']?['user']?['data']?['id']?.toString() ?? attrs['userId']?.toString();
    
    final addedByUser = _getIncluded('users', addedByUserId);
    final targetUser = _getIncluded('users', targetUserId);
    
    final adminName = addedByUser?['attributes']?['displayName'] ?? addedByUser?['attributes']?['username'] ?? '系统管理员';
    final targetName = targetUser?['attributes']?['displayName'] ?? targetUser?['attributes']?['username'] ?? '您';

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '由于违规行为收到警告。';
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '未知';
    if (timeStr != null) {
      try {
        final parsedDate = _parseFlexibleDate(timeStr);
        if (parsedDate != null) timeDisplay = formatRelativeTime(parsedDate);
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
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 20),
              const SizedBox(width: 8),
              Text('收到警告记 $strikes 分', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text(comment, style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5)),
          const SizedBox(height: 12),
          Text('下发方: $adminName', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('时间: $timeDisplay', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt']?.toString();
    
    String timeDisplay = '';
    if (timeStr != null) {
      try { 
         final parsedDate = _parseFlexibleDate(timeStr);
         if (parsedDate != null) timeDisplay = formatRelativeTime(parsedDate);
      } catch (_) {}
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
      try { 
         final parsedDate = _parseFlexibleDate(timeStr);
         if (parsedDate != null) timeDisplay = formatRelativeTime(parsedDate);
      } catch (_) {}
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
