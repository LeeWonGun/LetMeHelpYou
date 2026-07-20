// lib/ui/clipboard_and_save.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

Future<void> copyToClipboard(
    BuildContext context,
    String text, {
      String ok = '복사되었습니다.',
    }) async {
  await Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
}

Future<void> saveImageToGallery(
    BuildContext context,
    String url, {
      String? name, // 확장자 없이 전달해도 됨(아래에서 .png 붙임)
    }) async {
  try {
    // 1) 다운로드
    final resp = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final Uint8List bytes = Uint8List.fromList(resp.data ?? const []);

    // 2) 임시 파일 저장
    final dir = await getTemporaryDirectory();
    final base = (name == null || name.trim().isEmpty)
        ? 'lecture_ai_${DateTime.now().millisecondsSinceEpoch}'
        : name.trim();
    final fileNameWithExt = '$base.png'; // 저장 파일명
    final filePath = '${dir.path}/$fileNameWithExt';
    final f = File(filePath);
    await f.writeAsBytes(bytes, flush: true);

    // 3) 갤러리에 저장 (필수 named 인자 3개!)
    final result = await SaverGallery.saveFile(
      filePath: filePath,
      fileName: fileNameWithExt,
      skipIfExists: false,                       // 같은 이름이어도 저장
      androidRelativePath: 'Pictures/LectureAI', // (선택) 안드로이드 폴더
    );

    // 4) 임시 파일 정리(실패해도 무시)
    try { await f.delete(); } catch (_) {}

    final ok = result.isSuccess;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '이미지 저장 완료' : '이미지 저장 실패')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('이미지 저장 실패: $e')),
    );
  }
}
