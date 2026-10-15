import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import 'api_service.dart';

class RCImageApi {
  /// 上传图片到七牛云
  static Future<String?> uploadImage(File imageFile) async {
    final tokenUrl = '/pc/generate_qiniu_token';
    final jsonData = {
      'bucket_name': 'cms-attachment',
      'expired_time': 3600
    };
    final tokenResponse = await ApiService.sendRequest(tokenUrl, method: 'POST', body: jsonData);

    if (tokenResponse == null || tokenResponse.data == null ||
        tokenResponse.data['success'] != true ||
        tokenResponse.data['data'] == null) {
      debugPrint('Failed to get qiniu token');
      return null;
    }

    final token = tokenResponse.data['data']['token'];

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final originalFileName = imageFile.uri.pathSegments.isNotEmpty
        ? imageFile.uri.pathSegments.last
        : imageFile.path.split(RegExp(r'[/\\]')).last;
    final fileName = '$timestamp$originalFileName';

    final uploadUrl = 'https://upload.qiniup.com/';
    FormData formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
      'token': token,
      'key': fileName,
      'fname': originalFileName
    });
    final uploadResponse = await ApiService.sendRequest(uploadUrl, method: 'POST', body: formData);

    if (uploadResponse == null ||
        uploadResponse.data == null ||
        (uploadResponse.data is Map &&
            uploadResponse.data['key'] == null &&
            uploadResponse.data['success'] != true)) {
      debugPrint('Failed to upload to qiniu: ${uploadResponse?.data}');
      return null;
    }

    final key = uploadResponse.data is Map ? uploadResponse.data['key'] : null;
    if (key == null) return null;
    final imageUrl = 'https://qn-scd1.yuketang.cn/$key';
    return imageUrl;
  }
}