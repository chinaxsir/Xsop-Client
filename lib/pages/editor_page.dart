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
  
  List<FlarumTag> _primaryTags = [];
  List<FlarumTag> _secondaryTags = [];
  List<FlarumTag> _selectedTags = [];

  bool get isReply => widget.discussion != null;

  @override
  void initState() {
    super.initState();
    if (!isReply) {
      if (widget.availableTags != null && widget.availableTags!.isNotEmpty) {
        _categorizeTags(widget.availableTags!);
      } else {
        _fetchTags();
      }
    }
  }

  void _categorizeTags(List<FlarumTag> tags) {
    _primaryTags = tags.where((t) => t.isPrimary).toList();
    _secondaryTags = tags.where((t) => !t.isPrimary).toList();
  }

  Future<void> _fetchTags() async {
    setState(() { _isLoadingTags = true; _tagError = null; });
    try {
      final res = await widget.api.getTags();
      if (mounted) {
        setState(() {
          _categorizeTags(parseTags(res));
          _isLoadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _tagError = '无法获取板块标签，网络可能已断开。';
          _isLoadingTags = false;
        });
      }
    }
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文内容不能为空')));
      return;
    }
    if (!isReply && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入具有描述性的标题')));
      return;
    }
    // Flarum 网页版通常强制要求至少选择一个主标签
    if (!isReply && _selectedTags.where((t) => t.isPrimary).isEmpty && _primaryTags.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少选择一个主标签')));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isReply ? '回复成功' : '发布成功')));
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      String errMsg = '发布失败，请检查网络';
      if (e.response?.statusCode == 403) errMsg = '权限不足：您无权在当前板块发帖或回复';
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

  // [富文本工具扩展] 插入格式化代码
  void _insertMarkdown(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    int start = selection.start;
    int end = selection.end;
    if (start == -1 || end == -1) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, '$prefix${text.substring(start, end)}$suffix');
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + (end - start)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isReply ? '回复主题' : '发布新主题', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('发送'),
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
                  hintText: '分享你的想法（支持 Markdown 语法）...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                ),
              ),
            ),
          ),
          _buildToolbar(),
        ],
      ),
    );
  }

  // [核心修复：还原原汁原味的 Flarum 底部功能拓展条（上传、发图、收费）]
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.format_bold, color: Colors.black87),
                tooltip: '加粗',
                onPressed: () => _insertMarkdown('**', '**'),
              ),
              IconButton(
                icon: const Icon(Icons.format_italic, color: Colors.black87),
                tooltip: '斜体',
                onPressed: () => _insertMarkdown('*', '*'),
              ),
              IconButton(
                icon: const Icon(Icons.link, color: Colors.black87),
                tooltip: '插入链接',
                onPressed: () => _insertMarkdown('[', '](https://)'),
              ),
              Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
              IconButton(
                icon: const Icon(Icons.image_outlined, color: Colors.black87),
                tooltip: '插入图片',
                onPressed: () {
                  // TODO: 后续可在此接入 image_picker 进行图片直传
                  _insertMarkdown('![图片描述](', ')');
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已插入图片语法，请填入图片链接')));
                },
              ),
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.black87),
                tooltip: '上传附件',
                onPressed: () {
                  // TODO: 后续可在此接入 file_picker 进行文件直传
                  _insertMarkdown('[点击下载附件](', ')');
                },
              ),
              Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
              TextButton.icon(
                icon: const Icon(Icons.lock_outline, size: 18, color: Colors.orange),
                label: const Text('付费阅读', style: TextStyle(color: Colors.orange)),
                onPressed: () {
                  _insertMarkdown('[charge=10]\n在这里输入需要付费查阅的核心内容...\n', '[/charge]');
                },
              ),
            ],
          ),
        ),
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
              child: const Text('重新获取')
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
              hintText: '请输入具有描述性的标题...',
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        ),
        if (_primaryTags.isNotEmpty || _secondaryTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_primaryTags.isNotEmpty) ...[
                  Text('主标签 (必选)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _primaryTags.map((t) => _buildTagChip(t)).toList(),
                  ),
                ],
                if (_secondaryTags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('次级标签 (可选)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _secondaryTags.map((t) => _buildTagChip(t)).toList(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(FlarumTag tag) {
    final isSelected = _selectedTags.contains(tag);
    return FilterChip(
      label: Text(tag.name),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            // Flarum 一般限制只能选一个主标签，我们在前端可以放宽或者严格限制
            if (tag.isPrimary) {
               _selectedTags.removeWhere((t) => t.isPrimary);
            }
            _selectedTags.add(tag);
          } else {
            _selectedTags.remove(tag);
          }
        });
      },
    );
  }
}
