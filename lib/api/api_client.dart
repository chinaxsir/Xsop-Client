// 文件位置: lib/api/api_client.dart

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _tokenKey = 'flarum_token';
  static const String _userIdKey = 'flarum_user_id';

  final Dio _dio;
  final String baseUrl;

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
    return _asMap(response.data);
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

  Future<void> warnUser(int userId, {int? postId, int strikes = 0, String? publicComment, String? privateComment}) async {
    final Map<String, dynamic> data = {
      "data": {"type": "warnings", "attributes": {"strikes": strikes, "publicComment": publicComment ?? "", "privateComment": privateComment ?? ""}, "relationships": {"user": {"data": {"type": "users", "id": userId.toString()}}}}
    };
    if (postId != null) data["data"]["relationships"]["post"] = {"data": {"type": "posts", "id": postId.toString()}};
    await _dio.post('/api/warnings', data: data);
  }

  String _extractErrorCode(dynamic data) {
    try {
      if (data is Map && data['errors'] is List && data['errors'].isNotEmpty) {
        return data['errors'][0]['code']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  // [闪电探针：移除所有阻塞型验证，执行轻量级一击必杀]
  Future<void> buyPost(List<String> possibleIds, int discussionId, int postId) async {
    String? fallbackErrorMsg;

    // 1. 激活后端订单会话 (非常轻量级的 GET 请求)
    try {
       await _dio.get('/api/pay-to-read/payment/?id=$discussionId');
    } catch (_) {}

    // 2. 直取命门 (极速 POST 请求)
    final ziivenUrl = '/api/pay-to-read/payment/pay';
    final ziivenPayloads = [
      {"discussion_id": discussionId}, 
      {"id": discussionId},
      {"post_id": postId},
    ];

    for (var p in ziivenPayloads) {
       try {
         final response = await _dio.post(ziivenUrl, data: p);
         
         // 极速拆包验毒（只校验内存数据，不再发网络请求查帖子）
         if (response.data is Map) {
             final resData = response.data as Map;
             final status = resData['status'];
             final msg = resData['msg'] ?? resData['message'] ?? resData['error'];
             
             if (status == 400 || status == 500 || status == 'error' || status == false) {
                 fallbackErrorMsg = msg?.toString() ?? '余额不足或服务器拒绝。';
                 continue; 
             }
         }
         
         final resStr = response.data?.toString() ?? '';
         if (resStr.contains('余额不足') || resStr.contains('积分不足') || resStr.contains('没有权限')) {
             fallbackErrorMsg = '余额不足或操作受限。';
             continue;
         }

         // 验证通过，瞬间放行！不再死循环等结果！
         return; 

       } on DioException catch (e) {
         final code = e.response?.statusCode;
         if (code == 404 || code == 405) {
            break; // 路由不匹配，立刻跳出尝试通用路线，绝不卡死转圈
         } 
         
         if (e.response?.data is Map) {
             fallbackErrorMsg = e.response?.data['msg'] ?? e.response?.data['message'] ?? e.response?.data['error'];
         }
       }
    }

    // 3. 极速保底通道
    final templates = [
      '/api/paytoread/{id}',
      '/api/pay-to-read/{id}',
    ];

    for (var tmpl in templates) {
      for (var id in possibleIds) {
         final ep = tmpl.replaceAll('{id}', id);
         try {
           final response = await _dio.post(ep, data: {"data": {}});
           
           if (response.data is Map) {
              if (response.data['status'] == 'error' || response.data['success'] == false) {
                 continue;
              }
           }
           final str = response.data?.toString() ?? '';
           if (str.contains('余额不足') || str.contains('操作受限')) continue;

           return; 

         } on DioException catch (e) {
           final code = e.response?.statusCode;
           if (code == 404 || code == 405) continue;
           if (e.response?.data is Map) {
               fallbackErrorMsg = e.response?.data['msg'] ?? e.response?.data['message'];
           }
         }
      }
    }

    throw Exception(fallbackErrorMsg ?? '参数未能匹配，购买操作被服务器拦截。');
  }

  Future<void> tipPost(int postId, int amount) async {
    DioException? bestErr;
    final endpoints = [
      '/api/posts/$postId/tip', 
      '/api/posts/$postId/reward', 
      '/api/tips',
      '/api/rewards',
    ];
    
    final payloads = [
      {"data": {"type": "tips", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
      {"data": {"attributes": {"amount": amount}}},
      {"amount": amount},
    ];

    for (final ep in endpoints) {
      bool routeExists = false;
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          final errCode = _extractErrorCode(e.response?.data);
          
          if (code == 404 && errCode == 'route_not_found') {
             routeExists = false;
             break; 
          }
          if (code == 405) {
             routeExists = false;
             break;
          }

          routeExists = true;
          bestErr = e;

          if (code == 422 || errCode == 'validation_error') continue;

          if (errCode != 'not_found' && code != 404) {
             throw e;
          }
        }
      }
      if (routeExists && bestErr != null) throw bestErr;
    }
    
    throw Exception('未匹配到有效的打赏接口。');
  }

  Future<void> reportPost(int postId, String reason, String? detail) async {
    await _dio.post('/api/flags', data: {
      "data": {"type": "flags", "attributes": {"reason": reason, "reasonDetail": detail ?? ""}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}
    });
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
  
  Future<void> _saveAuth(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (userId != null) await prefs.setInt(_userIdKey, userId);
  }
}
