import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class ApiService {
  final String baseUrl;
  final Map<String, String> defaultHeaders;
  
  ApiService({
    String? baseUrl,
    Map<String, String>? defaultHeaders,
  }) : baseUrl = baseUrl ?? ApiConstants.baseUrl,
       defaultHeaders = defaultHeaders ?? ApiConstants.defaultHeaders;
  
  Future<http.Response> post(
    String endpoint, 
    Map<String, dynamic> body,
    {Map<String, String>? headers,
    bool includeAuth = false}
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final mergedHeaders = {
      ...defaultHeaders,
      ...?headers,
    };
    
    try {
      return await http.post(
        url,
        headers: mergedHeaders,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<http.Response> get(
    String endpoint,
    {Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
    bool includeAuth = false}
  ) async {
    var url = Uri.parse('$baseUrl$endpoint');
    
    if (queryParams != null) {
      url = url.replace(queryParameters: queryParams.map((key, value) => MapEntry(key, value.toString())));
    }
    
    final mergedHeaders = {
      ...defaultHeaders,
      ...?headers,
    };
    
    try {
      return await http.get(url, headers: mergedHeaders)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> body,
    {Map<String, String>? headers,
    bool includeAuth = true}
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final mergedHeaders = {
      ...defaultHeaders,
      ...?headers,
    };
    
    try {
      return await http.put(
        url,
        headers: mergedHeaders,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<http.Response> delete(
    String endpoint,
    {Map<String, String>? headers,
    bool includeAuth = true}
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final mergedHeaders = {
      ...defaultHeaders,
      ...?headers,
    };
    
    try {
      return await http.delete(
        url,
        headers: mergedHeaders,
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}