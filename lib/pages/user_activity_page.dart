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

  Future<void> _loadData() async {
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
        // [核心修复点：为查询追加 include=discussion,user 才能保证本地验证不抓瞎]
        final res = await widget.api.getDynamicList('/api/posts', queryParameters: {
          'filter[user]': uid, 
          'filter[type]': 'comment', 
          'include': 'discussion,user'
        });
        final rawPosts = res['data'] as List<dynamic>? ?? [];
        
        _items = rawPosts.where((p) {
           final relUserId = p['relationships']?['user']?['data']?['id']?.toString();
           final attrUserId = p['attributes']?['userId']?.toString();
           if (relUserId != null) return relUserId == uid;
           if (attrUserId != null) return attrUserId == uid;
           return true; 
        }).toList();
        
        _included = res['included'] ?? [];
        _customEmptyMessage = '无回复记录。';
      } 
      else if (widget.activityType == 'warnings') {
        List<dynamic> wData = [];
        final wEndpoints = ['/api/warnings', '/api/users/$uid/warnings', '/api/user-warnings'];
        for (var ep in wEndpoints) {
           try {
               final r = await widget.api.getDynamicList(ep, queryParameters: {'filter[user]': uid, 'include': 'addedByUser,post'});
               wData.addAll(r['data'] ?? []);
               _included.addAll(r['included'] ?? []);
           } catch(_) {
               try {
                   final r = await widget.api.getDynamicList(ep, queryParameters: {'filter[user]': uid});
                   wData.addAll(r['data'] ?? []);
                   _included.addAll(r['included'] ?? []);
               } catch(_) {}
           }
        }
        final Map<String, dynamic> wUnique = {};
        for (var i in wData) if (i['id'] != null) wUnique[i['id'].toString()] = i;
        _items = wUnique.values.toList();
        _customEmptyMessage = '暂无站务警告记录。';
      } 
      else if (widget.activityType == 'tips') {
        List<dynamic> tData = [];
        // [极度暴力的打赏探针：不论是原版还是魔改，全方面扫荡该用户的资产记录]
        final tEndpoints = ['/api/tips', '/api/rewards', '/api/moneyHistory', '/api/users/$uid/tips', '/api/users/$uid/moneyHistory', '/api/money-transfers'];
        final tFilters = ['filter[user]', 'filter[recipient]', 'filter[sender]'];
        
        for (var ep in tEndpoints) {
            if (ep.contains(uid)) {
                try {
                   final r = await widget.api.getDynamicList(ep, queryParameters: {'include': 'sender,recipient,post'});
                   tData.addAll(r['data'] ?? []);
                   _included.addAll(r['included'] ?? []);
                } catch(_) {
                   try {
                       final r = await widget.api.getDynamicList(ep);
                       tData.addAll(r['data'] ?? []);
                       _included.addAll(r['included'] ?? []);
                   } catch(_) {}
                }
                continue;
            }
            for (var fk in tFilters) {
                try {
                   final r = await widget.api.getDynamicList(ep, queryParameters: {fk: uid, 'include': 'sender,recipient,post'});
                   tData.addAll(r['data'] ?? []);
                   _included.addAll(r['included'] ?? []);
                } catch(_) {
                   try {
                       final r = await widget.api.getDynamicList(ep, queryParameters: {fk: uid});
                       tData.addAll(r['data'] ?? []);
                       _included.addAll(r['included'] ?? []);
                   } catch(_) {}
                }
            }
        }
        
        final Map<String, dynamic> tUnique = {};
        for (var i in tData) {
           if (i != null && i['id'] != null) {
               final rels = i['relationships'] ?? {};
               final attrs = i['attributes'] ?? {};
               bool isRelated = false;
               
               for (var val in rels.values) {
                 if (val is Map && val['data'] is Map && val['data']['id'].toString() == uid) isRelated = true;
                 if (val is Map && val['data'] is List) {
                   for (var v in val['data']) {
                     if (v is Map && v['id'].toString() == uid) isRelated = true;
                   }
                 }
               }
               if (attrs.values.any((v) => v.toString() == uid)) isRelated = true;
               if (isRelated) tUnique[i['id'].toString()] = i;
           }
        }
        _items = tUnique.values.toList();
        _customEmptyMessage = '暂无打赏或资产流水。';
      }

      if (_items.isNotEmpty) {
        _items.sort((a, b) {
          final timeA = a['attributes']?['createdAt'];
          final timeB = b['attributes']?['createdAt'];
          final dateA = timeA != null ? DateTime.tryParse(timeA.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = timeB != null ? DateTime.tryParse(timeB.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA);
        });
      }

      if (mounted) setState(() => _isLoading = false);
      
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          if (e.response?.statusCode == 404) {
             _items = []; _error = null; 
          } else if (e.response?.statusCode == 403) {
             _error = '服务器拦截：无权查看这些数据。';
          } else {
             _error = '网络传输发生故障。';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '发生数据渲染层错误。'; _isLoading = false; });
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

    final strikes = attrs['strikes'] ?? 0;
    final comment = attrs['publicComment'] ?? attrs['reason'] ?? '违反社区发帖规范。';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.tryParse(timeStr.toString()) ?? DateTime.now()) : '时间丢失';

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
          Text('处理人：$adminName  |  归档时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTipItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final amount = attrs['amount']?.toString() ?? attrs['money']?.toString() ?? '0';
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.tryParse(timeStr.toString()) ?? DateTime.now()) : '未知';

    final senderId = item['relationships']?['sender']?['data']?['id']?.toString() ?? attrs['senderId']?.toString();
    final sender = _getIncluded('users', senderId);
    final senderName = sender?['attributes']?['displayName'] ?? sender?['attributes']?['username'] ?? '账户';

    final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString() ?? attrs['recipientId']?.toString();
    final recipient = _getIncluded('users', recipientId);
    final recipientName = recipient?['attributes']?['displayName'] ?? recipient?['attributes']?['username'] ?? '接收人';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade100), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text('打赏流水 ($amount XSD)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Text('记录：$senderName  →  $recipientName', style: const TextStyle(color: Colors.black87, fontSize: 14)),
          const SizedBox(height: 12),
          Text('结算时间：$timeDisplay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.tryParse(timeStr.toString()) ?? DateTime.now()) : '';

    String discussionTitle = '原始帖子未找到';
    final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
    if (discussionId != null) {
      final dNode = _getIncluded('discussions', discussionId);
      if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '原始帖子未找到';
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
                  createdAt: timeStr != null ? DateTime.tryParse(timeStr.toString()) ?? DateTime.now() : DateTime.now(),
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
    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.tryParse(timeStr.toString()) ?? DateTime.now()) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attrs['title'] ?? '基础日志流', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
