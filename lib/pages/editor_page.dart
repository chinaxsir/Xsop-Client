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
  bool _isUploading = false; 
  
  List<FlarumTag> _tags = [];
  bool _isLoadingTags = false;
  
  FlarumTag? _selectedPrimaryTag;
  final List<FlarumTag> _selectedSecondaryTags = [];

  bool get _isNewPost => widget.discussion == null;

  @override
  void initState() {
    super.initState();
    if (widget.availableTags != null && widget.availableTags!.isNotEmpty) {
      _tags = widget.availableTags!;
    } else if (_isNewPost) {
      _fetchTags();
    }
  }

  Future<void> _fetchTags() async {
    setState(() => _isLoadingTags = true);
    try {
      final res = await widget.api.getTags();
      if (mounted) {
        setState(() {
          _tags = parseTags(res);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取标签失败，请检查网络')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingTags = false);
    }
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;

    if (selection.isValid) {
      final selectedText = selection.textInside(text);
      final newText = text.replaceRange(selection.start, selection.end, '$prefix$selectedText$suffix');
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + prefix.length + selectedText.length + suffix.length),
      );
    } else {
      final insertAt = text.length;
      _contentController.text = text + prefix + suffix;
      _contentController.selection = TextSelection.collapsed(offset: insertAt + prefix.length);
    }
  }

  void _applyTagTemplate(FlarumTag tag) {
    if (tag.template != null && tag.template!.isNotEmpty) {
      final currentText = _contentController.text.trim();
      if (currentText.isEmpty) {
        _contentController.text = tag.template!;
      } else if (!currentText.contains(tag.template!)) {
        _contentController.text += '\n\n${tag.template!}';
      }
    }
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内容不能为空')));
      return;
    }

    if (_isNewPost) {
      final title = _titleController.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题不能为空')));
        return;
      }
      
      final allowedTags = _tags.where((t) => t.canStartDiscussion).toList();
      final secondaryTags = allowedTags.where((t) => !t.isPrimary).toList();
      
      if (_selectedPrimaryTag == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发布失败：必须选择一个主标签')));
        return;
      }
      if (secondaryTags.isNotEmpty && _selectedSecondaryTags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发布失败：必须至少选择一个次标签')));
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      if (_isNewPost) {
        List<String> finalTagIds = [_selectedPrimaryTag!.id];
        finalTagIds.addAll(_selectedSecondaryTags.map((t) => t.id));

        await widget.api.createDiscussion(
          title: _titleController.text.trim(),
          content: content,
          tagIds: finalTagIds, 
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发布成功！')));
          Navigator.pop(context, true); 
        }
      } else {
        await widget.api.createPost(int.parse(widget.discussion!.id), content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回复成功！')));
          Navigator.pop(context, true); 
        }
      }
    } on DioException catch (e) {
      String errMsg = '提交失败，请检查网络或权限';
      if (e.response?.statusCode == 403) errMsg = '权限不足：您没有在当前板块发帖的权限';
      if (e.response?.statusCode == 401) errMsg = '身份验证过期：请重新登录';
      
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail'];
        }
      } catch (_) {}
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('发生未知错误，请重试')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    
    try {
      final fileName = pickedFile.name;
      final fileInfo = await widget.api.uploadFile(pickedFile.path, filename: fileName);
      if (fileInfo != null && fileInfo['url']!.isNotEmpty) {
        _insertMarkdown('\n![图片](', '${fileInfo['url']})\n');
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传未能获取到链接')));
      }
    } on DioException catch (e) {
      String errMsg = '图片上传失败';
      if (e.response?.statusCode == 403) errMsg = '权限不足：当前等级无权上传图片';
      else if (e.response?.statusCode == 413) errMsg = '文件过大：服务器拒绝接收（超过上传限制）';
      else if (e.response?.statusCode == 422) errMsg = '格式受限：不支持的图片格式';
      
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail'];
        }
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片上传异常: ${e.toString().split('\n').first}')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    setState(() => _isUploading = true);
    
    try {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;
      final fileInfo = await widget.api.uploadFile(filePath, filename: fileName);
      
      if (fileInfo != null && fileInfo['url']!.isNotEmpty) {
        final url = fileInfo['url']!;
        final name = fileInfo['baseName']!;
        _insertMarkdown('\n[$name](', '$url)\n');
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传未能获取到文件链接')));
      }
    } on DioException catch (e) {
      String errMsg = '附件上传失败';
      if (e.response?.statusCode == 403) errMsg = '权限不足：当前等级无权上传此后缀附件';
      else if (e.response?.statusCode == 413) errMsg = '文件过大：超过服务器单文件上传体积上限';
      else if (e.response?.statusCode == 422) errMsg = '格式受限：服务器不允许上传该类型附件';
      
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail'];
        }
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('附件上传异常: ${e.toString().split('\n').first}')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowedTags = _tags.where((t) => t.canStartDiscussion).toList();
    final primaryTags = allowedTags.where((t) => t.isPrimary).toList();
    final secondaryTags = allowedTags.where((t) => !t.isPrimary).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(_isNewPost ? '发布新主题' : '回复帖子', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton(
              onPressed: _isSubmitting || _isUploading || _isLoadingTags ? null : _submit,
              child: _isSubmitting || _isLoadingTags
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('发送'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isNewPost) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '请输入具有描述性的标题...',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
            
            if (_isLoadingTags)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            
            if (!_isLoadingTags && primaryTags.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择主标签 (必选 1 项)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: primaryTags.map((tag) {
                        final isSelected = _selectedPrimaryTag?.id == tag.id;
                        return ChoiceChip(
                          label: Text(tag.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedPrimaryTag = selected ? tag : null;
                              if (selected) _applyTagTemplate(tag);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            
            if (!_isLoadingTags && secondaryTags.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择次标签 (至少选 1 项)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: secondaryTags.map((tag) {
                        final isSelected = _selectedSecondaryTags.any((t) => t.id == tag.id);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedSecondaryTags.add(tag);
                                _applyTagTemplate(tag);
                              } else {
                                _selectedSecondaryTags.removeWhere((t) => t.id == tag.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          ],
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: _isNewPost ? '分享你的想法（支持 Markdown）...' : '写下你的回复...',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: const Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: _isUploading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file), 
                    onPressed: _isSubmitting || _isUploading ? null : _pickAndUploadAttachment,
                    tooltip: '插入任意附件',
                    color: Colors.grey.shade700,
                  ),
                  IconButton(
                    icon: _isUploading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined), 
                    onPressed: _isSubmitting || _isUploading ? null : _pickAndUploadImage,
                    tooltip: '插入图片',
                    color: Colors.grey.shade700,
                  ),
                  // [核心修复：全面补齐网页端发帖功能栏]
                  _buildToolbarBtn(Icons.title, () => _insertMarkdown('### ', ''), '标题'),
                  _buildToolbarBtn(Icons.format_bold, () => _insertMarkdown('**', '**'), '加粗'),
                  _buildToolbarBtn(Icons.format_italic, () => _insertMarkdown('*', '*'), '斜体'),
                  _buildToolbarBtn(Icons.format_strikethrough, () => _insertMarkdown('~~', '~~'), '删除线'),
                  _buildToolbarBtn(Icons.format_quote, () => _insertMarkdown('\n> ', '\n'), '引用'),
                  _buildToolbarBtn(Icons.warning_amber_outlined, () => _insertMarkdown('>! ', ' !<'), '防透剧(折叠)'),
                  _buildToolbarBtn(Icons.code, () => _insertMarkdown('\n```\n', '\n```\n'), '代码块'),
                  _buildToolbarBtn(Icons.link, () => _insertMarkdown('[', '](https://)'), '插入链接'),
                  
                  _buildToolbarBtn(Icons.format_list_bulleted, () => _insertMarkdown('\n- ', ''), '无序列表'),
                  _buildToolbarBtn(Icons.format_list_numbered, () => _insertMarkdown('\n1. ', ''), '有序列表'),
                  _buildToolbarBtn(Icons.monetization_on_outlined, () => _insertMarkdown('[charge=10]', '[/charge]'), '插入付费阅读'),
                  _buildToolbarBtn(Icons.alternate_email, () => _insertMarkdown('@', ''), '提及(@)用户'),
                  _buildToolbarBtn(Icons.emoji_emotions_outlined, () => _insertMarkdown('😀', ''), '插入表情'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolbarBtn(IconData icon, VoidCallback onPressed, String tooltip) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
      color: Colors.grey.shade700,
      iconSize: 22,
    );
  }
}
