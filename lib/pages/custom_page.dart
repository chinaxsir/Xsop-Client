// 文件位置: lib/pages/custom_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:xsop_forum/api/api_client.dart';

class CustomPage extends StatefulWidget {
  final ApiClient api;
  final String pageId;
  final String title;

  const CustomPage({
    super.key,
    required this.api,
    required this.pageId,
    required this.title,
  });

  @override
  State<CustomPage> createState() => _CustomPageState();
}

class _CustomPageState extends State<CustomPage> {
  bool _isLoading = true;
  String? _error;
  String _htmlContent = '';

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  Future<void> _loadPageData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.api.getCustomPage(widget.pageId);
      final attrs = response['data']?['attributes'];
      
      if (attrs != null && attrs['contentHtml'] != null) {
        _htmlContent = attrs['contentHtml'];
      } else {
        _error = '页面内容为空';
      }
      
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is DioException && e.response?.statusCode == 404) {
            _error = '未找到该页面数据';
          } else {
            _error = '加载失败，请检查网络';
          }
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: _buildBody(),
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
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadPageData, 
              child: const Text('重试')
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      // 使用 HtmlWidget 原生渲染从网页端后台同步过来的 HTML 标签
      child: HtmlWidget(
        _htmlContent,
        textStyle: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
        customStylesBuilder: (element) {
          // 对后台复杂的 CSS Grid / Flex 样式进行移动端降级保护，避免内容溢出
          if (element.classes.contains('grid') || element.classes.contains('flex')) {
            return {'display': 'block', 'width': '100%'};
          }
          return null;
        },
      ),
    );
  }
}
