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
  List<dynamic> _included = []; // 核心：用于存储并解析被关联进来的主题名称和用户信息
  
  // 用于优雅展示空数据的提示文案
  String _customEmptyMessage = '空空如也';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> res;
      
      switch (widget.activityType) {
        case 'discussions':
          res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
          _customEmptyMessage = '该用户暂未发布任何主题。';
          break;
        case 'posts':
          // [核心修复：增加 include=discussion，让 APP 能获取到回复所在的真实帖子标题]
          res = await widget.api.getDynamicList('/api/posts', queryParameters: {
            'filter[user]': widget.user.id,
            'include': 'discussion'
          });
          _customEmptyMessage = '该用户暂未发表任何回复。';
          break;
        case 'warnings_received':
          res = await widget.api.getDynamicList('/api/warnings', queryParameters: {'filter[user]': widget.user.id});
          _customEmptyMessage = '该用户暂未收到任何警告。';
          break;
        case 'warnings_sent':
          res = await widget.api.getDynamicList('/api/warnings', queryParameters: {'filter[addedByUser]': widget.user.id});
          _customEmptyMessage = '该用户暂未发出任何警告。';
          break;
        case 'tips_received':
          // 尽最大可能获取发送者信息
          res = await widget.api.getDynamicList('/api/tips', queryParameters: {
            'filter[recipient]': widget.user.id,
            'include': 'sender,recipient'
          });
          _customEmptyMessage = '暂无收到的打赏记录。';
          break;
        case 'tips_sent':
          res = await widget.api.getDynamicList('/api/tips', queryParameters: {
            'filter[sender]': widget.user.id,
            'include': 'sender,recipient'
          });
          _customEmptyMessage = '暂无发出的打赏记录。';
          break;
        default:
          throw Exception('未知的活动类型');
      }
      
      if (mounted) {
        setState(() {
          _items = res['data'] as List<dynamic>? ?? [];
          _included = res['included'] as List<dynamic>? ?? [];
          _isLoading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          // [核心修复：优雅拦截 404 (插件未安装) 或数据为空的情况，不再显示裂开的图标]
          if (e.response?.statusCode == 404) {
             _items = []; 
             _error = null; 
             _customEmptyMessage = '未开启该功能或暂无数据 (404)';
          } else if (e.response?.statusCode == 403) {
             _error = '权限不足：您无法查看此详情';
          } else {
             _error = '加载失败，请检查网络';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '解析数据发生异常';
          _isLoading = false;
        });
      }
    }
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // 网络等硬核错误提示
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
    
    // [核心修复：完美对齐网页版的空数据占位符展示]
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
        return _buildListItem(item);
      },
    );
  }

  // 动态渲染不同类型的列表项
  Widget _buildListItem(Map<String, dynamic> item) {
    final attrs = item['attributes'] ?? {};
    final type = item['type'];
    
    String title = '';
    String subtitle = '';
    String? htmlContent;
    String? badgeText;
    Color badgeColor = Colors.grey;

    final timeStr = attrs['createdAt'];
    final timeDisplay = timeStr != null ? formatRelativeTime(DateTime.parse(timeStr)) : '';

    if (type == 'discussions') {
      title = attrs['title'] ?? '无标题';
      subtitle = '发布于 $timeDisplay';
    } else if (type == 'posts') {
      // [核心修复：解析并拼接帖子真实标题]
      String discussionTitle = '未知主题';
      final discussionId = attrs['discussionId']?.toString() ?? item['relationships']?['discussion']?['data']?['id']?.toString();
      if (discussionId != null) {
        final dNode = _included.firstWhere((e) => e['type'] == 'discussions' && e['id'].toString() == discussionId, orElse: () => null);
        if (dNode != null) discussionTitle = dNode['attributes']?['title'] ?? '未知主题';
      }
      
      title = '回复了主题：「$discussionTitle」';
      htmlContent = attrs['contentHtml'] ?? attrs['content'];
      subtitle = '回复于 $timeDisplay';
    } else if (type == 'warnings') {
      title = '站务警告记录';
      htmlContent = attrs['publicComment'] ?? attrs['reason'] ?? '由于违反社区规定，已被管理员记录。';
      badgeText = '警告';
      badgeColor = Colors.red;
      subtitle = '记录于 $timeDisplay';
    } else if (type == 'tips' || type == 'money_transfers' || type == 'transactions') {
      // [核心修复：适配类似 "10 XSD 来自 xx 给 xx" 的网页版打赏UI]
      final amount = attrs['amount']?.toString() ?? '0';
      badgeText = '$amount XSD';
      badgeColor = Colors.orange;

      String senderName = '';
      String recipientName = '';

      final senderId = item['relationships']?['sender']?['data']?['id']?.toString();
      if (senderId != null) {
        final sNode = _included.firstWhere((e) => e['type'] == 'users' && e['id'].toString() == senderId, orElse: () => null);
        if (sNode != null) senderName = sNode['attributes']?['displayName'] ?? sNode['attributes']?['username'] ?? '';
      }

      final recipientId = item['relationships']?['recipient']?['data']?['id']?.toString();
      if (recipientId != null) {
        final rNode = _included.firstWhere((e) => e['type'] == 'users' && e['id'].toString() == recipientId, orElse: () => null);
        if (rNode != null) recipientName = rNode['attributes']?['displayName'] ?? rNode['attributes']?['username'] ?? '';
      }

      String detailStr = '';
      if (senderName.isNotEmpty && recipientName.isNotEmpty) {
        detailStr = '来自 $senderName 给 $recipientName';
      }

      title = detailStr.isNotEmpty ? detailStr : '资产变动记录';
      htmlContent = attrs['message']; 
      subtitle = '发生于 $timeDisplay';
    } else {
      title = '记录详情';
      subtitle = timeDisplay;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeColor.withOpacity(0.5), width: 0.5),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          if (htmlContent != null && htmlContent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F9F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: HtmlWidget(
                htmlContent,
                textStyle: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
