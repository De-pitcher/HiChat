import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

/// Test utility for video thumbnail generation
class ThumbnailTestUtil {
  
  /// Test thumbnail generation for a video file
  static Future<void> testThumbnailGeneration(String videoPath) async {
    try {
      debugPrint('🧪 Testing thumbnail generation for: $videoPath');
      
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('🧪 ❌ Video file does not exist');
        return;
      }
      
      debugPrint('🧪 Video file size: ${await videoFile.length()} bytes');
      
      final appDir = await getApplicationDocumentsDirectory();
      final testDir = Directory('${appDir.path}/test_thumbnails');
      if (!await testDir.exists()) {
        await testDir.create(recursive: true);
      }
      
      final thumbnailPath = '${testDir.path}/test_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      debugPrint('🧪 Generating thumbnail to: $thumbnailPath');
      
      // Test 1: Generate thumbnail data
      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
        timeMs: 1000, // 1 second into video
      );
      
      if (thumbnailData != null) {
        debugPrint('🧪 ✅ Thumbnail data generated: ${thumbnailData.length} bytes');
        
        // Save thumbnail to file
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(thumbnailData);
        
        final savedExists = await thumbnailFile.exists();
        debugPrint('🧪 Thumbnail file saved: $savedExists');
        debugPrint('🧪 Thumbnail file size: ${savedExists ? await thumbnailFile.length() : 0} bytes');
        
        if (savedExists) {
          debugPrint('🧪 ✅ Thumbnail generation test PASSED');
        } else {
          debugPrint('🧪 ❌ Thumbnail file save FAILED');
        }
      } else {
        debugPrint('🧪 ❌ Thumbnail data generation FAILED');
      }
      
    } catch (error, stackTrace) {
      debugPrint('🧪 ❌ Thumbnail generation test ERROR: $error');
      debugPrint('🧪 Stack trace: $stackTrace');
    }
  }
  
  /// Test thumbnail generation with different parameters
  static Future<void> testThumbnailVariants(String videoPath) async {
    final testCases = [
      {'timeMs': 0, 'quality': 50, 'maxWidth': 200},
      {'timeMs': 1000, 'quality': 75, 'maxWidth': 300},
      {'timeMs': 2000, 'quality': 90, 'maxWidth': 400},
    ];
    
    for (int i = 0; i < testCases.length; i++) {
      final testCase = testCases[i];
      debugPrint('🧪 Testing variant ${i + 1}: $testCase');
      
      try {
        final thumbnailData = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: testCase['maxWidth'] as int,
          quality: testCase['quality'] as int,
          timeMs: testCase['timeMs'] as int,
        );
        
        if (thumbnailData != null) {
          debugPrint('🧪 ✅ Variant ${i + 1} SUCCESS: ${thumbnailData.length} bytes');
        } else {
          debugPrint('🧪 ❌ Variant ${i + 1} FAILED: null data');
        }
      } catch (error) {
        debugPrint('🧪 ❌ Variant ${i + 1} ERROR: $error');
      }
    }
  }
}