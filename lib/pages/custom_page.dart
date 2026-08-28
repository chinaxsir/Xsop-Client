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
        // 🚨 引擎第一步：向服务端传回的纯净 HTML 中注入移动端适配的 CSS 样式表
        // 赋予页面和网页端一致的圆角、阴影、间距和微蓝灰底色（#f0f4f8）
        _htmlContent = '''
        <style>
          .grid, .flex, .row, .container { display: flex; flex-direction: column; gap: 16px; }
          .col, .col-md-6, .col-sm-12, .col-md-4 { width: 100%; display: block; }
          .card, .box, .panel, .service-card { 
            background-color: #f0f4f8 !important; 
            border-radius: 12px !important; 
            padding: 24px !important; 
            border: none !important;
            margin-bottom: 16px !important;
          }
          h1, h2, h3, h4 { color: #1a202c !important; font-weight: 700 !important; margin: 12px 0 8px 0 !important; font-size: 18px !important; }
          p { color: #4a5568 !important; font-size: 14px !important; line-height: 1.6 !important; margin: 0 !important; }
          a { text-decoration: none !important; color: #1a202c !important; }
        </style>
        ''' + attrs['contentHtml'];
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

  // 🚨 引擎第二步：FontAwesome 图标的本地映射字典
  // 将 Flarum 后台填写的 fa-xxx 转换为原生的 Flutter 矢量图标
  IconData _mapFontAwesomeToFlutter(Iterable<String> classes) {
    final cls = classes.join(' ').toLowerCase();
    
    // 匹配网页端常用图标集
    if (cls.contains('sitemap') || cls.contains('network')) return Icons.account_tree;
    if (cls.contains('shield')) return Icons.security;
    if (cls.contains('graduation') || cls.contains('school')) return Icons.school;
    if (cls.contains('plane') || cls.contains('flight')) return Icons.flight_takeoff;
    if (cls.contains('mobile') || cls.contains('phone')) return Icons.phone_iphone;
    if (cls.contains('code') || cls.contains('dev')) return Icons.code;
    
    // 基础备用集
    if (cls.contains('laptop') || cls.contains('desktop')) return Icons.computer;
    if (cls.contains('server')) return Icons.dns;
    if (cls.contains('cloud')) return Icons.cloud;
    if (cls.contains('cog') || cls.contains('wrench')) return Icons.settings;
    if (cls.contains('user')) return Icons.person;
    if (cls.contains('book') || cls.contains('file')) return Icons.book;
    if (cls.contains('star')) return Icons.star;
    if (cls.contains('heart')) return Icons.favorite;
    if (cls.contains('info') || cls.contains('question')) return Icons.info_outline;
    if (cls.contains('check')) return Icons.check_circle;
    if (cls.contains('gavel') || cls.contains('law')) return Icons.gavel;
    
    return Icons.widgets_outlined; // 无法识别时的默认占位图标
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
      child: HtmlWidget(
        _htmlContent,
        textStyle: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
        
        // 强制约束图片、框架等的最大宽度
        customStylesBuilder: (element) {
          if (element.localName == 'img' || element.localName == 'iframe') {
            return {'max-width': '100%', 'height': 'auto'};
          }
          return null;
        },
        
        // 🚨 引擎启动：实时接管 HTML 的渲染管线
        customWidgetBuilder: (element) {
          // 拦截所有的 i 标签或携带 fa/fas 类的标签（这是 FontAwesome 的特征）
          if (element.localName == 'i' || element.localName == 'span') {
            if (element.classes.any((c) => c.startsWith('fa-') || c == 'fas' || c == 'fab' || c == 'far')) {
              
              // 提取对应的原生图标并加上特定的主题蓝灰色 (#526D85) 渲染
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Icon(
                  _mapFontAwesomeToFlutter(element.classes), 
                  size: 36, 
                  color: const Color(0xFF526D85)
                ),
              );
              
            }
          }
          return null;
        },
      ),
    );
  }
}
