import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:whisper_space_flutter/core/constants/api_constants.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import '../chat/model/chat_model/chat_list_model.dart';
import '../chat/model/group_model/group_details_model.dart';
import '../chat/model/group_message_model/group_message_model.dart';
import '../chat/model/group_model/user_model.dart';
import '../chat/model/group_model/group_image_model.dart';

class ChatAPISource {
  final StorageService storageService;
  final String baseUrl;

  ChatAPISource({
    required this.storageService,
    String? baseUrl
  }): baseUrl = baseUrl ?? ApiConstants.baseUrl;

  Future<Map<String, String>> _authHeaders() async{
    final token = storageService.getToken();
    if (token == null) {
      throw Exception('Auth token is null');
    }

    return{
      ...ApiConstants.defaultHeaders,
      'Authorization': 'Bearer $token'
    };
  }

  Future<List<ChatListItemModel>> getChats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/chats/'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json)=>ChatListItemModel.fromJson(json)).toList();
    } else {
      throw Exception(
        'Failed to load chats (${response.statusCode})',
      );
    }
  }

  Future<GroupDetailsModel> createNewGroup({
    required String name,
    String? description,
    List<int> inviteUserIds = const [],
  }) async{
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/groups/'),
      headers: {
        ...(await _authHeaders()),
        'Content-Type':'application/json'
      },
      body: jsonEncode({
        'name': name,
        'description': description,
        'invite_user_ids': inviteUserIds
      }
      )
    );
    if(response.statusCode == 201){
      final Map<String, dynamic> data = jsonDecode(response.body);
      return GroupDetailsModel.fromJson(data);
    }
    else{
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<GroupDetailsModel> getGroupById(int groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/groups/$groupId'),
      headers: await _authHeaders()
    );

    if(response.statusCode == 200){
      final Map<String, dynamic> data = jsonDecode(response.body);
      print('data $data');
      return GroupDetailsModel.fromJson(data);
    }else{
      throw Exception('Failed to group chat ($groupId) –  ${response.statusCode}');
    }
  }

  Future<GroupDetailsModel> updateGroupById(
      int groupId, {
        String? name,
        String? description,
      }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/v1/groups/$groupId'),
      headers: {
        ...(await _authHeaders()),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return GroupDetailsModel.fromJson(data);
    } else {
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> deleteGroupId(int groupId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/groups/$groupId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 204){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> leaveGroupById(int groupId) async{
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/groups/leave/$groupId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 204){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<List<UserModel>> getGroupMembers(int groupId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/groups/$groupId/members/'),
      headers: await _authHeaders()
    );
    if(response.statusCode == 200){
      final List data = jsonDecode(response.body);
      return data.map((json)=>UserModel.fromJson(json)).toList();
    }else{
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<List<GroupMessageModel>> getGroupMessage(int groupId) async{
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/groups/$groupId/messages'),
      headers: await _authHeaders()
    );
    final List data = jsonDecode(response.body);
    return data.map((json)=> GroupMessageModel.fromJson(json)).toList();
  }

  Future<void> inviteUser(int groupId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/groups/$groupId/invites/$userId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 200){
      throw Exception(jsonDecode(response.body));
    }
  }

  Future<void> removeMember(int groupId, int memberId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/groups/remove/$groupId/members/$memberId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 204){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> uploadGroupCover(int groupId, File file) async {
    final uri = Uri.parse('$baseUrl/api/v1/groups/$groupId/cover');

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _authHeaders());

    request.files.add(
      await http.MultipartFile.fromPath(
        'cover',
        file.path,
      ),
    );

    final response = await request.send();

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = await response.stream.bytesToString();
      throw Exception(body);
    }
  }

  Future<List<GroupImage>> getGroupCovers(int groupId) async{
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/groups/$groupId/cover'),
      headers: await _authHeaders()
    );
    if(response.statusCode == 200){
      final List data = jsonDecode(response.body);
      return data.map((json)=> GroupImage.fromJson(json)).toList();
    }else{
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> deleteCoverById(int coverId) async{
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/groups/cover/$coverId'),
      headers: await _authHeaders()
    );
    if(response.statusCode != 204){
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }
}
