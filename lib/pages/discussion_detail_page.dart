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

  bool get _canWarnUser {
    if (_currentUser == null) return false;
    return _currentUser!.groups.any((g) => g.id == '1' || g.id == '3' || g.id == '4');
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
            String msg = '加载失败 (HTTP ${e.response?.statusCode})';
            try {
              if (e.response?.data != null) {
                 msg += '\n\n详细信息:\n${e.response?.data}';
              }
            } catch (_) {}
            _error = msg;
          } else {
            _error = '未知错误：${e.toString()}';
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openEditorForEdit(int index) async {
    final post = _posts[index];
    final postId = post['id'];
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在获取内容...')));
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
              title: const Row(children: [Icon(Icons.card_giftcard, color: Colors.orange), SizedBox(width: 8), Text('打赏')]),
              content: TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '请输入金额', border: OutlineInputBorder()),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: isSubmitting ? null : () async {
                    final amount = int.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效金额。')));
                       return;
                    }
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.tipPost(postId, amount);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作成功。')));
                      }
                    } catch (e) {
                      if (mounted) {
                         String errMsg = '操作失败';
                         if (e is DioException) {
                            try {
                               final rawData = e.response?.data;
                               if (rawData != null && rawData is Map && rawData['errors'] != null && rawData['errors'].isNotEmpty) {
                                 errMsg = rawData['errors'][0]['detail'] ?? '失败原因: ${rawData['errors'][0]['code']}';
                               }
                            } catch (_) {}
                         } else {
                            errMsg = e.toString().replaceAll('Exception: ', '');
                         }
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg), duration: const Duration(seconds: 4)));
                         Navigator.pop(context); 
                      }
                    } finally {
                      if (mounted) setStateDialog(() => isSubmitting = false);
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('确定'),
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
           title: const Text('点赞详情'),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               ListTile(
                 leading: const Icon(Icons.thumb_up, color: Colors.green),
                 title: const Text('获赞数'),
                 trailing: Text('$upvotes', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
               ),
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
              title: const Row(children: [Icon(Icons.warning_amber, color: Colors.redAccent), SizedBox(width: 8), Text('警告用户')]),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('警告分数', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: strikesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16),
                    const Text('公开评论', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: publicCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作成功。')));
                      }
                    } on DioException catch (e) {
                       String errMsg = '操作失败';
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
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('确定'),
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
        
        String errMsg = '操作失败';
        try {
          final errs = e.response?.data['errors'];
          if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
            errMsg = errs[0]['detail'];
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
      }
    }
  }

  Future<void> _deletePost(int postId, int index) async {
    try {
      await widget.api.deletePost(postId);
      if (mounted) {
        setState(() { _posts.removeAt(index); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作成功。')));
      }
    } on DioException catch (e) {
      String errMsg = '操作失败';
      try {
        final errs = e.response?.data['errors'];
        if (errs != null && errs is List && errs.isNotEmpty && errs[0]['detail'] != null) {
          errMsg = errs[0]['detail'];
        }
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
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
        if (url.startsWith('//')) {
           url = 'https:$url';
        }
        
        return '''
        <div style="background-color: #f8f9fa; padding: 20px; border-radius: 12px; text-align: center; border: 1px solid #e9ecef; margin: 16px 0;">
          <p style="margin: 0 0 12px 0; color: #495057; font-size: 15px; font-weight: bold;">▶️ 本帖包含外部视频</p>
          <a href="$url" style="display: inline-block; background-color: #00a1d6; color: white; padding: 10px 24px; border-radius: 6px; text-decoration: none; font-weight: bold; font-size: 14px;">在浏览器中安全播放</a>
        </div>
        ''';
      }
    );
    return safeHtml;
  }
  
  Widget _buildPayBlock(String payAmount, String buyersCount, List<String> possibleIds, int discussionId, int postId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8F8),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
             child: CustomPaint(painter: _DashedBorderPainter(color: const Color(0xFFE88A8E))), 
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text('本帖的付费阅读内容', style: TextStyle(color: const Color(0xFFE85055), fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('作者将该内容设置为付费可见。 价格 $payAmount XSD', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                         Text('$buyersCount人付费', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
                                        title: const Text('确认购买', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                        content: Text('是否确认花费 $payAmount XSD 购买此内容？'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('取消', style: TextStyle(color: Colors.grey)),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF526D85)),
                                            onPressed: isSubmitting ? null : () async {
                                              setStateDialog(() => isSubmitting = true);
                                              try {
                                                await widget.api.buyPost(possibleIds, discussionId, postId);
                                                if (mounted) {
                                                  Navigator.pop(ctx); 
                                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('购买成功！请稍候...')));
                                                  
                                                  // 强制拉取全局余额和最新帖子状态，彻底击碎假象
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
                                              : const Text('购买'),
                                          ),
                                        ],
                                      );
                                    }
                                  );
                                }
                              );
                           },
                           child: const Text('购买', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                         )
                      ],
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
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
              const Text('出错了，请重试。', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () {
                  setState(() { _isLoading = true; _error = null; });
                  _loadDiscussionDetail();
                }, 
                child: const Text('重试')
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
        final postId = int.parse(post['id']);
        final discussionId = int.parse(widget.discussion.id); 
        final attrs = post['attributes'] ?? {};
        
        final userIdStr = post['relationships']?['user']?['data']?['id']?.toString();
        final FlarumUser? user = userIdStr != null ? _usersMap[userIdStr] : null;
        
        final username = user?.displayName.isNotEmpty == true ? user!.displayName : (user?.username ?? '已注销');
        final avatarUrl = user?.avatarUrl;
        final timeStr = attrs['createdAt'] as String?;
        final time = timeStr != null ? DateTime.tryParse(timeStr) : null;
        
        final htmlContent = attrs['contentHtml'] as String? ?? '';
        final rawContent = attrs['content'] as String? ?? '';
        final isLiked = attrs['isLiked'] ?? false;
        final likesCount = attrs['likesCount'] ?? 0;

        final bool canEdit = attrs['canEdit'] == true;
        final bool canDelete = attrs['canDelete'] == true;
        
        Set<String> possibleIds = {postId.toString(), discussionId.toString()};
        
        for (var rels in [post['relationships'] ?? {}, _discussionData['relationships'] ?? {}]) {
           rels.forEach((key, value) {
              if (key.toLowerCase().contains('pay')) {
                 if (value is Map && value['data'] is Map && value['data']['id'] != null) {
                    possibleIds.add(value['data']['id'].toString());
                 }
              }
           });
        }
        
        for (var inc in _included) {
           final t = inc['type']?.toString().toLowerCase() ?? '';
           if (t.contains('pay')) {
              possibleIds.add(inc['id'].toString());
           }
        }
        
        for (var at in [attrs, _discussionData['attributes'] ?? {}]) {
           at.forEach((key, value) {
              if (key.toLowerCase().contains('id') || key.toLowerCase().contains('pay')) {
                 if (value is int) possibleIds.add(value.toString());
                 if (value is String && int.tryParse(value) != null) possibleIds.add(value);
              }
           });
        }

        // 提取价格，为 UI 显示提供保障
        String payAmount = '1';
        if (attrs['payAmount'] != null) payAmount = attrs['payAmount'].toString();
        else if (attrs['price'] != null) payAmount = attrs['price'].toString();
        else {
           final match = RegExp(r'amount=([0-9\.]+)').firstMatch(rawContent);
           if (match != null) payAmount = match.group(1) ?? '1';
        }

        String buyersCount = '0';
        if (attrs['paidUsersCount'] != null) buyersCount = attrs['paidUsersCount'].toString();
        else if (attrs['buyersCount'] != null) buyersCount = attrs['buyersCount'].toString();
        
        
        // 🚨【终极解码引擎】：完全基于 Ziiven 注入的 HTML 样式标签判定，不再死等 hasPaid 变量！
        bool isPayProtected = false;
        
        // 如果文本里包含锁定的特征词
        if (rawContent.contains('[pay') || rawContent.contains('[charge')) {
            isPayProtected = true; // 默认它被锁了
            
            // 但是！如果 HTML 源码里被插件注入了 "ptr-paid" (已购买标签)，直接原地赦免，强制解锁！
            if (htmlContent.contains('ptr-paid')) {
                isPayProtected = false; 
            }
        }

        // 作者永远拥有免死金牌
        if (_currentUser != null && _currentUser!.id == userIdStr) {
             isPayProtected = false;
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
                 _buildPayBlock(payAmount, buyersCount, possibleIds.toList(), discussionId, postId) 
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
                      if (value == 'edit') _openEditorForEdit(index);
                      else if (value == 'delete') _deletePost(postId, index);
                      else if (value == 'tip') _showTipDialog(postId);
                      else if (value == 'warn') _showWarnDialog(postId, userIdStr);
                      else if (value == 'vote') _showVoteDetails(index);
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(value: 'tip', child: Row(children: [Icon(Icons.card_giftcard, size: 18, color: Colors.orange), SizedBox(width: 8), Text('打赏')])),
                      const PopupMenuItem<String>(value: 'vote', child: Row(children: [Icon(Icons.how_to_vote_outlined, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('点赞详情')])),
                      
                      if (canEdit) const PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('编辑')])),
                      if (_canWarnUser) const PopupMenuItem<String>(value: 'warn', child: Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('警告')])),
                      if (canDelete) const PopupMenuDivider(),
                      if (canDelete) const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
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

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    var path = Path();
    double dashWidth = 5.0, dashSpace = 4.0;
    
    double startX = 0;
    while (startX < size.width) {
      path.moveTo(startX, 0);
      path.lineTo(startX + dashWidth, 0);
      startX += dashWidth + dashSpace;
    }
    startX = 0;
    while (startX < size.width) {
      path.moveTo(startX, size.height);
      path.lineTo(startX + dashWidth, size.height);
      startX += dashWidth + dashSpace;
    }
    double startY = 0;
    while (startY < size.height) {
      path.moveTo(0, startY);
      path.lineTo(0, startY + dashWidth);
      startY += dashWidth + dashSpace;
    }
    startY = 0;
    while (startY < size.height) {
      path.moveTo(size.width, startY);
      path.lineTo(size.width, startY + dashWidth);
      startY += dashWidth + dashSpace;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
