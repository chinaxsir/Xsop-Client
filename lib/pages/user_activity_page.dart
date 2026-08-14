// 新建文件位置: lib/pages/user_activity_page.dart

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
      
      // [智能路由引擎：根据传入类型自动匹配 Flarum 标准接口或常用插件接口]
      switch (widget.activityType) {
        case 'discussions':
          res = await widget.api.getDynamicList('/api/discussions', queryParameters: {'filter[q]': 'author:${widget.user.username}'});
          break;
        case 'posts':
          res = await widget.api.getDynamicList('/api/posts', queryParameters: {'filter[user]': widget.user.id});
          break;
        case 'warnings_received':
          res = await widget.api.getDynamicList('/api/warnings', queryParameters: {'filter[user]': widget.user.id});
          break;
        case 'warnings_sent':
          res = await widget.api.getDynamicList('/api/warnings', queryParameters: {'filter[addedByUser]': widget.user.id});
          break;
        case 'tips_received':
          // 适配主流打赏插件流水，如查不到自动兜底
          res = await widget.api.getDynamicList('/api/tips', queryParameters: {'filter[recipient]': widget.user.id});
          break;
        case 'tips_sent':
          res = await widget.api.getDynamicList('/api/tips', queryParameters: {'filter[sender]': widget.user.id});
          break;
        default:
          throw Exception('未知的活动类型');
      }
      
      if (mounted) {
        setState(() {
          _items = res['data'] as List<dynamic>? ?? [];
          _isLoading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          // 优雅降级：如果是 404 说明没装对应插件，而不是网络错误
          if (e.response?.statusCode == 404) {
             _error = '未开启该功能或暂无数据 (404)';
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
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ],
        ),
      );
    }
    
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('空空如也', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
          ],
        ),
      );
    }
    
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _buildListItem(item);
      },
    );
  }

  // [动态渲染引擎：根据不同的流水记录，解析出不同的 UI 排版]
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
      title = '在某主题中的回复';
      htmlContent = attrs['contentHtml'] ?? attrs['content'];
      subtitle = '回复于 $timeDisplay';
    } else if (type == 'warnings') {
      title = '站务警告通知';
      htmlContent = attrs['publicComment'] ?? attrs['reason'] ?? '由于违反社区规定，已被管理员记录。';
      badgeText = '警告';
      badgeColor = Colors.red;
      subtitle = '记录于 $timeDisplay';
    } else if (type == 'tips') {
      title = '资产变动记录';
      final amount = attrs['amount']?.toString() ?? '0';
      badgeText = '$amount XSD';
      badgeColor = Colors.orange;
      htmlContent = attrs['message'] ?? '发生了打赏交易';
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
