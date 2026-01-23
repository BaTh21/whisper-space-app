import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:whisper_space_flutter/core/constants/api_constants.dart';

import 'package:whisper_space_flutter/core/services/storage_service.dart';

class FriendAPISource {
  final StorageService storageService;
  final String baseUrl;

  FriendAPISource({
    required this.storageService,
    String? baseUrl
  }): baseUrl = baseUrl ?? ApiConstants.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = storageService.getToken();
    print('Token: $token');
    return {
      ...ApiConstants.defaultHeaders,
      'Authorization': 'Bearer $token'
    };
  }

  Future<List<dynamic>> getFriends() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/friends/'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch friends: ${response.statusCode}');
    }
  }

  Future<void> sendFriendRequest(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/request/$userId'),
      headers: await _authHeaders(),
    );

    if(response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<List<dynamic>> getPendingRequests() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/friends/pending'),
      headers: await _authHeaders()
    );

    if (response.statusCode == 200){
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load pending request ${response.statusCode}');
  }

  Future<void> cancelPending(int pendingId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/friends/pending/$pendingId'),
      headers: await _authHeaders()
    );

    if (response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<List<dynamic>> getRequestingUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/friends/requests'),
      headers: await _authHeaders()
    );
    if(response.statusCode == 200){
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load pending request ${response.statusCode}');
  }

  Future<void> acceptFriendRequest(int requesterId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/accept/$requesterId'),
      headers: await _authHeaders()
    );
    if (response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> unfriend(int friendId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/unfriend/$friendId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }
  
  Future<List<dynamic>> getBlockedUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/friends/blocked'),
      headers: await _authHeaders()
    );
    if (response.statusCode == 200){
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get blocked users ${response.statusCode}');
  }

  Future<void> blockUser(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/block/$userId'),
      headers: await _authHeaders()
    );

    if(response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }
  
  Future<void> unblockUser(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/friends/unblock/$userId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 200){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<List<dynamic>> getSuggestionUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/users/suggestions'),
      headers: await _authHeaders()
    );
    if(response.statusCode == 200){
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get suggested users ${response.statusCode}');
  }
}