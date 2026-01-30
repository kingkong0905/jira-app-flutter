// Converts between Jira ADF (Atlassian Document Format) and Quill Delta for description editing.
// ADF doc: { type: 'doc', version: 1, content: [ paragraph | heading | bulletList | orderedList | codeBlock ... ] }
/// Quill Delta: { ops: [ { insert: string, attributes?: { bold, italic, link, header, list, 'code-block' } } ] }

List<Map<String, dynamic>> adfToQuillOps(dynamic adf) {
  final ops = <Map<String, dynamic>>[];
  if (adf == null) return ops;
  if (adf is String) {
    final t = (adf as String).trim();
    if (t.isEmpty) {
      ops.add({'insert': '\n'});
      return ops;
    }
    for (final line in t.split('\n')) {
      ops.add({'insert': line});
      ops.add({'insert': '\n'});
    }
    return ops;
  }
  if (adf is! Map) return ops;
  final content = adf['content'];
  if (content is! List) {
    ops.add({'insert': '\n'});
    return ops;
  }
  for (final node in content) {
    if (node is! Map) continue;
    final type = node['type']?.toString() ?? '';
    final nodeContent = node['content'];
    if (type == 'paragraph') {
      _emitInlineContent(nodeContent, ops);
      ops.add({'insert': '\n'});
    } else if (type == 'heading') {
      final level = (node['attrs'] is Map) ? (node['attrs'] as Map)['level'] : 1;
      final l = level is int ? level : (level is double ? level.toInt() : 1);
      _emitInlineContent(nodeContent, ops);
      ops.add({'insert': '\n', 'attributes': {'header': l.clamp(1, 6)}});
    } else if (type == 'codeBlock' && nodeContent is List) {
      final code = nodeContent.map((c) => _plainFromNode(c)).join('');
      ops.add({'insert': code});
      ops.add({'insert': '\n', 'attributes': {'code-block': true}});
    } else if (type == 'bulletList' && nodeContent is List) {
      for (final item in nodeContent) {
        if (item is Map && item['type'] == 'listItem' && item['content'] is List) {
          for (final block in item['content'] as List) {
            if (block is Map && block['type'] == 'paragraph' && block['content'] != null) {
              _emitInlineContent(block['content'], ops);
              break;
            }
          }
          ops.add({'insert': '\n', 'attributes': {'list': 'bullet'}});
        }
      }
    } else if (type == 'orderedList' && nodeContent is List) {
      for (final item in nodeContent) {
        if (item is Map && item['type'] == 'listItem' && item['content'] is List) {
          for (final block in item['content'] as List) {
            if (block is Map && block['type'] == 'paragraph' && block['content'] != null) {
              _emitInlineContent(block['content'], ops);
              break;
            }
          }
          ops.add({'insert': '\n', 'attributes': {'list': 'ordered'}});
        }
      }
    } else if (type == 'mediaSingle' && nodeContent is List) {
      for (final media in nodeContent) {
        if (media is Map) {
          final attrs = media['attrs'];
          if (attrs is Map) {
            final id = attrs['id']?.toString() ?? '';
            final alt = attrs['alt']?.toString() ?? '';
            final filename = alt.isNotEmpty ? alt : (id.isNotEmpty ? 'attachment' : '');
            final isImage = attrs['type']?.toString() == 'file' && 
                (filename.toLowerCase().endsWith('.jpg') ||
                 filename.toLowerCase().endsWith('.jpeg') ||
                 filename.toLowerCase().endsWith('.png') ||
                 filename.toLowerCase().endsWith('.gif') ||
                 filename.toLowerCase().endsWith('.webp'));
            
            if (id.isNotEmpty) {
              final marker = isImage 
                  ? '[image:$id:$filename]'
                  : '[attachment:$id:$filename]';
              ops.add({'insert': marker});
            } else {
              final placeholder = alt.isNotEmpty ? '[Image: $alt]' : '[Image]';
              ops.add({'insert': placeholder});
            }
            ops.add({'insert': '\n'});
          }
        }
      }
    } else if (type == 'mediaGroup' && nodeContent is List) {
      for (final media in nodeContent) {
        if (media is Map) {
          final attrs = media['attrs'];
          if (attrs is Map) {
            final id = attrs['id']?.toString() ?? '';
            final alt = attrs['alt']?.toString() ?? '';
            final filename = alt.isNotEmpty ? alt : (id.isNotEmpty ? 'attachment' : '');
            final isImage = attrs['type']?.toString() == 'file' && 
                (filename.toLowerCase().endsWith('.jpg') ||
                 filename.toLowerCase().endsWith('.jpeg') ||
                 filename.toLowerCase().endsWith('.png') ||
                 filename.toLowerCase().endsWith('.gif') ||
                 filename.toLowerCase().endsWith('.webp'));
            
            if (id.isNotEmpty) {
              final marker = isImage 
                  ? '[image:$id:$filename]'
                  : '[attachment:$id:$filename]';
              ops.add({'insert': marker});
            } else {
              final placeholder = alt.isNotEmpty ? '[Image: $alt]' : '[Image]';
              ops.add({'insert': placeholder});
            }
            ops.add({'insert': '\n'});
          }
        }
      }
    }
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return ops;
}

void _emitInlineContent(dynamic content, List<Map<String, dynamic>> ops) {
  if (content is! List) return;
  for (final item in content) {
    if (item is! Map) continue;
    final type = item['type']?.toString() ?? '';
    if (type == 'text') {
      final text = item['text']?.toString() ?? '';
      final marks = item['marks'] as List?;
      Map<String, dynamic>? attrs;
      if (marks != null) {
        for (final m in marks) {
          if (m is Map) {
            if (m['type'] == 'strong') attrs = {...?attrs, 'bold': true};
            else if (m['type'] == 'em') attrs = {...?attrs, 'italic': true};
            else if (m['type'] == 'link' && m['attrs'] is Map) {
              final href = (m['attrs'] as Map)['href']?.toString();
              if (href != null) attrs = {...?attrs, 'link': href};
            }
            else if (m['type'] == 'code') attrs = {...?attrs, 'code': true};
          }
        }
      }
      if (text.isNotEmpty) {
        if (attrs != null && attrs.isNotEmpty) {
          ops.add({'insert': text, 'attributes': attrs});
        } else {
          ops.add({'insert': text});
        }
      }
    } else if (type == 'mention') {
      final attrs = item['attrs'];
      final text = attrs is Map ? (attrs['text'] ?? attrs['id'] ?? 'user')?.toString() ?? 'user' : 'user';
      final mentionText = text.startsWith('@') ? text : '@$text';
      ops.add({'insert': mentionText});
    } else if (type == 'inlineCard') {
      final attrs = item['attrs'];
      final url = attrs is Map ? (attrs['url'] as String?) ?? '' : '';
      if (url.isNotEmpty) {
        ops.add({'insert': url, 'attributes': {'link': url}});
      } else {
        ops.add({'insert': '[Link]'});
      }
    } else if (type == 'mediaInline' || type == 'media') {
      // Handle inline media (for comments)
      final attrs = item['attrs'];
      if (attrs is Map) {
        final id = attrs['id']?.toString() ?? '';
        final alt = attrs['alt']?.toString() ?? attrs['url']?.toString() ?? '';
        final isImage = attrs['type']?.toString() == 'file' && 
            (alt.toLowerCase().endsWith('.jpg') ||
             alt.toLowerCase().endsWith('.jpeg') ||
             alt.toLowerCase().endsWith('.png') ||
             alt.toLowerCase().endsWith('.gif') ||
             alt.toLowerCase().endsWith('.webp'));
        if (id.isNotEmpty) {
          final marker = isImage 
              ? '[image:$id:$alt]'
              : '[attachment:$id:$alt]';
          ops.add({'insert': marker});
        } else if (alt.isNotEmpty) {
          ops.add({'insert': '[Attachment: $alt]'});
        }
      }
    } else if (type == 'hardBreak') {
      ops.add({'insert': '\n'});
    }
  }
}

String _plainFromNode(dynamic node) {
  if (node == null) return '';
  if (node is String) return node;
  if (node is Map) {
    final t = node['text'];
    if (t is String) return t;
    final c = node['content'];
    if (c is List) return c.map(_plainFromNode).join('');
  }
  if (node is List) return node.map(_plainFromNode).join('');
  return '';
}

/// Convert Quill Delta ops to ADF document.
/// Handles attachment markers like [attachment:ID:filename] and [image:ID:filename],
/// converting them to ADF mediaSingle nodes with media content.
Map<String, dynamic> quillOpsToAdf(List<dynamic> opsList) {
  final content = <Map<String, dynamic>>[];
  if (opsList.isEmpty) {
    content.add({'type': 'paragraph', 'content': []});
    return {'type': 'doc', 'version': 1, 'content': content};
  }
  final ops = opsList.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
  int i = 0;
  String buffer = '';
  Map<String, dynamic>? bufferAttrs;

  void flushParagraph() {
    if (buffer.isEmpty && bufferAttrs == null) return;
    final inline = buffer.isEmpty ? [] : [_textNode(buffer, bufferAttrs)];
    content.add({'type': 'paragraph', 'content': inline});
    buffer = '';
    bufferAttrs = null;
  }

  void flushHeading(int level) {
    final inline = buffer.isEmpty ? [] : [_textNode(buffer, bufferAttrs)];
    content.add({'type': 'heading', 'attrs': {'level': level.clamp(1, 6)}, 'content': inline});
    buffer = '';
    bufferAttrs = null;
  }

  void flushCodeBlock() {
    if (buffer.isEmpty) {
      content.add({'type': 'codeBlock', 'content': []});
    } else {
      content.add({'type': 'codeBlock', 'content': [{'type': 'text', 'text': buffer}]});
    }
    buffer = '';
    bufferAttrs = null;
  }

  void flushList(String listType) {
    final inline = buffer.isEmpty ? [] : [_textNode(buffer, bufferAttrs)];
    final listItem = {'type': 'listItem', 'content': [{'type': 'paragraph', 'content': inline}]};
    final last = content.isNotEmpty ? content.last : null;
    if (last != null && last['type'] == (listType == 'bullet' ? 'bulletList' : 'orderedList')) {
      (last['content'] as List).add(listItem);
    } else {
      content.add({
        'type': listType == 'bullet' ? 'bulletList' : 'orderedList',
        'content': [listItem],
      });
    }
    buffer = '';
    bufferAttrs = null;
  }

  // Pattern to match attachment markers: [attachment:ID:filename] or [image:ID:filename]
  final attachmentPattern = RegExp(r'\[(attachment|image):([^:]+):([^\]]+)\]');
  
  while (i < ops.length) {
    final op = ops[i];
    final insert = op['insert'];
    final attrs = op['attributes'] is Map ? Map<String, dynamic>.from(op['attributes'] as Map) : null;
    if (insert == null) {
      i++;
      continue;
    }
    if (insert is String) {
      final s = insert as String;
      if (s == '\n') {
        final header = attrs?['header'];
        final list = attrs?['list']?.toString();
        final codeBlock = attrs?['code-block'] == true;
        if (codeBlock) {
          flushCodeBlock();
        } else if (header != null) {
          final l = header is int ? header : (header is double ? header.toInt() : 1);
          flushHeading(l);
        } else if (list == 'bullet' || list == 'ordered') {
          flushList(list!);
        } else {
          flushParagraph();
        }
      } else {
        // Check for attachment markers in the text
        final matches = attachmentPattern.allMatches(s);
        if (matches.isEmpty) {
          buffer += s;
          bufferAttrs = attrs;
        } else {
          // Split text by attachment markers and process each part
          int lastEnd = 0;
          for (final match in matches) {
            // Add text before the marker
            if (match.start > lastEnd) {
              buffer += s.substring(lastEnd, match.start);
              bufferAttrs = attrs;
            }
            
            // Flush current paragraph before adding media
            if (buffer.isNotEmpty || bufferAttrs != null) {
              flushParagraph();
            }
            
            // Extract attachment info from marker
            final type = match.group(1) ?? 'attachment';
            final attachmentIdStr = match.group(2) ?? '';
            final filename = match.group(3) ?? '';
            final isImage = type == 'image' || filename.toLowerCase().endsWith('.jpg') ||
                filename.toLowerCase().endsWith('.jpeg') ||
                filename.toLowerCase().endsWith('.png') ||
                filename.toLowerCase().endsWith('.gif') ||
                filename.toLowerCase().endsWith('.webp');
            
            // Convert attachment ID to integer if possible (Jira expects numeric IDs)
            final attachmentIdNum = int.tryParse(attachmentIdStr);
            final attachmentId = attachmentIdNum ?? attachmentIdStr;
            
            // Create ADF media node
            // Use string representation of ID for consistency
            final mediaNode = {
              'type': 'media',
              'attrs': {
                'id': attachmentIdNum?.toString() ?? attachmentIdStr,
                'type': 'file',
                'collection': 'attachment',
                'width': isImage ? 300 : null,
                'height': isImage ? 200 : null,
                'alt': filename,
              },
            };
            
            // Wrap in mediaSingle for single images, or add to mediaGroup
            if (isImage) {
              content.add({
                'type': 'mediaSingle',
                'attrs': {'layout': 'center'},
                'content': [mediaNode],
              });
            } else {
              // For non-images, add as mediaSingle with file icon representation
              content.add({
                'type': 'mediaSingle',
                'attrs': {'layout': 'center'},
                'content': [mediaNode],
              });
            }
            
            lastEnd = match.end;
          }
          
          // Add remaining text after last marker
          if (lastEnd < s.length) {
            buffer += s.substring(lastEnd);
            bufferAttrs = attrs;
          }
        }
      }
    } else if (insert is Map) {
      // Handle Quill image embeds if present
      final imageUrl = insert['image']?.toString();
      if (imageUrl != null) {
        // Flush current paragraph before adding media
        if (buffer.isNotEmpty || bufferAttrs != null) {
          flushParagraph();
        }
        
        // Extract attachment ID from URL if it's a Jira attachment URL
        final attachmentIdMatch = RegExp(r'/attachment/(\d+)/').firstMatch(imageUrl);
        final attachmentIdStr = attachmentIdMatch?.group(1) ?? '';
        
        if (attachmentIdStr.isNotEmpty) {
          // Convert to integer then back to string (Jira expects numeric string IDs)
          final attachmentIdNum = int.tryParse(attachmentIdStr);
          content.add({
            'type': 'mediaSingle',
            'attrs': {'layout': 'center'},
            'content': [
              {
                'type': 'media',
                'attrs': {
                  'id': attachmentIdNum?.toString() ?? attachmentIdStr,
                  'type': 'file',
                  'collection': 'attachment',
                  'width': 300,
                  'height': 200,
                },
              },
            ],
          });
        }
      }
    }
    i++;
  }
  if (buffer.isNotEmpty || bufferAttrs != null) {
    flushParagraph();
  }
  if (content.isEmpty) content.add({'type': 'paragraph', 'content': []});
  return {'type': 'doc', 'version': 1, 'content': content};
}

Map<String, dynamic> _textNode(String text, Map<String, dynamic>? attrs) {
  if (attrs == null || attrs.isEmpty) return {'type': 'text', 'text': text};
  final marks = <Map<String, dynamic>>[];
  if (attrs['bold'] == true) marks.add({'type': 'strong'});
  if (attrs['italic'] == true) marks.add({'type': 'em'});
  if (attrs['code'] == true) marks.add({'type': 'code'});
  final link = attrs['link']?.toString();
  if (link != null && link.isNotEmpty) marks.add({'type': 'link', 'attrs': {'href': link}});
  if (marks.isEmpty) return {'type': 'text', 'text': text};
  return {'type': 'text', 'text': text, 'marks': marks};
}
