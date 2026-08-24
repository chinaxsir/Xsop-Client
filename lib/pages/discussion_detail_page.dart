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
  
  Map<String, dynamic> _discussionData = {};
  List<dynamic> _included = [];
  
  FlarumUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadDiscussionDetail();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final userId = await widget.api.getUserId();
    if (userId != null) {
      try {
        final res = await widget.api.getUser(userId);
        if (mounted) setState(() => _currentUser = parseUser(res, widget.api.baseUrl));
      } catch (_) {}
    }
  }

  bool get _isModerator {
    if (_currentUser == null) return false;
    return _currentUser!.groups.any((g) => g.id == '1' || g.id == '4');
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
        _discussionData = data['data'] ?? {};
        _included = included;
        _usersMap = users;
        _posts = postsList;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is DioException) {
            String msg = '连接异常 (状态码: ${e.response?.statusCode})';
            _error = msg;
          } else {
            _error = '系统错误：${e.toString()}';
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _renameDiscussion() async {
    final String currentTitle = _discussionData['attributes']?['title'] ?? widget.discussion.title;
    final ctrl = TextEditingController(text: currentTitle);
    
    await showDialog(
      context: context,
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: const Text('重命名主题', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: '请输入新的主题标题', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.grey))),
              FilledButton(
                onPressed: isSubmitting ? null : () async {
                  final newTitle = ctrl.text.trim();
                  if (newTitle.isEmpty || newTitle == currentTitle) return;
                  
                  setStateDialog(() => isSubmitting = true);
                  try {
                    await widget.api.updateDiscussion(int.parse(widget.discussion.id), title: newTitle);
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：标题修改已保存。')));
                    }
                  } catch (_) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：修改指令执行失败。')));
                  } finally {
                    if (mounted) setStateDialog(() => isSubmitting = false);
                  }
                  _loadDiscussionDetail();
                },
                child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                    : const Text('确认修改'),
              ),
            ],
          )
        );
      }
    );
  }

  Future<void> _toggleSticky(bool isSticky) async {
    setState(() => _isLoading = true);
    try {
       await widget.api.updateDiscussion(int.parse(widget.discussion.id), isSticky: isSticky);
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：状态已更新。')));
    } catch (_) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：操作未能生效。')));
    }
    _loadDiscussionDetail();
  }

  Future<void> _toggleLock(bool isLocked) async {
    setState(() => _isLoading = true);
    try {
       await widget.api.updateDiscussion(int.parse(widget.discussion.id), isLocked: isLocked);
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：锁定状态已变更。')));
    } catch (_) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：操作未能生效。')));
    }
    _loadDiscussionDetail();
  }

  Future<void> _deleteDiscussion() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('删除主题警告', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text('系统警告：您即将删除此主题及其从属的所有回复数据。此项变更将被永久执行且不可撤销，请确认继续。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('确认删除')
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;
    
    setState(() => _isLoading = true);
    try {
       await widget.api.deleteDiscussion(int.parse(widget.discussion.id));
       if (mounted) {
         Navigator.pop(context, true); 
       }
    } catch (_) {
       if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：删除指令被拒绝。')));
       }
    }
  }

  Future<void> _editTags() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('主题标签管理'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '输入标签节点ID (逗号分隔)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          FilledButton(onPressed: () async {
             final ids = ctrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
             if (ids.isEmpty) return;
             Navigator.pop(ctx);
             setState(() => _isLoading = true);
             try {
                await widget.api.updateDiscussion(int.parse(widget.discussion.id), tagIds: ids);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：节点归属已更替。')));
             } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：操作未能生效。')));
             }
             _loadDiscussionDetail();
          }, child: const Text('保存修改')),
        ],
      )
    );
  }

  Future<void> _openEditorForEdit(int index) async {
    final post = _posts[index];
    final postId = post['id'];
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在读取数据，请稍候...')));
    String rawContent = post['attributes']?['content']?.toString() ?? '';
    
    try {
       final res = await widget.api.getDynamicList('/api/posts/$postId');
       rawContent = res['data']?['attributes']?['content']?.toString() ?? rawContent;
    } catch (_) {}

    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorPage(
          api: widget.api,
          postToEdit: post, 
          initialContent: rawContent,
        ),
      ),
    );
    
    if (result == true) {
      setState(() => _isLoading = true);
      _loadDiscussionDetail();
    }
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
           title: const Text('交互记录详情'),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               ListTile(
                 leading: const Icon(Icons.thumb_up, color: Colors.green),
                 title: const Text('正向交互数'),
                 trailing: Text('$upvotes', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
               ),
             ]
           ),
           actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭视窗'))]
         );
      }
    );
  }

  Future<void> _showReportDialog(int postId) async {
    if (_currentUser == null) return;
    final detailCtrl = TextEditingController();
    String reason = 'spam'; 

    await showDialog(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Row(children: [Icon(Icons.report_problem_outlined, color: Colors.orange), SizedBox(width: 8), Text('内容违规报告')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'spam', child: Text('涉嫌垃圾广告')),
                      DropdownMenuItem(value: 'inappropriate', child: Text('涉嫌违背准则')),
                      DropdownMenuItem(value: 'off_topic', child: Text('偏离交流主题')),
                    ],
                    onChanged: (v) => setStateDialog(() => reason = v ?? 'spam'),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: detailCtrl, maxLines: 3, decoration: const InputDecoration(hintText: '请补充具体案由 (选填)', border: OutlineInputBorder())),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('撤销', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: isSubmitting ? null : () async {
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.reportPost(postId, int.parse(_currentUser!.id), reason, detailCtrl.text.trim());
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：报告已记录，待中心审核。')));
                      }
                    } catch (e) {
                       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：档案提交中止。')));
                    } finally {
                      if (mounted) setStateDialog(() => isSubmitting = false);
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('立案提交'),
                ),
              ],
            );
          }
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
              title: const Row(children: [Icon(Icons.warning_amber, color: Colors.redAccent), SizedBox(width: 8), Text('账号行为约束')]),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('信誉扣除分额', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: strikesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16),
                    const Text('中心公开批示 (必须提供)', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: publicCtrl, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    const Text('管理内控案卷 (非公开)', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: privateCtrl, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder())),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('暂缓', style: TextStyle(color: Colors.grey))),
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：账号约束指令已生效。')));
                      }
                    } on DioException catch (e) {
                       String errMsg = '系统提示：管控授权被拒绝。';
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
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('执行批示'),
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
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _posts[index]['attributes']['isLiked'] = currentIsLiked;
          _posts[index]['attributes']['likesCount'] = currentLikesCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：状态同步中止。')));
      }
    }
  }

  Future<void> _deletePost(int postId, int index) async {
    try {
      await widget.api.deletePost(postId);
      if (mounted) {
        setState(() { _posts.removeAt(index); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：数据列已销毁。')));
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：销毁指令未获许可。')));
    }
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

  String _sanitizeHtmlForVideo(String htmlContent) {
    if (htmlContent.isEmpty) return htmlContent;
    String safeHtml = htmlContent.replaceAllMapped(
      RegExp(r'<iframe[^>]+src="([^"]+)"[^>]*>.*?</iframe>', caseSensitive: false),
      (match) {
        String url = match.group(1) ?? '';
        if (url.startsWith('//')) url = 'https:$url';
        return '''
        <div style="background-color: #f8f9fa; padding: 20px; border-radius: 12px; text-align: center; border: 1px solid #e9ecef; margin: 16px 0;">
          <p style="margin: 0 0 12px 0; color: #495057; font-size: 15px; font-weight: bold;">▶️ 视音频资源载体</p>
          <a href="$url" style="display: inline-block; background-color: #00a1d6; color: white; padding: 10px 24px; border-radius: 6px; text-decoration: none; font-weight: bold; font-size: 14px;">启用外部安全播放源</a>
        </div>
        ''';
      }
    );
    return safeHtml;
  }
  
  Widget _buildLockedPayBlock(String payAmount, String buyersCount, String ptrId, int discussionId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5), 
        border: Border.all(color: const Color(0xFFFFA8A8), width: 1.5), 
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text('加密阅读节点', style: TextStyle(color: Color(0xFFE85055), fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('该节点已被资产保护层锁定。 准入资产: $payAmount XSD', style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text('$buyersCount 名授权账户', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                   const SizedBox(height: 8),
                   FilledButton(
                     style: FilledButton.styleFrom(
                       backgroundColor: const Color(0xFF526D85), 
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                       minimumSize: const Size(80, 36),
                     ),
                     onPressed: () async {
                        final isLoggedIn = await widget.api.isLoggedIn;
                        if (!isLoggedIn) {
                          _promptLogin();
                          return;
                        }
                        if (ptrId.isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统错误：加密节点标识遗失，请切换至桌面端环境。')));
                           return;
                        }
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) {
                            bool isSubmitting = false;
                            return StatefulBuilder(
                              builder: (ctx, setStateDialog) {
                                return AlertDialog(
                                  backgroundColor: Colors.white,
                                  surfaceTintColor: Colors.transparent,
                                  title: const Text('授权协议确认', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                  content: Text('此操作将从您的账户中划拨 $payAmount XSD 资产以解除节点封锁，是否批准？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('终止', style: TextStyle(color: Colors.grey)),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF526D85)),
                                      onPressed: isSubmitting ? null : () async {
                                        setStateDialog(() => isSubmitting = true);
                                        try {
                                          await widget.api.buyPost(ptrId, discussionId);
                                          if (mounted) {
                                            Navigator.pop(ctx); 
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：资产审核通过，正在解密区块...')));
                                            setState(() => _isLoading = true);
                                            await _loadCurrentUser();
                                            await _loadDiscussionDetail(); 
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            final eStr = e.toString();
                                            Navigator.pop(ctx); 
                                            String pureMsg = eStr.replaceAll('Exception: ', '');
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pureMsg), duration: const Duration(seconds: 4)));
                                          }
                                        } finally {
                                          if (mounted) setStateDialog(() => isSubmitting = false);
                                        }
                                      },
                                      child: isSubmitting 
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                                        : const Text('批准支付'),
                                    ),
                                  ],
                                );
                              }
                            );
                          }
                        );
                     },
                     child: const Text('授权获取', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                   )
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildUnlockedPayBlock(String safeHtmlContent, String buyersCount) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFF), 
        border: Border.all(color: const Color(0xFF64B5F6), width: 1.5), 
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 40), 
              const Text('✅ 区块已解密', style: TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold, fontSize: 14)),
              Text('共有 $buyersCount 项准入记录', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 16),
          HtmlWidget(
             safeHtmlContent, 
             textStyle: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dAttrs = _discussionData['attributes'] ?? {};
    final bool canRename = dAttrs['canRename'] == true;
    final bool canSticky = dAttrs['canSticky'] == true;
    final bool canLock = dAttrs['canLock'] == true;
    final bool canTag = dAttrs['canTag'] == true;
    final bool canDeleteDiscussion = dAttrs['canDelete'] == true;
    final bool isSticky = dAttrs['isSticky'] == true;
    final bool isLocked = dAttrs['isLocked'] == true;
    final String currentTitle = dAttrs['title'] ?? widget.discussion.title;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(currentTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: const Color(0xFFE5E5EA), height: 0.5),
        ),
        actions: [
          if (canRename || canSticky || canLock || canTag || canDeleteDiscussion)
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings, color: Colors.black87),
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              onSelected: (val) {
                if (val == 'rename') _renameDiscussion();
                else if (val == 'sticky') _toggleSticky(!isSticky);
                else if (val == 'lock') _toggleLock(!isLocked);
                else if (val == 'delete') _deleteDiscussion();
                else if (val == 'tag') _editTags();
              },
              itemBuilder: (ctx) => [
                if (canRename) const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.title, size: 18), SizedBox(width: 8), Text('重命名主题')])),
                if (canSticky) PopupMenuItem(value: 'sticky', child: Row(children: [Icon(isSticky ? Icons.vertical_align_bottom : Icons.vertical_align_top, size: 18), const SizedBox(width: 8), Text(isSticky ? '解除主题置顶' : '执行主题置顶')])),
                if (canLock) PopupMenuItem(value: 'lock', child: Row(children: [Icon(isLocked ? Icons.lock_open : Icons.lock_outline, size: 18), const SizedBox(width: 8), Text(isLocked ? '解除主帖封锁' : '执行主帖封锁')])),
                if (canTag) const PopupMenuItem(value: 'tag', child: Row(children: [Icon(Icons.local_offer_outlined, size: 18), SizedBox(width: 8), Text('节点标签分配')])),
                if (canDeleteDiscussion) const PopupMenuDivider(),
                if (canDeleteDiscussion) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('销毁数据源', style: TextStyle(color: Colors.red))])),
              ]
            )
        ],
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
                  Text('撰写补充文档...', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
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
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              const Text('加载程序意外终止。', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () {
                  setState(() { _isLoading = true; _error = null; });
                  _loadDiscussionDetail();
                }, 
                child: const Text('重启读取进程')
              ),
            ],
          ),
        )
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _posts.length,
      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
      itemBuilder: (context, index) {
        final post = _posts[index];
        final discussionId = int.parse(widget.discussion.id); 
        final attrs = post['attributes'] ?? {};
        
        final userIdStr = post['relationships']?['user']?['data']?['id']?.toString();
        final FlarumUser? user = userIdStr != null ? _usersMap[userIdStr] : null;
        
        final username = user?.displayName.isNotEmpty == true ? user!.displayName : (user?.username ?? '已注销账户');
        final avatarUrl = user?.avatarUrl;
        final timeStr = attrs['createdAt'] as String?;
        final time = timeStr != null ? DateTime.tryParse(timeStr) : null;
        
        final htmlContent = attrs['contentHtml'] as String? ?? '';
        final rawContent = attrs['content'] as String? ?? '';
        final isLiked = attrs['isLiked'] ?? false;
        final likesCount = attrs['likesCount'] ?? 0;

        final bool canEdit = attrs['canEdit'] == true;
        final bool canDelete = attrs['canDelete'] == true;
        final bool canFlag = attrs['canFlag'] == true;
        final bool canSeeVotes = attrs['canSeeVotes'] == true;
        final bool canWarn = _isModerator && userIdStr != _currentUser?.id;

        String payAmount = '1';
        if (attrs['payAmount'] != null) payAmount = attrs['payAmount'].toString();
        else if (attrs['price'] != null) payAmount = attrs['price'].toString();
        else {
           final match = RegExp(r'amount=([0-9\.]+)').firstMatch(rawContent);
           if (match != null) payAmount = match.group(1) ?? '1';
        }

        String buyersCount = '0';
        final cntMatch = RegExp(r'data-haspaid-cnt="([0-9]+)"').firstMatch(htmlContent);
        if (cntMatch != null && cntMatch.group(1) != null) {
            buyersCount = cntMatch.group(1)!;
        } else if (attrs['paidUsersCount'] != null) {
            buyersCount = attrs['paidUsersCount'].toString();
        } else if (attrs['buyersCount'] != null) {
            buyersCount = attrs['buyersCount'].toString();
        }
        
        String ptrId = '';
        final idMatch = RegExp(r'id=([0-9]+)').firstMatch(rawContent);
        if (idMatch != null && idMatch.group(1) != null) ptrId = idMatch.group(1)!;
        if (ptrId.isEmpty) {
            final dataIdMatch = RegExp(r'data-id="([0-9]+)"').firstMatch(htmlContent);
            if (dataIdMatch != null && dataIdMatch.group(1) != null) ptrId = dataIdMatch.group(1)!;
        }
        
        bool isPayProtected = false;
        bool hasSuccessfullyUnlocked = false; 
        
        if (htmlContent.contains('ptr-block') || htmlContent.contains('pay-to-read') || rawContent.contains('[pay')) {
            isPayProtected = true; 
            if (htmlContent.contains('ptr-paid') || htmlContent.contains('ptr-unlocked')) {
                isPayProtected = false; 
                hasSuccessfullyUnlocked = true;
            }
        }

        if (_currentUser != null && _currentUser!.id == userIdStr) {
             if (isPayProtected) {
                 isPayProtected = false;
                 hasSuccessfullyUnlocked = true;
             }
        }

        final safeHtml = _sanitizeHtmlForVideo(htmlContent);

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
              
              if (isPayProtected) 
                 _buildLockedPayBlock(payAmount, buyersCount, ptrId, discussionId) 
              else if (hasSuccessfullyUnlocked)
                 _buildUnlockedPayBlock(safeHtml, buyersCount)
              else 
                 HtmlWidget(
                    safeHtml, 
                    textStyle: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
                 ),
                 
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
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('追加文档', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500))),
                  ),
                  const SizedBox(width: 8),
                  
                  // 🚨 剔除旧版的“资产打赏”
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
                      final postIdInt = int.parse(_posts[index]['id']);
                      if (value == 'edit') _openEditorForEdit(index);
                      else if (value == 'delete') _deletePost(postIdInt, index);
                      else if (value == 'warn') _showWarnDialog(postIdInt, userIdStr);
                      else if (value == 'report') _showReportDialog(postIdInt);
                      else if (value == 'vote') _showVoteDetails(index);
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      
                      if (canSeeVotes) const PopupMenuItem<String>(value: 'vote', child: Row(children: [Icon(Icons.how_to_vote_outlined, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('交互日志记录')])),
                      
                      if (canFlag && userIdStr != _currentUser?.id) const PopupMenuItem<String>(value: 'report', child: Row(children: [Icon(Icons.report_problem_outlined, size: 18, color: Colors.orange), SizedBox(width: 8), Text('上报违规')])),
                      
                      if (canEdit) const PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('修订文档')])),
                      
                      if (canWarn) const PopupMenuItem<String>(value: 'warn', child: Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('下达账号约束')])),
                      
                      if (canDelete) const PopupMenuDivider(),
                      if (canDelete) const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('抹除数据列', style: TextStyle(color: Colors.red))])),
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
