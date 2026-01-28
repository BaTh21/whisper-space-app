import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:whisper_space_flutter/core/constants/api_constants.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'inbox_model/inbox_model.dart';

class InboxAPISource {
  final StorageService storageService;
  final String? baseUrl;

  InboxAPISource({
    required this.storageService,
    String? baseUrl
   }): baseUrl = baseUrl ?? ApiConstants.baseUrl;

  Future<Map<String, String>> _authHeader() async{
    final token = storageService.getToken();
    return {
      ...ApiConstants.defaultHeaders,
      'Authorization': 'Bearer $token'
    };
  }

  Future<List<InboxModel>> getActivities({int limit = 20, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/api/v1/activities/?limit=$limit&offset=$offset');
    final response = await http.get(uri, headers: await _authHeader());

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((json) => InboxModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? error['msg'] ?? 'No activity found');
    }
  }

  Future<void> readActivity(int activityId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/v1/activities/$activityId/read'),
      headers: await _authHeader(),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? data['msg'] ?? data['message'] ?? 'Cannot read activity');
    }
  }

  Future<void> deleteActivityById(int activityId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/activities/$activityId'),
      headers: await _authHeader(),
    );

    if (response.statusCode != 204) {
      String errorMessage = 'Cannot delete activity';
      try {
        final data = jsonDecode(response.body);
        errorMessage = data['message'] ?? errorMessage;
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  Future<void> deleteSelectedActivities(List<int> activityIds) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/activities/delete'),
      headers: {
        ...await _authHeader(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'ids': activityIds,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(
        error['detail'] ?? error['message'] ?? 'Cannot delete activities',
      );
    }
  }

  Future<int> getUnreadActivityCount() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/activities/unread/count'),
      headers: await _authHeader(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['unread_count'] as int;
    } else {
      throw Exception('Failed to load unread activity count');
    }
  }

  Future<void> markAllActivitiesAsRead() async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/v1/activities/read-all'),
      headers: await _authHeader(),
    );
    final error = jsonDecode(response.body);
    if(response.statusCode != 200){
      throw Exception(error['details'] ?? error['message'] ?? error['msg']);
    }
  }

  Future<void> acceptFriendRequest(int actorId) async{
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/accept/$actorId'),
      headers: await _authHeader()
    );
    final error = jsonDecode(response.body);
    if(response.statusCode != 200){
      throw Exception(error['details'] ?? error['message'] ?? error['msg']);
    }
  }

  Future<void> acceptGroupInvite(int groupId) async{
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/groups/invites/$groupId/accept'),
      headers: await _authHeader()
    );
    final error = jsonDecode(response.body);
    if(response.statusCode != 200){
      throw Exception(error['details'] ?? error['message'] ?? error['msg']);
    }
  }

}
