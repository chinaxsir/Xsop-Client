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
        _usersMap = users;
        _posts = postsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '网络传输发生故障，获取主题系统详情阻断';
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditorForEdit(int index) async {
    final post = _posts[index];
    final postId = post['id'];
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('提取Markdown源码环境数据中...')));
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
              title: const Row(children: [Icon(Icons.card_giftcard, color: Colors.orange), SizedBox(width: 8), Text('资源打赏系统')]),
              content: TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '输入交互流转数值 (XSD)', border: OutlineInputBorder(), suffixText: 'XSD'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: isSubmitting ? null : () async {
                    final amount = int.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('交互数值非法阻断')));
                       return;
                    }
                    setStateDialog(() => isSubmitting = true);
                    try {
                      await widget.api.tipPost(postId, amount);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资产流水结算成功！')));
                      }
                    } on DioException catch (e) {
                      if (mounted) {
                         String errMsg = '打赏阻断：服务端底层鉴权拒绝，或余额核验失败';
                         try {
                           final rawData = e.response?.data;
                           if (rawData != null && rawData is Map) {
                             if (rawData['errors'] != null && rawData['errors'] is List && rawData['errors'].isNotEmpty) {
                               errMsg = rawData['errors'][0]['detail'] ?? errMsg;
                             } else if (rawData['message'] != null) {
                               errMsg = rawData['message'];
                             }
                           }
                         } catch (_) {}
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg), duration: const Duration(seconds: 4)));
                         Navigator.pop(context); 
                      }
                    } catch (e) {
                      if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('内部引擎防崩溃：${e.toString()}'), duration: const Duration(seconds: 4)));
                         Navigator.pop(context); 
                      }
                    } finally {
                      if (mounted) setStateDialog(() => isSubmitting = false);
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('执行结算'),
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
           title: const Text('数据流统计参数'),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               ListTile(
                 leading: const Icon(Icons.thumb_up, color: Colors.green),
                 title: const Text('互动 / 核验通过基数'),
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
              title: const Row(children: [Icon(Icons.warning_amber, color: Colors.redAccent), SizedBox(width: 8), Text('下发站务警告数据')]),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('核验等级：计入参数', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: strikesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 16),
                    const Text('前端下发通报内容', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(controller: publicCtrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('系统撤销', style: TextStyle(color: Colors.grey))),
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统警告下发部署完毕！')));
                      }
                    } on DioException catch (e) {
                       String errMsg = '越权环境阻断，警告下发失败';
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
                  child: isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('确认下发'),
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
        
        String errMsg = '操作越权系统拦截';
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统底层数据已清除')));
      }
    } on DioException catch (e) {
      String errMsg = '服务器驳回了删除请求系统拦截';
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
  
  // [图2 核心修复：1:1 像素级复刻网页版的红色虚线购买组件！]
  Widget _buildPayBlock(Map<String, dynamic> attrs) {
    // 获取价格和购买人数，处理多语言或不同插件的兼容性
    final payAmount = attrs['payAmount']?.toString() ?? '1';
    final buyersCount = attrs['paidUsersCount']?.toString() ?? attrs['buyersCount']?.toString() ?? '0';
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8F8), // 接近网页端的极浅红底色
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
             child: CustomPaint(painter: _DashedBorderPainter(color: const Color(0xFFE88A8E))), // 官方同款红虚线
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
                             backgroundColor: const Color(0xFF526D85), // 官方同款深蓝灰按钮
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                             minimumSize: const Size(80, 36),
                           ),
                           onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系统提示：该板块支付接口仅限 Web 端核验，请前往网页版进行权限结算购买。')));
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
                  Text('前端交互回复系统...', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
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
        final rawContent = attrs['content'] as String? ?? '';
        final isLiked = attrs['isLiked'] ?? false;
        final likesCount = attrs['likesCount'] ?? 0;

        final bool canEdit = attrs['canEdit'] == true;
        final bool canDelete = attrs['canDelete'] == true;
        
        // [极度智能探测：哪怕 Flarum 没有下发 payAmount，只要 rawContent 包含收费标志，就认为是收费帖！防止图1白板]
        final isPayProtected = htmlContent.isEmpty && (
           rawContent.contains('[pay') || 
           rawContent.contains('付费可见') ||
           attrs['isPay'] == true || 
           attrs['payAmount'] != null
        );

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
                 _buildPayBlock(attrs)
              else 
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
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('系统交互', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500))),
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
                      const PopupMenuItem<String>(value: 'tip', child: Row(children: [Icon(Icons.card_giftcard, size: 18, color: Colors.orange), SizedBox(width: 8), Text('资产打赏')])),
                      const PopupMenuItem<String>(value: 'vote', child: Row(children: [Icon(Icons.how_to_vote_outlined, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('核验详情')])),
                      
                      if (canEdit) const PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('系统编辑')])),
                      if (_canWarnUser) const PopupMenuItem<String>(value: 'warn', child: Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('通报警告')])),
                      if (canDelete) const PopupMenuDivider(),
                      if (canDelete) const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('安全抹除', style: TextStyle(color: Colors.red))])),
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
