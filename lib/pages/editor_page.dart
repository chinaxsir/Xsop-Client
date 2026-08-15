// 文件位置: lib/pages/editor_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';

class EditorPage extends StatefulWidget {
  final ApiClient api;
  final Discussion? discussion;
  final List<FlarumTag>? availableTags;

  const EditorPage({
    super.key,
    required this.api,
    this.discussion,
    this.availableTags,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _isLoadingTags = false;
  String? _tagError;
  
  List<FlarumTag> _tags = [];
  List<FlarumTag> _selectedTags = [];

  bool get isReply => widget.discussion != null;

  @override
  void initState() {
    super.initState();
    if (!isReply) {
      if (widget.availableTags != null && widget.availableTags!.isNotEmpty) {
        _tags = widget.availableTags!;
      } else {
        _fetchTags();
      }
    }
  }

  Future<void> _fetchTags() async {
    setState(() { _isLoadingTags = true; _tagError = null; });
    try {
      final res = await widget.api.getTags();
      if (mounted) {
        setState(() {
          _tags = parseTags(res);
          _isLoadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _tagError = '未能成功载入系统分类标签，网络通信链路可能存在异常。';
          _isLoadingTags = false;
        });
      }
    }
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请录入有效的内容数据')));
      return;
    }
    if (!isReply && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请设置有效的实体标题')));
      return;
    }
    if (!isReply && _selectedTags.isEmpty && _tags.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请为当前实体分配归属标签')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (isReply) {
        await widget.api.createPost(int.parse(widget.discussion!.id), content);
      } else {
        final tagIds = _selectedTags.map((t) => t.id).toList();
        await widget.api.createDiscussion(title: title, content: content, tagIds: tagIds);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('业务数据提交成功')));
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      String errMsg = '数据上传失败，请检视通信状态';
      if (e.response?.statusCode == 403) errMsg = '权限检验不通过：无权执行该写入操作';
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail'];
        }
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isReply ? '追加事务日志' : '新建系统业务实体', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('执行提交'),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          if (!isReply) _buildHeader(),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: isReply ? '请输入追加日志的内容信息 (系统已集成 Markdown 解析引擎)...' : '请输入详细的业务阐述 (系统已集成 Markdown 解析引擎)...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoadingTags) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_tagError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.wifi_off, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(_tagError!, style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                 setState(() { _isLoadingTags = true; _tagError = null; });
                 await Future.delayed(const Duration(milliseconds: 400));
                 _fetchTags();
              }, 
              child: const Text('重新发起通信请求')
            )
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '请输入具有高标识度的系统标题...',
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        ),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag.name),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
