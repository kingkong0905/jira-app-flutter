import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../theme/app_theme.dart';

/// Widget for uploading attachments with preview and remove functionality
class AttachmentUploadWidget extends StatefulWidget {
  final List<AttachmentItem> attachments;
  final Function(AttachmentItem) onAttachmentAdded;
  final Function(AttachmentItem) onAttachmentRemoved;
  final String? issueKey; // Required for uploading to existing issue
  final quill.QuillController? editorController; // Optional: insert attachments into editor after upload
  final Function(String attachmentId, String filename, bool isImage)? onAttachmentUploaded; // Callback when attachment is uploaded

  const AttachmentUploadWidget({
    super.key,
    required this.attachments,
    required this.onAttachmentAdded,
    required this.onAttachmentRemoved,
    this.issueKey,
    this.editorController,
    this.onAttachmentUploaded,
  });

  @override
  State<AttachmentUploadWidget> createState() => _AttachmentUploadWidgetState();
}

class _AttachmentUploadWidgetState extends State<AttachmentUploadWidget> {
  bool _uploading = false;

  Future<void> _pickFile() async {
    debugPrint('_pickFile() called');
    try {
      debugPrint('Opening file picker... (Platform: ${kIsWeb ? "Web" : "Native"})');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true, // Always request data to ensure we can access files
        withReadStream: false, // We'll read the entire file
      );
      debugPrint('File picker returned: ${result != null ? "result with ${result.files.length} files" : "null (cancelled)"}');

      // Check if user cancelled (result is null) - this is normal, don't show error
      if (result == null) {
        debugPrint('File picker cancelled by user');
        return;
      }

      // Check if files were actually selected
      if (result.files.isEmpty) {
        debugPrint('FilePicker returned empty files list');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files were selected')),
          );
        }
        return;
      }

      debugPrint('FilePicker selected ${result.files.length} file(s)');
      int successCount = 0;
      
      for (final file in result.files) {
        debugPrint('Processing file: ${file.name}, path: ${file.path}, bytes: ${file.bytes != null ? file.bytes!.length : 0}');
        
        try {
          AttachmentItem? attachment;
          
          // Prefer file path if available (mobile/desktop)
          if (file.path != null && !kIsWeb) {
            attachment = AttachmentItem(
              filePath: file.path!,
              filename: file.name,
              size: file.size,
            );
            debugPrint('Added attachment with path: ${attachment.filePath}');
          } 
          // Fallback to bytes if path is not available (web or some mobile scenarios)
          else if (file.bytes != null) {
            if (kIsWeb) {
              // On web, store bytes directly
              attachment = AttachmentItem(
                filePath: null,
                filename: file.name,
                size: file.size,
                fileBytes: file.bytes,
              );
              debugPrint('Added attachment with bytes (web): ${attachment.filename}');
            } else {
              // Mobile/Desktop but path unavailable: save to temp file
              try {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File('${tempDir.path}/${file.name}');
                await tempFile.writeAsBytes(file.bytes!);
                
                attachment = AttachmentItem(
                  filePath: tempFile.path,
                  filename: file.name,
                  size: file.size,
                );
                debugPrint('Added attachment with temp path: ${attachment.filePath}');
              } catch (tempError) {
                debugPrint('Error creating temp file: $tempError');
                // Fallback: store bytes directly even on mobile if temp file fails
                attachment = AttachmentItem(
                  filePath: null,
                  filename: file.name,
                  size: file.size,
                  fileBytes: file.bytes,
                );
                debugPrint('Added attachment with bytes (fallback): ${attachment.filename}');
              }
            }
          } else {
            debugPrint('File ${file.name} has no path or bytes - requesting bytes...');
            // Try to read bytes if not already loaded
            if (!kIsWeb && file.path != null) {
              try {
                final fileBytes = await File(file.path!).readAsBytes();
                final tempDir = await getTemporaryDirectory();
                final tempFile = File('${tempDir.path}/${file.name}');
                await tempFile.writeAsBytes(fileBytes);
                
                attachment = AttachmentItem(
                  filePath: tempFile.path,
                  filename: file.name,
                  size: fileBytes.length,
                );
                debugPrint('Added attachment by reading file: ${attachment.filePath}');
              } catch (readError) {
                debugPrint('Error reading file: $readError');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not access file ${file.name}: $readError')),
                  );
                }
                continue;
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('File ${file.name} could not be accessed (no path or bytes)')),
                );
              }
              continue;
            }
          }
          
          if (attachment != null) {
            widget.onAttachmentAdded(attachment);
            successCount++;
          }
        } catch (e) {
          debugPrint('Error processing file ${file.name}: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to process ${file.name}: $e')),
            );
          }
        }
      }
      
      if (successCount > 0 && mounted) {
        debugPrint('Successfully added $successCount file(s)');
      }
    } catch (e) {
      debugPrint('FilePicker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachments.isEmpty) {
      return InkWell(
        onTap: () {
          debugPrint('Attach file button tapped');
          _pickFile();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file, size: AppTheme.iconSizeSm, color: AppTheme.textMuted),
              const SizedBox(width: AppTheme.spaceSm),
              Text(
                'Attach file',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBase,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Add more button
        InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: AppTheme.iconSizeSm, color: AppTheme.primary),
                const SizedBox(width: AppTheme.spaceXs),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBase,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Attachment chips
        ...widget.attachments.map((attachment) => _buildAttachmentChip(attachment)),
      ],
    );
  }

  Widget _buildAttachmentChip(AttachmentItem attachment) {
    final isImage = attachment.filename.toLowerCase().endsWith('.jpg') ||
        attachment.filename.toLowerCase().endsWith('.jpeg') ||
        attachment.filename.toLowerCase().endsWith('.png') ||
        attachment.filename.toLowerCase().endsWith('.gif') ||
        attachment.filename.toLowerCase().endsWith('.webp');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImage && (attachment.filePath != null || attachment.fileBytes != null))
            Container(
              width: AppTheme.widthXxl,
              height: AppTheme.widthXxl,
              margin: AppTheme.paddingRight8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: attachment.filePath != null
                    ? DecorationImage(
                        image: FileImage(File(attachment.filePath!)),
                        fit: BoxFit.cover,
                      )
                    : (attachment.fileBytes != null
                        ? DecorationImage(
                            image: MemoryImage(attachment.fileBytes!),
                            fit: BoxFit.cover,
                          )
                        : null),
              ),
            )
          else
            Icon(
              Icons.insert_drive_file,
              size: AppTheme.iconSizeSm,
              color: AppTheme.textMuted,
            ),
          Flexible(
            child: Text(
              attachment.filename,
              style: const TextStyle(fontSize: AppTheme.fontSizeMd, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (attachment.size != null) ...[
            const SizedBox(width: AppTheme.spaceXs),
            Text(
              _formatFileSize(attachment.size!),
              style: TextStyle(fontSize: AppTheme.fontSizeXs, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(width: AppTheme.spaceXs),
          InkWell(
            onTap: () => widget.onAttachmentRemoved(attachment),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: AppTheme.iconSizeXs,
                color: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Represents an attachment item (local file or uploaded attachment)
class AttachmentItem {
  final String? filePath; // Local file path (for new uploads, null on web)
  final String filename;
  final int? size;
  final Uint8List? fileBytes; // File bytes (for web platform where path is unavailable)
  final String? attachmentId; // Jira attachment ID (after upload)
  final String? contentUrl; // Jira attachment content URL (after upload)
  final String? mimeType; // MIME type of the attachment

  AttachmentItem({
    this.filePath,
    required this.filename,
    this.size,
    this.fileBytes,
    this.attachmentId,
    this.contentUrl,
    this.mimeType,
  });

  bool get isUploaded => attachmentId != null;
  bool get hasFile => filePath != null || fileBytes != null;
  bool get isImage => mimeType?.startsWith('image/') == true ||
      filename.toLowerCase().endsWith('.jpg') ||
      filename.toLowerCase().endsWith('.jpeg') ||
      filename.toLowerCase().endsWith('.png') ||
      filename.toLowerCase().endsWith('.gif') ||
      filename.toLowerCase().endsWith('.webp');
}
