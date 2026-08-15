// 文件位置: lib/pages/discussion_detail_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; 
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:xsop_forum/api/api_client.dart';
import 'package:xsop_forum/models/flarum_models.dart';
import 'package:xsop_forum/pages/home_page.dart' show formatRelativeTime;
import 'package:xsop_forum/pages/editor_page.dart';
import 'package:xsop_forum/pages/login_page.dart';

class DiscussionDetailPage extends StatefulWidget {
  final ApiClient api;
  final Discussion discussion;

  const DiscussionDetailPage({
    super.key,
    required this.api,
    required this.discussion,
  });

  @override
  State<DiscussionDetailPage> createState() => _DiscussionDetailPageState();
}

class _DiscussionDetailPageState extends State<DiscussionDetailPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _posts = [];
  Map<String, dynamic> _usersMap = {};

  @override
  void initState() {
    super.initState();
    _loadDiscussionDetail();
  }

  Future<void> _loadDiscussionDetail() async {
    try {
      final data = await widget.api.getDiscussion(int.parse(widget.discussion.id));
      final included = data['included'] as List<dynamic>? ?? [];
      final Map<String, dynamic> users = {};
      final List<dynamic> postsList = [];

      for (var item in included) {
        if (item['type'] == 'users') {
          users[item['id']] = parseUser({'data': item, 'included': included}, widget.api.baseUrl);
        } else if (item['type'] == 'posts' && item['attributes']?['contentType'] == 'comment') {
          postsList.add(item);
        }
      }

      postsList.sort((a, b) {
        final aNum = a['attributes']['number'] as int? ?? 0;
        final bNum = b['attributes']['number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });

      setState(() {
        _usersMap = users;
        _posts = postsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '无法加载帖子详情，请检查网络';
        _isLoading = false;
      });
    }
  }

  // [修复图2：精准提取 Flarum 原生 content Markdown 作为编辑框初始值]
  Future<void> _showEditDialog(int postId, int index) async {
    final post = _posts[index];
    final initialContent = post['attributes']?['content']?.toString() ?? '';
    final editController = TextEditingController(text: initialContent);

    await showDialog(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Text('编辑回复', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: TextField(
                  controller: editController,
                  maxLines: null,
                  minLines: 4,
                  decoration: const InputDecoration(
                    hintText: '修改内容（支持 Markdown）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  onPressed: isSubmitting ? null : () async {
                    if (editController.text.trim().isEmpty) return;
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.editPost(postId, editController.text.trim());
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('编辑成功')));
                        setState(() => _isLoading = true);
                        _loadDiscussionDetail(); 
                      }
                    } on DioException catch (e) {
                       String errMsg = '编辑失败';
                       try {
                         final errs = e.response?.data['errors'];
                         if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
                           errMsg = errs[0]['detail'];
                         }
                       } catch (_) {}
                       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
                    } finally {
                      if (mounted) setStateDialog(() => isSubmitting = false);
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('保存修改'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  // [修复图1：调用原生打赏接口，直通服务端报错日志]
  Future<void> _showTipDialog(int postId) async {
    final amountController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Row(children: [Icon(Icons.card_giftcard, color: Colors.orange), SizedBox(width: 8), Text('打赏作者')]),
              content: TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '请输入打赏金额', border: OutlineInputBorder(), suffixText: 'XSD'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: isSubmitting ? null : () async {
                    final amount = int.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效金额')));
                       return;
                    }
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.tipPost(postId, amount);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('打赏成功，感谢支持！')));
                      }
                    } on DioException catch (e) {
                      if (mounted) {
                         String errMsg = '打赏异常，余额可能不足或未开通接口';
                         try {
                           final errs = e.response?.data['errors'];
                           if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
                             errMsg = errs[0]['detail'];
                           }
                         } catch (_) {}
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
                         Navigator.pop(context); 
                      }
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('确认打赏'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showVoteDetails(int index) {
    final post = _posts[index];
    final attrs = post['attributes'] ?? {};
    final upvotes = attrs['upvotes'] ?? attrs['likesCount'] ?? attrs['points'] ?? attrs['votes'] ?? 0;
    
    showDialog(
      context: context,
      builder: (context) {
         return AlertDialog(
           backgroundColor: Colors.white,
           surfaceTintColor: Colors.transparent,
           title: const Text('互动详情'),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               ListTile(
                 leading: const Icon(Icons.thumb_up, color: Colors.green),
                 title: const Text('支持 / 获赞数'),
                 trailing: Text('$upvotes', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
               ),
               const SizedBox(height: 16),
               const Text('具体参与用户列表需前往网页端查看。', style: TextStyle(color: Colors.grey, fontSize: 12)),
             ]
           ),
           actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))]
         );
      }
    );
  }

  Future<void> _showWarnDialog(int postId, String? userIdStr) async {
    if (userIdStr == null) return;
    final userId = int.parse(userIdStr);
    final strikesCtrl = TextEditingController(text: '1');
    final publicCtrl = TextEditingController();
    final privateCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Row(children: [Icon(Icons.warning_amber, color: Colors.redAccent), SizedBox(width: 8), Text('下发违规警告')]),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('严重程度：记几分？', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: strikesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16),
                    const Text('用户批注。为什么警告？（对用户可见）', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: publicCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    const Text('管理员备注。（仅对管理员可见）', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: privateCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: isSubmitting ? null : () async {
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.warnUser(
                        userId, 
                        postId: postId,
                        strikes: int.tryParse(strikesCtrl.text) ?? 0,
                        publicComment: publicCtrl.text.trim(),
                        privateComment: privateCtrl.text.trim(),
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('警告下发成功！')));
                      }
                    } on DioException catch (e) {
                       String errMsg = '警告下发失败，权限不足';
                       try {
                         final errs = e.response?.data['errors'];
                         if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
                           errMsg = errs[0]['detail'];
                         }
                       } catch (_) {}
                       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
                    } finally {
                      if (mounted) setStateDialog(() => isSubmitting = false);
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('确认警告'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _toggleLike(int index) async {
    final isLoggedIn = await widget.api.isLoggedIn;
    if (!isLoggedIn) {
      _promptLogin();
      return;
    }
    final post = _posts[index];
    final postId = int.parse(post['id']);
    final attrs = post['attributes'] ?? {};
    final bool currentIsLiked = attrs['isLiked'] ?? false;
    final int currentLikesCount = attrs['likesCount'] ?? 0;

    setState(() {
      _posts[index]['attributes']['isLiked'] = !currentIsLiked;
      _posts[index]['attributes']['likesCount'] = currentIsLiked ? currentLikesCount - 1 : currentLikesCount + 1;
    });

    try {
      await widget.api.likePost(postId, !currentIsLiked);
    } on DioException catch (_) {
      if (mounted) {
        setState(() {
          _posts[index]['attributes']['isLiked'] = currentIsLiked;
          _posts[index]['attributes']['likesCount'] = currentLikesCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作权限不足')));
      }
    }
  }

  Future<void> _deletePost(int postId, int index) async {
    try {
      await widget.api.deletePost(postId);
      if (mounted) {
        setState(() { _posts.removeAt(index); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除成功')));
      }
    } on DioException catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败：权限不足')));
    }
  }

  Future<void> _showReportDialog(int postId) async {
    String selectedReason = 'spam';
    final detailController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Text('举报该内容'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile(title: const Text('垃圾广告'), value: 'spam', groupValue: selectedReason, onChanged: (val) => setStateDialog(() => selectedReason = val.toString())),
                    RadioListTile(title: const Text('违规内容'), value: 'inappropriate', groupValue: selectedReason, onChanged: (val) => setStateDialog(() => selectedReason = val.toString())),
                    RadioListTile(title: const Text('偏离主题'), value: 'off_topic', groupValue: selectedReason, onChanged: (val) => setStateDialog(() => selectedReason = val.toString())),
                    const SizedBox(height: 8),
                    TextField(controller: detailController, decoration: const InputDecoration(hintText: '补充详细原因（选填）', border: OutlineInputBorder()), maxLines: 2),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      await widget.api.reportPost(postId, selectedReason, detailController.text);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('举报已提交，感谢您的反馈')));
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('权限不足：无法举报')));
                    }
                  },
                  child: const Text('提交'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openReplyEditor() async {
    final isLoggedIn = await widget.api.isLoggedIn;
    if (!isLoggedIn) {
      _promptLogin();
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorPage(
          api: widget.api,
          discussion: widget.discussion,
        ),
      ),
    );
    if (result == true) {
      setState(() => _isLoading = true);
      _loadDiscussionDetail();
    }
  }

  void _promptLogin() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => LoginPage(api: widget.api)));
    if (result == true) {
      setState(() => _isLoading = true);
      _loadDiscussionDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.discussion.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
          ),
          child: InkWell(
            onTap: _openReplyEditor,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Text('写下你的回复...', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _posts.length,
      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
      itemBuilder: (context, index) {
        final post = _posts[index];
        final postId = int.parse(post['id']);
        final attrs = post['attributes'] ?? {};
        
        final userIdStr = post['relationships']?['user']?['data']?['id']?.toString();
        final FlarumUser? user = userIdStr != null ? _usersMap[userIdStr] : null;
        
        final username = user?.displayName.isNotEmpty == true ? user!.displayName : (user?.username ?? '已注销');
        final avatarUrl = user?.avatarUrl;
        final timeStr = attrs['createdAt'] as String?;
        final time = timeStr != null ? DateTime.tryParse(timeStr) : null;
        
        final htmlContent = attrs['contentHtml'] as String? ?? '';
        final isLiked = attrs['isLiked'] ?? false;
        final likesCount = attrs['likesCount'] ?? 0;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade100,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null ? Icon(Icons.person, size: 20, color: Theme.of(context).colorScheme.primary) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            if (user != null && user.groups.isNotEmpty) buildUserBadges(user.groups),
                          ],
                        ),
                        if (time != null) const SizedBox(height: 2),
                        if (time != null) Text(formatRelativeTime(time), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('#${attrs['number']}', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              HtmlWidget(htmlContent, textStyle: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () => _toggleLike(index),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 16, color: isLiked ? Theme.of(context).colorScheme.primary : Colors.grey.shade700),
                          if (likesCount > 0) ...[const SizedBox(width: 4), Text('$likesCount', style: TextStyle(color: isLiked ? Theme.of(context).colorScheme.primary : Colors.grey.shade700, fontSize: 13))]
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _openReplyEditor,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('回复', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500))),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: Colors.grey.shade500),
                    color: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) async {
                      final isLoggedIn = await widget.api.isLoggedIn;
                      if (!isLoggedIn) {
                        _promptLogin();
                        return;
                      }
                      if (value == 'report') _showReportDialog(postId);
                      else if (value == 'delete') _deletePost(postId, index);
                      else if (value == 'edit') _showEditDialog(postId, index);
                      else if (value == 'tip') _showTipDialog(postId);
                      else if (value == 'vote') _showVoteDetails(index);
                      else if (value == 'warn') _showWarnDialog(postId, userIdStr);
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18), SizedBox(width: 8), Text('举报')])),
                      const PopupMenuItem<String>(value: 'tip', child: Row(children: [Icon(Icons.card_giftcard, size: 18, color: Colors.orange), SizedBox(width: 8), Text('打赏')])),
                      const PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('编辑')])),
                      const PopupMenuItem<String>(value: 'vote', child: Row(children: [Icon(Icons.how_to_vote_outlined, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('互动详情')])),
                      const PopupMenuItem<String>(value: 'warn', child: Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('下发警告')])),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }
}
