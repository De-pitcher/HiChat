import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Debug utility to check media cache contents
class MediaCacheDebugger {
  
  /// Debug the entire media cache structure
  static Future<void> debugCacheContents() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/media_cache');
      
      debugPrint('🔍 === MEDIA CACHE DEBUG ===');
      debugPrint('🔍 Cache directory: ${cacheDir.path}');
      debugPrint('🔍 Cache exists: ${await cacheDir.exists()}');
      
      if (await cacheDir.exists()) {
        await _debugDirectory(cacheDir, 0);
      }
      
      debugPrint('🔍 === END CACHE DEBUG ===');
    } catch (error) {
      debugPrint('🔍 Error debugging cache: $error');
    }
  }
  
  /// Debug a specific directory recursively
  static Future<void> _debugDirectory(Directory dir, int depth) async {
    final indent = '  ' * depth;
    
    try {
      final items = await dir.list().toList();
      
      debugPrint('$indent📁 ${dir.path.split('/').last}/ (${items.length} items)');
      
      for (final item in items) {
        if (item is Directory) {
          await _debugDirectory(item, depth + 1);
        } else if (item is File) {
          final stat = await item.stat();
          final name = item.path.split('/').last;
          final size = '${(stat.size / 1024).toStringAsFixed(1)} KB';
          debugPrint('$indent  📄 $name ($size)');
        }
      }
    } catch (error) {
      debugPrint('$indent❌ Error reading directory: $error');
    }
  }
  
  /// Debug metadata file
  static Future<void> debugMetadata() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final metadataFile = File('${appDir.path}/media_cache/metadata.json');
      
      debugPrint('🔍 === METADATA DEBUG ===');
      debugPrint('🔍 Metadata file: ${metadataFile.path}');
      debugPrint('🔍 Exists: ${await metadataFile.exists()}');
      
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        debugPrint('🔍 Content length: ${content.length} characters');
        debugPrint('🔍 Content preview: ${content.length > 200 ? '${content.substring(0, 200)}...' : content}');
      }
      
      debugPrint('🔍 === END METADATA DEBUG ===');
    } catch (error) {
      debugPrint('🔍 Error debugging metadata: $error');
    }
  }
}