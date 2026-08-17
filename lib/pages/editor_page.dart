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

  // [阶梯式交互核心状态]
  bool _hasRevealedEditor = false;

  bool get isReply => widget.discussion != null;
  bool get isEdit => widget.postToEdit != null;
  bool get hasSelectedPrimary => _selectedTags.any((t) => t.isPrimary);

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _contentController.text = widget.initialContent ?? '';
    }
    // 如果是回帖或编辑，直接显示正文编辑框
    if (isReply || isEdit) {
      _hasRevealedEditor = true;
    } else {
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
    
    if (!isReply && !isEdit) {
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题不能为空')));
        return;
      }
      final primaryTags = _tags.where((t) => t.isPrimary).toList();
      if (primaryTags.isNotEmpty && _selectedTags.where((t) => t.isPrimary).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('必须选择 1 个主标签')));
        return;
      }
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

  // [联动式标签处理机制]
  void _handleTagSelection(FlarumTag tag, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (tag.isPrimary) {
          // 主标签单选互斥
          _selectedTags.removeWhere((t) => t.isPrimary);
          _selectedTags.add(tag);
          
          if (tag.isChild) {
            try {
              final parent = _tags.firstWhere((t) => t.id == tag.parentId);
              _selectedTags.add(parent);
            } catch (_) {}
          }
          
          // 如果系统根本没有次级标签，选完主标签就直接弹开正文框
          final secondaryTags = _tags.where((t) => !t.isPrimary).toList();
          if (secondaryTags.isEmpty) {
             _hasRevealedEditor = true;
          }
        } else {
          // 次级标签最多选两个
          final secondaryCount = _selectedTags.where((t) => !t.isPrimary).length;
          if (secondaryCount >= 2 && !_selectedTags.contains(tag)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('最多只能选择 2 个次级标签')));
            return; 
          }
          _selectedTags.add(tag);
          if (tag.isChild) {
            try {
              final parent = _tags.firstWhere((t) => t.id == tag.parentId);
              if (!_selectedTags.contains(parent)) {
                 _selectedTags.add(parent);
              }
            } catch (_) {}
          }
          // 一旦选了次级标签，立刻弹开正文录入框
          _hasRevealedEditor = true;
        }

        // 自动拉取提现模板
        if (tag.slug.toLowerCase().contains('cash') || tag.name.contains('Cash') || tag.name.contains('收费')) {
           if (!_contentController.text.contains('提现申请核验单')) {
              _contentController.text += '\n💸 提现申请核验单\n*请仔细核对以下信息，防刷单核对用。*\n\n- **提现金额 (XSD): ** [填写纯数字，最低100]\n- **收款方式: ** [填写方式，如支付宝、微信]\n- **收款账号: ** [填写完整账号]\n- **真实姓名: ** [填写您的真实姓名]\n';
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已自动拉取提现模板')));
           }
        }
      } else {
        _selectedTags.remove(tag);
        // 如果取消父级，子级一并取消
        _selectedTags.removeWhere((t) => t.isChild && t.parentId == tag.id);
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
              child: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('发送', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          // [核心重构：滚动承载视窗] 彻底解决输入框被挤死的问题
          Expanded(
            child: _buildScrollableBody(),
          ),
          _buildToolbar(),
        ],
      ),
    );
  }

  // 承载了标题、阶梯标签和自动扩展的正文输入框
  Widget _buildScrollableBody() {
    if (_isLoadingTags) return const Center(child: CircularProgressIndicator());

    final primaryTags = _tags.where((t) => t.isPrimary).toList();
    final secondaryTags = _tags.where((t) => !t.isPrimary).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        if (!isReply && !isEdit) ...[
          // --- 模块 1：标题 ---
          const Text('输入标题', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(hintText: '标题写在这里...', border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), hintStyle: TextStyle(color: Colors.grey.shade400)),
            ),
          ),
          const SizedBox(height: 28),

          // --- 模块 2：主标签 ---
          if (primaryTags.isNotEmpty) ...[
            const Text('第一步：选择主版块 (必选 1 个)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 12),
            _buildTagGroup(primaryTags),
          ],

          // --- 模块 3：次级标签 (选中主标签后带动画弹开) ---
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: (hasSelectedPrimary && secondaryTags.isNotEmpty) ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('第二步：附加话题 (最多选 2 个)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
                    // 贴心设计：如果用户不想选次级标签，可以直接点跳过拉出正文框
                    if (!_hasRevealedEditor)
                      InkWell(
                        onTap: () => setState(() => _hasRevealedEditor = true),
                        child: Text('跳过，直接写正文', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                      )
                  ],
                ),
                const SizedBox(height: 12),
                _buildTagGroup(secondaryTags),
              ],
            ) : const SizedBox(width: double.infinity),
          ),
        ],

        // --- 模块 4：正文编辑框 (触发条件后带动画弹开) ---
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: _hasRevealedEditor ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isReply && !isEdit) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 24),
                const Text('第三步：编写正文', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 12),
              ],
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300)
                ),
                child: TextField(
                  controller: _contentController,
                  minLines: 12, // 保证它具有足够高的初始触控面积
                  maxLines: null, // 无限向下延伸
                  style: const TextStyle(fontSize: 16, height: 1.6),
                  decoration: InputDecoration(
                    hintText: '分享你的想法 (支持 Markdown 语法)...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
              ),
              const SizedBox(height: 60), // 给底部留足留白，防止被键盘遮挡
            ],
          ) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // [告别紧凑：高颜值卡片化区块引擎]
  Widget _buildTagGroup(List<FlarumTag> tags) {
    final parentTags = tags.where((t) => !t.isChild).toList();
    final orphanChildren = tags.where((t) => t.isChild && !parentTags.any((p) => p.id == t.parentId)).toList();

    List<Widget> columns = [];
    for (final parent in parentTags) {
      final children = tags.where((t) => t.isChild && t.parentId == parent.id).toList();
      columns.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50, // 微浅灰底色
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTagChip(parent),
              if (children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 12),
                  child: Wrap(
                    spacing: 12, // 加大横向间距
                    runSpacing: 12, // 加大纵向间距
                    children: children.map((c) => _buildTagChip(c)).toList(),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    if (orphanChildren.isNotEmpty) {
      columns.add(
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: orphanChildren.map((c) => _buildTagChip(c)).toList(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: columns,
    );
  }

  Widget _buildTagChip(FlarumTag tag) {
    final isSelected = _selectedTags.contains(tag);
    return FilterChip(
      label: Text(tag.name, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 增加触摸面积
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
      backgroundColor: Colors.white,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.primary,
      onSelected: (val) => _handleTagSelection(tag, val),
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
                onPressed: () => _insertMarkdown('[pay amount=1 id=0]id为空或0将创建新的付费阅读，不修改原有的id则已经付费的用户可继续阅读', '[\/pay]'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
