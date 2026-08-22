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

  // [修复防误伤引擎：只认真实错误，放行合法交易]
  Future<void> buyPost(List<String> possibleIds, int discussionId, int postId) async {
    DioException? bestErr;

    try {
       await _dio.get('/api/pay-to-read/payment/', queryParameters: {'id': discussionId});
    } catch (_) {}

    final ziivenUrl = '/api/pay-to-read/payment/pay';
    final ziivenPayloads = [
      {"id": discussionId.toString()}, 
      {"id": postId.toString()},
      {"discussionId": discussionId.toString()},
      {"data": {"attributes": {"id": discussionId.toString()}}},
    ];

    for (var p in ziivenPayloads) {
       try {
         final response = await _dio.post(ziivenUrl, data: p);
         
         final resData = response.data;
         if (resData != null) {
            final resStr = resData.toString().toLowerCase();
            // [极其关键的改动]：取消包含 'error' 或 'false' 的判定，防止把 {"success": true, "error": null} 误杀！
            // 仅对明确代表业务失败的中文提示进行精准阻击！
            if (resStr.contains('余额不足') || 
                resStr.contains('积分不足') || 
                resStr.contains('未登录') || 
                resStr.contains('没有权限')) {
                throw DioException(
                   requestOptions: response.requestOptions,
                   response: response,
                   error: 'FALSE_POSITIVE_INTERCEPTED'
                );
            }
         }
         return; // 购买成功，放行！

       } on DioException catch (e) {
         final code = e.response?.statusCode;
         if (code == 404 || code == 405) continue; 

         bestErr = e;
         final resStr = e.response?.data?.toString() ?? '';
         
         if (RegExp(r'不足|enough|余额|fund|权限|不能|支付|buy|XSD|积分|金币|购买|XSD', caseSensitive: false).hasMatch(resStr) || 
             code == 403 || 
             e.error == 'FALSE_POSITIVE_INTERCEPTED') {
            
            if (e.error == 'FALSE_POSITIVE_INTERCEPTED') {
               throw Exception('余额不足或操作受限。');
            }
            throw e;
         }
       }
    }

    final templates = [
      '/api/paytoread/{id}',
      '/api/pay-to-read/{id}',
      '/api/ziiven/paytoread/{id}',
      '/api/paytosee/{id}',
      '/api/pay-to-see/{id}',
      '/api/discussions/{id}/pay',
      '/api/posts/{id}/pay',
    ];

    for (var tmpl in templates) {
      bool routeExists = false;
      for (var id in possibleIds) {
         final ep = tmpl.replaceAll('{id}', id);
         try {
           final response = await _dio.post(ep, data: {"data": {}});
           
           final resStr = response.data?.toString().toLowerCase() ?? '';
           if (resStr.contains('余额不足') || resStr.contains('积分不足')) {
                throw DioException(requestOptions: response.requestOptions, response: response, error: 'FALSE_POSITIVE_INTERCEPTED');
           }
           return; 

         } on DioException catch (e) {
           final errCode = _extractErrorCode(e.response?.data);
           final code = e.response?.statusCode;

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

           if (code == 422 || errCode == 'validation_error') {
               try {
                  final r2 = await _dio.post(ep, data: {"data": {"type": "paytoread", "attributes": {}}});
                  final r2Str = r2.data?.toString().toLowerCase() ?? '';
                  if (r2Str.contains('余额不足') || r2Str.contains('积分不足')) {
                     throw DioException(requestOptions: r2.requestOptions, response: r2, error: 'FALSE_POSITIVE_INTERCEPTED');
                  }
                  return;
               } on DioException catch (e2) {
                  bestErr = e2;
               }
           }

           if (bestErr?.error == 'FALSE_POSITIVE_INTERCEPTED') {
              throw Exception('余额不足或操作受限。');
           }

           if (errCode != 'not_found' && code != 404 && code != 422) {
              throw bestErr!;
           }
         }
      }

      if (routeExists && bestErr != null) {
         if (bestErr.error == 'FALSE_POSITIVE_INTERCEPTED') throw Exception('余额不足或操作受限。');
         throw bestErr;
      }
    }

    if (bestErr != null) {
       if (bestErr.error == 'FALSE_POSITIVE_INTERCEPTED') throw Exception('余额不足或操作受限。');
       throw bestErr;
    }
    throw Exception('未匹配到有效的购买接口，请确认后端插件已启用 API 支持。');
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
