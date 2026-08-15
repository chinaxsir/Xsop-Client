// 文件位置: lib/pages/editor_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';

class EditorPage extends StatefulWidget {
  final ApiClient api;
  final Discussion? discussion;
  final List<FlarumTag>? availableTags;
  final Map<String, dynamic>? postToEdit; 
  final String? initialContent;

  const EditorPage({
    super.key,
    required this.api,
    this.discussion,
    this.availableTags,
    this.postToEdit,
    this.initialContent,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _isUploading = false;
  bool _isLoadingTags = false;
  String? _tagError;
  
  List<FlarumTag> _tags = [];
  List<FlarumTag> _selectedTags = [];

  bool get isReply => widget.discussion != null;
  bool get isEdit => widget.postToEdit != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _contentController.text = widget.initialContent ?? '';
    }
    if (!isReply && !isEdit) {
      if (widget.availableTags != null && widget.availableTags!.isNotEmpty) {
        _categorizeTags(widget.availableTags!);
      } else {
        _fetchTags();
      }
    }
  }

  void _categorizeTags(List<FlarumTag> tags) {
    _tags = tags;
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
      if (mounted) setState(() { _tagError = '无法获取板块标签，请检查网络。'; _isLoadingTags = false; });
    }
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文不能为空')));
      return;
    }
    if (!isReply && !isEdit && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (isEdit) {
        final postId = int.parse(widget.postToEdit!['id']);
        await widget.api.editPost(postId, content);
      } else if (isReply) {
        await widget.api.createPost(int.parse(widget.discussion!.id), content);
      } else {
        final tagIds = _selectedTags.map((t) => t.id).toList();
        await widget.api.createDiscussion(title: title, content: content, tagIds: tagIds);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? '编辑成功' : (isReply ? '回复成功' : '发布成功'))));
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      String errMsg = '提交失败：操作被服务器拒绝';
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail']; // 将真实的错误原因直接反馈在 UI 上
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

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;
    _uploadLogic(pickedFile.path, pickedFile.name, true);
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path != null) {
        _uploadLogic(file.path!, file.name, false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选择文件异常')));
    }
  }

  // [深度暴露：将服务器的上传报错赤裸裸地呈现出来]
  Future<void> _uploadLogic(String path, String fileName, bool isImage) async {
    setState(() => _isUploading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在执行上传...')));
    try {
      final uploadRes = await widget.api.uploadFile(path, filename: fileName);
      if (uploadRes != null && uploadRes['url'] != null) {
        final url = uploadRes['url'];
        final baseName = uploadRes['baseName'];
        if (isImage) {
          _insertMarkdown('![$baseName]($url)', '\n');
        } else {
          _insertMarkdown('[$baseName]($url)', '\n');
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件上传成功！')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('接口异常：服务器返回了空数据。')));
      }
    } on DioException catch (e) {
      String errMsg = '接口拒绝上传。';
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail']; 
        }
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传阻断：$errMsg')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _handleTagSelection(FlarumTag tag, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTags.add(tag);
        if (tag.slug.toLowerCase().contains('cash') || tag.name.contains('Cash') || tag.name.contains('收费')) {
           if (!_contentController.text.contains('提现申请核验单')) {
              _contentController.text += '''
💸 提现申请核验单
*请仔细核对以下信息，防刷单核对用。*

- **提现金额 (XSD): ** [填写纯数字，最低100]
- **收款方式: ** [填写方式，如支付宝、微信]
- **收款账号: ** [填写完整账号]
- **真实姓名: ** [填写您的真实姓名]
''';
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已自动拉取模板')));
           }
        }
      } else {
        _selectedTags.remove(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    String pageTitle = isEdit ? '编辑内容' : (isReply ? '回复主题' : '发布新主题');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(pageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: FilledButton(
              onPressed: (_isSubmitting || _isUploading) ? null : _submit,
              child: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('发送'),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          if (!isReply && !isEdit) _buildHeader(),
          if (_isUploading) const LinearProgressIndicator(minHeight: 2),
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
              IconButton(icon: const Icon(Icons.image_outlined, color: Colors.black87), tooltip: '上传图片', onPressed: _isUploading ? null : _pickAndUploadImage),
              IconButton(icon: const Icon(Icons.attach_file, color: Colors.black87), tooltip: '上传附件', onPressed: _isUploading ? null : _pickAndUploadFile),
              Container(width: 1, height: 24, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
              TextButton.icon(
                icon: const Icon(Icons.lock_outline, size: 18, color: Colors.orange),
                label: const Text('付费阅读', style: TextStyle(color: Colors.orange)),
                onPressed: () => _insertMarkdown('[charge=10]\n在这里输入付费隐藏内容...\n', '[/charge]'),
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
