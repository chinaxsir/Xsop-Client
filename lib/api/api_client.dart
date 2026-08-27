// 文件位置: lib/api/api_client.dart

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _tokenKey = 'flarum_token';
  static const String _userIdKey = 'flarum_user_id';

  final Dio _dio;
  final String baseUrl;
  
  String currencyName = 'XSD'; 

  ApiClient({this.baseUrl = 'https://xsop.de'}) : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Token $token';
        }
        handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await logout();
        }
        handler.next(e);
      }
    ));
  }

  Future<Map<String, dynamic>> getForumInfo() async {
    final response = await _dio.get('/api');
    final data = _asMap(response.data);
    
    final attrs = data['data']?['attributes'];
    if (attrs != null) {
       String rawName = attrs['shebaoting-money.moneyname']?.toString() 
                     ?? attrs['antoinefr-money.moneyname']?.toString() 
                     ?? 'XSD';
       rawName = rawName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
       if (rawName.isNotEmpty) {
          currencyName = rawName;
       }
    }
    return data;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  Future<Map<String, dynamic>> login(String identification, String password) async {
    final response = await _dio.post('/api/token', data: {
      'identification': identification,
      'password': password,
      'lifetime': 31536000, 
      'remember': true, 
    });
    final data = _asMap(response.data);
    final token = data['token'] as String?;
    final userId = data['userId'] as int?;
    if (token != null && token.isNotEmpty) {
      await _saveAuth(token, userId);
    }
    return data;
  }

  Future<Map<String, dynamic>> getDiscussions({int page = 1, int pageSize = 20, String? tag, String? author, String? sort}) async {
    final query = <String, dynamic>{'page[number]': page, 'page[size]': pageSize};
    if (tag != null && tag.isNotEmpty) query['filter[tag]'] = tag.trim();
    List<String> searchQueries = [];
    if (author != null && author.isNotEmpty) searchQueries.add('author:${author.trim()}');
    if (searchQueries.isNotEmpty) query['filter[q]'] = searchQueries.join(' ');
    if (sort != null) query['sort'] = sort;

    final response = await _dio.get('/api/discussions', queryParameters: query);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getDiscussion(int id, {int page = 1, int pageSize = 20}) async {
    final response = await _dio.get('/api/discussions/$id', queryParameters: {
      'page[number]': page, 
      'page[size]': pageSize, 
      'include': 'user,posts,posts.user'
    });
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getTags() async {
    final response = await _dio.get('/api/tags', queryParameters: {'include': 'parent'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getUser(int id) async {
    final response = await _dio.get('/api/users/$id', queryParameters: {'include': 'groups'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createDiscussion({required String title, required String content, List<String>? tagIds}) async {
    final Map<String, dynamic> relationships = {};
    if (tagIds != null && tagIds.isNotEmpty) {
      relationships["tags"] = {"data": tagIds.map((id) => {"type": "tags", "id": id}).toList()};
    }
    final Map<String, dynamic> payloadData = {"type": "discussions", "attributes": {"title": title, "content": content}};
    if (relationships.isNotEmpty) payloadData["relationships"] = relationships;
    final response = await _dio.post('/api/discussions', data: {"data": payloadData});
    return _asMap(response.data);
  }

  Future<void> updateDiscussion(int id, {String? title, bool? isSticky, bool? isLocked, List<String>? tagIds}) async {
    final Map<String, dynamic> attributes = {};
    if (title != null && title.isNotEmpty) attributes['title'] = title;
    if (isSticky != null) attributes['isSticky'] = isSticky;
    if (isLocked != null) attributes['isLocked'] = isLocked;

    final Map<String, dynamic> relationships = {};
    if (tagIds != null) {
      relationships['tags'] = {"data": tagIds.map((tid) => {"type": "tags", "id": tid.toString()}).toList()};
    }

    final Map<String, dynamic> dataBlock = {
      "type": "discussions",
      "id": id.toString(),
      "attributes": attributes,
    };

    if (relationships.isNotEmpty) {
      dataBlock["relationships"] = relationships;
    }

    await _dio.patch('/api/discussions/$id', data: {"data": dataBlock});
  }

  Future<void> deleteDiscussion(int id) async {
    await _dio.delete('/api/discussions/$id');
  }

  Future<Map<String, dynamic>> createPost(int discussionId, String content) async {
    final data = {"data": {"type": "posts", "attributes": {"content": content}, "relationships": {"discussion": {"data": {"type": "discussions", "id": discussionId.toString()}}}}};
    final response = await _dio.post('/api/posts', data: data);
    return _asMap(response.data);
  }

  Future<void> deletePost(int postId) async {
    await _dio.delete('/api/posts/$postId');
  }

  Future<void> editPost(int postId, String content) async {
    await _dio.patch('/api/posts/$postId', data: {
      "data": {"type": "posts", "id": postId.toString(), "attributes": {"content": content}}
    });
  }

  Future<void> warnUser(int targetUserId, {int? postId, int strikes = 0, String? publicComment, String? privateComment}) async {
    final Map<String, dynamic> dataBlock = {
        "type": "warnings", 
        "attributes": {
          "userId": targetUserId.toString(),
          "strikes": strikes.toString(),
          "public_comment": publicComment ?? "",
          "private_comment": privateComment ?? ""
        }, 
        "relationships": <String, dynamic>{}
    };
    if (postId != null) {
       (dataBlock["relationships"] as Map<String, dynamic>)["post"] = {"data": {"type": "posts", "id": postId.toString()}};
    }
    await _dio.post('/api/warnings', data: {"data": dataBlock});
  }

  Future<void> reportPost(int postId, int currentUserId, String reason, String? detail) async {
    await _dio.post('/api/flags', data: {
      "data": {
        "type": "flags", 
        "attributes": {"reason": reason, "reasonDetail": detail ?? ""}, 
        "relationships": {
           "user": {"data": {"type": "users", "id": currentUserId.toString()}},
           "post": {"data": {"type": "posts", "id": postId.toString()}}
        }
      }
    });
  }

  Future<void> buyPost(String ptrId, int discussionId) async {
    try {
       await _dio.get('/api/pay-to-read/payment/', queryParameters: {'id': discussionId});
    } catch (_) {}

    try {
      final response = await _dio.post('/api/pay-to-read/payment/pay', data: {"id": ptrId});
      if (response.statusCode == 201) return; 
      throw Exception('操作失败');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final errStr = e.response?.data?.toString() ?? '';
      if (errStr.contains('不足') || errStr.contains('没钱') || errStr.contains('insufficient') || code == 403) {
         throw Exception('余额不足'); 
      }
      throw Exception('操作失败');
    }
  }

  // 🚨 修复：严格对齐用户提供的 Payload 截图
  Future<void> tipPost(int postId, double amount, String comment) async {
    // 载荷 1：直接包裹 attributes（对齐图1）
    final payload1 = {
      "data": {
        "attributes": {
          "amount": amount.toString(),
          "createMoney": false,
          "comment": comment
        }
      }
    };
    
    // 载荷 2：包含 relationships（以防后端严苛校验）
    final payload2 = {
      "data": {
        "type": "money-rewards",
        "attributes": {
          "amount": amount.toString(),
          "createMoney": false,
          "comment": comment
        },
        "relationships": {
           "post": {"data": {"type": "posts", "id": postId.toString()}}
        }
      }
    };

    DioException? bestErr;
    final endpoints = ['/api/posts/$postId/money-rewards', '/api/money-rewards'];

    for (var ep in endpoints) {
      for (var p in [payload1, payload2]) {
         try {
           final response = await _dio.post(ep, data: p);
           if (response.statusCode == 200 || response.statusCode == 201) return;
         } on DioException catch (e) {
           bestErr = e;
         }
      }
    }
    
    throw Exception(_extractApiError(bestErr) ?? '打赏失败');
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _dio.post('/api/forgot', data: {"email": email});
    } on DioException catch (e) {
      throw Exception(_extractApiError(e) ?? '发送失败');
    }
  }

  Future<void> changeEmail(int userId, String newEmail, String password) async {
    try {
      await _dio.patch('/api/users/$userId', data: {
        "data": {
          "type": "users",
          "id": userId.toString(),
          "attributes": {"email": newEmail}
        },
        "meta": {"password": password}
      });
    } on DioException catch (e) {
      throw Exception(_extractApiError(e) ?? '修改失败');
    }
  }

  Future<void> likePost(int postId, bool isLiked) async {
    await _dio.patch('/api/posts/$postId', data: {"data": {"type": "posts", "id": postId.toString(), "attributes": {"isLiked": isLiked}}});
  }

  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _dio.get('/api/notifications', queryParameters: {'include': 'fromUser,subject'});
    return _asMap(response.data);
  }

  Future<Map<String, String>?> uploadFile(String filePath, {String? filename}) async {
    String name = filename ?? filePath.split('/').last;
    final formData = FormData.fromMap({
      'files[]': await MultipartFile.fromFile(filePath, filename: name),
    });
    
    final response = await _dio.post('/api/fof/upload', data: formData);
    final data = _asMap(response.data);
    final files = data['data'] as List<dynamic>?;
    if (files != null && files.isNotEmpty) {
       final attrs = files.first['attributes'] as Map<String, dynamic>?;
       if (attrs != null) return {'url': attrs['url']?.toString() ?? '', 'baseName': attrs['baseName']?.toString() ?? name};
    }
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
  }

  Future<bool> get isLoggedIn async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, dynamic>> getDynamicList(String endpoint, {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get(endpoint, queryParameters: queryParameters);
    return _asMap(response.data);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  // 🚨 升级报错解析器：提取真正的底层错误（如"邮箱已被采用"）
  String? _extractApiError(DioException? e) {
    if (e == null) return null;
    try {
      final data = e.response?.data;
      if (data is Map) {
        if (data['errors'] is List && data['errors'].isNotEmpty) {
          return data['errors'][0]['detail']?.toString() ?? data['errors'][0]['code']?.toString();
        }
        if (data['message'] != null) {
          return data['message'].toString();
        }
      }
    } catch (_) {}
    return null;
  }
  
  Future<void> _saveAuth(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (userId != null) await prefs.setInt(_userIdKey, userId);
  }
}
