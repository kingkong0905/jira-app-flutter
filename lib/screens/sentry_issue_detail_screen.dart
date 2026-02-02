import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/sentry_models.dart';

/// Displays Sentry issue detail (title, culprit, tags, stack trace, breadcrumbs) from API.
class SentryIssueDetailScreen extends StatelessWidget {
  const SentryIssueDetailScreen({
    super.key,
    required this.detail,
    required this.onBack,
  });

  final SentryIssueDetail detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final issue = detail.issue;
    final event = detail.event;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        title: Text(issue.shortId.isNotEmpty ? issue.shortId : 'Issue'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title & level
              Text(
                issue.title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (issue.culprit != null && issue.culprit!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  issue.culprit!,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (issue.count != null && issue.count!.isNotEmpty)
                    _Chip(
                      label: AppLocalizations.of(context).eventCount(issue.count!),
                      color: colorScheme.primaryContainer,
                    ),
                  if (issue.level != null)
                    _Chip(label: issue.level!, color: _levelColor(issue.level!, colorScheme)),
                  if (issue.status != null) _Chip(label: issue.status!, color: colorScheme.primaryContainer),
                  if (issue.firstSeen != null) _Chip(label: 'First: ${_formatDate(issue.firstSeen!)}', color: colorScheme.surfaceContainerHighest),
                  if (issue.lastSeen != null) _Chip(label: 'Last: ${_formatDate(issue.lastSeen!)}', color: colorScheme.surfaceContainerHighest),
                ],
              ),
              const SizedBox(height: 24),

              // Tags
              if (issue.tags.isNotEmpty || (event?.tags.isNotEmpty ?? false)) ...[
                Text('Tags', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: (event?.tags.isNotEmpty == true ? event!.tags : issue.tags)
                      .map((t) => _Chip(label: '${t.key}: ${t.value}', color: colorScheme.surfaceContainerHighest))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Contexts (from event)
              if (event != null && event.contexts != null && event.contexts!.isNotEmpty) ...[
                _ContextsSection(contexts: event.contexts!, colorScheme: colorScheme, textTheme: textTheme),
                const SizedBox(height: 24),
              ],

              // Additional Data (from event.extra + non-standard context entries)
              if (event != null) ...[
                ..._buildAdditionalData(event, colorScheme, textTheme),
              ],

              // Stack trace (from event)
              if (event != null) ...[
                ..._buildEntries(context, event, colorScheme, textTheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Additional Data = event.extra from Sentry API (data sent when capturing the issue).
  List<Widget> _buildAdditionalData(SentryEvent event, ColorScheme colorScheme, TextTheme textTheme) {
    if (event.extra == null || event.extra!.isEmpty) return [];
    return [
      _AdditionalDataSection(extra: event.extra!, colorScheme: colorScheme, textTheme: textTheme),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildEntries(
    BuildContext context,
    SentryEvent event,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final list = <Widget>[];
    for (final entry in event.entries) {
      if (entry.type == 'exception' && entry.data != null) {
        final values = entry.data!['values'] as List<dynamic>?;
        if (values != null) {
          for (final v in values) {
            final map = v is Map ? Map<String, dynamic>.from(v) : null;
            if (map == null) continue;
            try {
              final ex = SentryExceptionValue.fromJson(map);
              list.add(_ExceptionStackBlock(
                exception: ex,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ));
              list.add(const SizedBox(height: 20));
            } catch (_) {}
          }
        }
      } else if (entry.type == 'breadcrumbs' && entry.data != null) {
        final values = entry.data!['values'] as List<dynamic>?;
        if (values != null && values.isNotEmpty) {
          list.add(_SectionTitle(title: 'Breadcrumbs'));
          list.add(const SizedBox(height: 8));
          list.add(_BreadcrumbsView(values: values, colorScheme: colorScheme, textTheme: textTheme));
          list.add(const SizedBox(height: 20));
        }
      }
    }
    return list;
  }

  Color _levelColor(String level, ColorScheme colorScheme) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'fatal':
        return colorScheme.errorContainer;
      case 'warning':
      case 'warn':
        return colorScheme.tertiaryContainer;
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.month}/${d.day}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Exception block: title, mechanism chips, stack trace with metadata and frame labels.
class _ExceptionStackBlock extends StatelessWidget {
  const _ExceptionStackBlock({
    required this.exception,
    required this.colorScheme,
    required this.textTheme,
  });

  final SentryExceptionValue exception;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final st = exception.stacktrace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${exception.type}: ${exception.value}',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        if (exception.mechanism != null && exception.mechanism!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (exception.mechanism!['type'] != null)
                _Chip(
                  label: 'mechanism: ${exception.mechanism!['type']}',
                  color: colorScheme.surfaceContainerHighest,
                ),
              if (exception.mechanism!['handled'] != null)
                _Chip(
                  label: 'handled: ${exception.mechanism!['handled']}',
                  color: colorScheme.primaryContainer,
                ),
            ],
          ),
        ],
        if (st != null && st.frames.isNotEmpty) ...[
          if (st.framesOmitted == true || st.hasSystemFrames == true) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (st.framesOmitted == true) 'Some frames omitted',
                if (st.hasSystemFrames == true) 'Has system frames',
              ].join(' • '),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          _StackTraceView(
            frames: st.frames,
            stacktrace: st,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
      ],
    );
  }
}

/// Expandable Contexts section (User, Browser, Runtime, OS, etc.).
class _ContextsSection extends StatefulWidget {
  const _ContextsSection({
    required this.contexts,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, dynamic> contexts;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<_ContextsSection> createState() => _ContextsSectionState();
}

class _ContextsSectionState extends State<_ContextsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = widget.contexts.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 22,
                  color: widget.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.contexts,
                  style: widget.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          ...entries.map((e) {
            final key = e.key.toString();
            final val = e.value;
            if (val is! Map) return const SizedBox.shrink();
            final map = Map<String, dynamic>.from(val as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ContextCard(
                title: _contextTitle(key),
                data: map,
                colorScheme: widget.colorScheme,
                textTheme: widget.textTheme,
              ),
            );
          }),
        ],
      ],
    );
  }

  static String _contextTitle(String key) {
    final lower = key.toLowerCase();
    if (lower == 'user') return 'User';
    if (lower == 'browser') return 'Browser';
    if (lower == 'runtime') return 'Runtime';
    if (lower == 'os' || lower == 'operating system') return 'Operating System';
    if (lower.contains('client') && lower.contains('os')) return 'Client Operating System';
    if (lower == 'device') return 'Device';
    if (lower == 'trace') return 'Trace';
    return key.length > 1 ? '${key[0].toUpperCase()}${key.substring(1)}' : key;
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.title,
    required this.data,
    required this.colorScheme,
    required this.textTheme,
  });

  final String title;
  final Map<String, dynamic> data;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ..._formatMap(data).map((line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  static List<String> _formatMap(Map<dynamic, dynamic> map, {int indent = 0}) {
    final lines = <String>[];
    final prefix = '  ' * indent;
    for (final e in map.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (v is Map) {
        lines.add('$prefix$k:');
        lines.addAll(_formatMap(Map<dynamic, dynamic>.from(v), indent: indent + 1));
      } else {
        final str = v?.toString() ?? 'null';
        lines.add('$prefix$k: $str');
      }
    }
    return lines;
  }
}

/// Expandable Additional Data section with Formatted/Raw toggle.
class _AdditionalDataSection extends StatefulWidget {
  const _AdditionalDataSection({
    required this.extra,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, dynamic> extra;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<_AdditionalDataSection> createState() => _AdditionalDataSectionState();
}

class _AdditionalDataSectionState extends State<_AdditionalDataSection> {
  bool _expanded = true;
  bool _formatted = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = widget.colorScheme;
    final textTheme = widget.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 22,
                      color: colorScheme.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.additionalData,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (_expanded) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(l10n.formatted)),
                  ButtonSegment(value: false, label: Text(l10n.raw)),
                ],
                selected: {_formatted},
                onSelectionChanged: (s) => setState(() => _formatted = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                ),
              ),
            ],
          ],
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: _formatted
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.extra.entries.map((e) {
                      final val = e.value?.toString() ?? 'null';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                e.key,
                                style: textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                val,
                                style: textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : SelectableText(
                    _toRawJson(widget.extra),
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  String _toRawJson(Map<String, dynamic> map) {
    final buf = StringBuffer();
    buf.writeln('{');
    for (final e in map.entries) {
      final v = e.value;
      final str = v is String ? '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"' : (v?.toString() ?? 'null');
      buf.writeln('  "${e.key}": $str,');
    }
    final s = buf.toString();
    if (s.endsWith(',\n')) return '${s.substring(0, s.length - 2)}\n}';
    return '$s}';
  }
}

/// Initial number of stack frames shown before "Show N more frames".
const int _kInitialVisibleFrames = 8;

class _StackTraceView extends StatefulWidget {
  const _StackTraceView({
    required this.frames,
    required this.colorScheme,
    required this.textTheme,
    this.stacktrace,
  });

  final List<SentryFrame> frames;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final SentryStacktrace? stacktrace;

  @override
  State<_StackTraceView> createState() => _StackTraceViewState();
}

class _StackTraceViewState extends State<_StackTraceView> {
  int _visibleCount = _kInitialVisibleFrames;
  final Set<int> _expandedFrames = {};

  @override
  Widget build(BuildContext context) {
    // Latest first: first frame = crash frame (innermost), last = outermost
    final ordered = List<SentryFrame>.from(widget.frames);
    final total = ordered.length;
    final showMoreCount = total - _visibleCount;
    final visibleFrames = ordered.take(_visibleCount).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < visibleFrames.length; i++) ...[
            _FrameTile(
              frame: visibleFrames[i],
              frameIndex: i,
              totalVisible: visibleFrames.length,
              colorScheme: widget.colorScheme,
              textTheme: widget.textTheme,
              expanded: _expandedFrames.contains(i),
              onTap: () {
                setState(() {
                  if (_expandedFrames.contains(i)) {
                    _expandedFrames.remove(i);
                  } else {
                    _expandedFrames.add(i);
                  }
                });
              },
            ),
            if (i < visibleFrames.length - 1) const Divider(height: 1),
          ],
          if (showMoreCount > 0)
            InkWell(
              onTap: () => setState(() => _visibleCount = total),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.expand_more,
                      size: 20,
                      color: widget.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).showMoreFrames(showMoreCount),
                      style: widget.textTheme.bodyMedium?.copyWith(
                        color: widget.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.frameIndex,
    required this.totalVisible,
    required this.colorScheme,
    required this.textTheme,
    required this.expanded,
    required this.onTap,
  });

  final SentryFrame frame;
  final int frameIndex;
  final int totalVisible;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = frame.filename ?? frame.absPath ?? '?';
    final line = frame.lineNo != null ? ':${frame.lineNo}' : '';
    final fn = frame.function ?? '';
    final hasContext = (frame.context != null && frame.context!.isNotEmpty) ||
        (frame.vars != null && frame.vars!.isNotEmpty);
    // First frame and not in-app = "Crashed in non-app"; other non-app = "Called from"
    final prefixLabel = frame.inApp
        ? null
        : (frameIndex == 0 ? 'Crashed in non-app: ' : 'Called from: ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: hasContext ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasContext)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                if (hasContext) const SizedBox(width: 4),
                if (frame.inApp)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'In App',
                      style: textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (prefixLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            prefixLabel,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      if (fn.isNotEmpty)
                        Text(
                          fn,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      Text(
                        '$file$line',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (frame.module != null && frame.module!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'module: ${frame.module}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          if (frame.context != null && frame.context!.isNotEmpty) ...[
            const SizedBox(height: 4),
            _FrameCodeContext(
              codeLines: frame.context!,
              colorScheme: colorScheme,
              textTheme: textTheme,
              highlightLine: frame.lineNo,
            ),
          ],
          if (frame.vars != null && frame.vars!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FrameVars(vars: frame.vars!, colorScheme: colorScheme, textTheme: textTheme),
          ],
        ],
      ],
    );
  }
}

/// Local variables for a stack frame.
class _FrameVars extends StatelessWidget {
  const _FrameVars({
    required this.vars,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, dynamic> vars;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 28),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Variables',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ...vars.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        e.key,
                        style: textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        e.value?.toString() ?? 'null',
                        style: textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _FrameCodeContext extends StatelessWidget {
  const _FrameCodeContext({
    required this.codeLines,
    required this.colorScheme,
    required this.textTheme,
    this.highlightLine,
  });

  final List<List<dynamic>> codeLines;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final int? highlightLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 28),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: codeLines.map((row) {
          if (row.length < 2) return const SizedBox.shrink();
          final lineNum = row[0] is int ? row[0] as int : (row[0] is num ? (row[0] as num).toInt() : null);
          final code = row[1]?.toString() ?? '';
          final isHighlight = lineNum != null && highlightLine != null && lineNum == highlightLine;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    lineNum?.toString() ?? '',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    code,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      backgroundColor: isHighlight ? colorScheme.errorContainer.withValues(alpha: 0.5) : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Initial number of breadcrumb entries shown before "View N more".
const int _kInitialVisibleBreadcrumbs = 8;

class _BreadcrumbsView extends StatefulWidget {
  const _BreadcrumbsView({required this.values, required this.colorScheme, required this.textTheme});

  final List<dynamic> values;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<_BreadcrumbsView> createState() => _BreadcrumbsViewState();
}

class _BreadcrumbsViewState extends State<_BreadcrumbsView> {
  int _visibleCount = _kInitialVisibleBreadcrumbs;
  final Set<int> _expandedIndices = {};

  static String _formatTs(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.hour}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.values.length;
    final showMoreCount = total - _visibleCount;
    final visibleValues = widget.values.take(_visibleCount).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < visibleValues.length; i++) ...[
            _BreadcrumbTile(
              index: i,
              map: visibleValues[i] is Map ? Map<String, dynamic>.from(visibleValues[i] as Map) : <String, dynamic>{},
              colorScheme: widget.colorScheme,
              textTheme: widget.textTheme,
              expanded: _expandedIndices.contains(i),
              onTap: () {
                setState(() {
                  if (_expandedIndices.contains(i)) {
                    _expandedIndices.remove(i);
                  } else {
                    _expandedIndices.add(i);
                  }
                });
              },
              formatTs: _formatTs,
            ),
            if (i < visibleValues.length - 1) const Divider(height: 1),
          ],
          if (showMoreCount > 0)
            InkWell(
              onTap: () => setState(() => _visibleCount = total),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.expand_more, size: 20, color: widget.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).viewMoreBreadcrumbs(showMoreCount),
                      style: widget.textTheme.bodyMedium?.copyWith(
                        color: widget.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreadcrumbTile extends StatelessWidget {
  const _BreadcrumbTile({
    required this.index,
    required this.map,
    required this.colorScheme,
    required this.textTheme,
    required this.expanded,
    required this.onTap,
    required this.formatTs,
  });

  final int index;
  final Map<String, dynamic> map;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool expanded;
  final VoidCallback onTap;
  final String Function(String) formatTs;

  @override
  Widget build(BuildContext context) {
    final category = map['category']?.toString() ?? '';
    final message = map['message']?.toString() ?? '';
    final type = map['type']?.toString() ?? '';
    final ts = map['timestamp']?.toString() ?? '';
    final data = map['data'];
    final hasDetail = (data != null && data is Map && (data as Map).isNotEmpty) || message.isNotEmpty;

    final title = category.isNotEmpty || type.isNotEmpty
        ? '$category${type.isNotEmpty ? ' · $type' : ''}'
        : (message.isNotEmpty ? message : 'Event');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: hasDetail ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasDetail)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                if (hasDetail) const SizedBox(width: 4),
                SizedBox(
                  width: 72,
                  child: Text(
                    ts.isNotEmpty ? formatTs(ts) : '',
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.length > 80 ? '${title.substring(0, 80)}…' : title,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded && hasDetail) ...[
          const SizedBox(height: 4),
          _BreadcrumbDetail(data: data, message: message, colorScheme: colorScheme, textTheme: textTheme),
        ],
      ],
    );
  }
}

class _BreadcrumbDetail extends StatelessWidget {
  const _BreadcrumbDetail({
    required this.data,
    required this.message,
    required this.colorScheme,
    required this.textTheme,
  });

  final dynamic data;
  final String message;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 28),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(message, style: textTheme.bodySmall),
            ),
          if (data != null && data is Map && (data as Map).isNotEmpty)
            ..._formatMap(data as Map).map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  static List<String> _formatMap(Map<dynamic, dynamic> map, {int indent = 0}) {
    final lines = <String>[];
    final prefix = '  ' * indent;
    for (final e in map.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (v is Map) {
        lines.add('$prefix$k:');
        lines.addAll(_formatMap(Map<dynamic, dynamic>.from(v), indent: indent + 1));
      } else {
        final str = v?.toString() ?? 'null';
        lines.add('$prefix$k: $str');
      }
    }
    return lines;
  }
}
