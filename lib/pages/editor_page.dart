// 文件位置: lib/pages/editor_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart'; // 引入真实的媒体选择器
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
  bool _isUploading = false; // 真实上传状态
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
      if (mounted) setState(() { _tagError = '无法获取板块标签，请下拉重试。'; _isLoadingTags = false; });
    }
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入内容')));
      return;
    }
    if (!isReply && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入标题')));
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
      String errMsg = '发布失败：网络或权限异常';
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

  // [深刻修复：接入手机底层相册，真枪实弹上传到服务器！]
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上传图片，请稍候...')));

    try {
      final uploadRes = await widget.api.uploadFile(pickedFile.path, filename: pickedFile.name);
      if (uploadRes != null && uploadRes['url'] != null) {
        // 成功获取服务器 URL，回填至输入框
        final url = uploadRes['url'];
        final baseName = uploadRes['baseName'];
        _insertMarkdown('![$baseName]($url)', '\n');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片上传成功！')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片上传失败，服务器返回空数据。')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传异常：可能未配置图床或文件超出限制')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _handleTagSelection(FlarumTag tag, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTags.add(tag);
        if (tag.slug.toLowerCase().contains('cash') || tag.name.contains('收费')) {
           if (!_contentController.text.contains('[charge=')) {
              _contentController.text += '\n[charge=10]\n隐藏内容\n[/charge]\n';
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已自动拉取付费阅读模板')));
           }
        }
      } else {
        _selectedTags.remove(tag);
      }
    });
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
              onPressed: (_isSubmitting || _isUploading) ? null : _submit,
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
          if (_isUploading) const LinearProgressIndicator(minHeight: 2), // 顶部加入真实的上传进度条
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: '分享你的想法 (支持 Markdown 语法)...',
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

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.format_bold, color: Colors.black87), tooltip: '加粗', onPressed: () => _insertMarkdown('**', '**')),
              IconButton(icon: const Icon(Icons.format_italic, color: Colors.black87), tooltip: '斜体', onPressed: () => _insertMarkdown('*', '*')),
              IconButton(icon: const Icon(Icons.link, color: Colors.black87), tooltip: '插入链接', onPressed: () => _insertMarkdown('[', '](https://)')),
              Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
              
              // [深刻修复：真实的图片上传按钮接入]
              IconButton(
                icon: const Icon(Icons.image_outlined, color: Colors.black87), 
                tooltip: '上传图片', 
                onPressed: _isUploading ? null : _pickAndUploadImage,
              ),
              
              Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
              TextButton.icon(
                icon: const Icon(Icons.lock_outline, size: 18, color: Colors.orange),
                label: const Text('付费阅读', style: TextStyle(color: Colors.orange)),
                onPressed: () => _insertMarkdown('[charge=10]\n隐藏的付费内容\n', '[/charge]'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoadingTags) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final primaryTags = _tags.where((t) => t.isPrimary).toList();
    final secondaryTags = _tags.where((t) => !t.isPrimary).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(hintText: '请输入标题...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey.shade400)),
          ),
        ),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (primaryTags.isNotEmpty) ...[
                  Text('主标签 (权限区)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: primaryTags.map((t) => _buildTagChip(t)).toList()),
                ],
                if (secondaryTags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('次级标签', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: secondaryTags.map((t) => _buildTagChip(t)).toList()),
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
      onSelected: (val) => _handleTagSelection(tag, val),
    );
  }
}
