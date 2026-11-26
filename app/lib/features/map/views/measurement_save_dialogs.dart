part of 'measurement_save_view.dart';

/// Centered dialog picker with search, list rows and a cancel
/// link — same pattern as the reference app.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.source});

  final String title;

  /// Invoked on open and on retry — a failed load never stays
  /// stale, and nothing is fetched until the dialog opens.
  final Future<List<PickerItem>> Function() source;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';
  late Future<List<PickerItem>> _future = widget.source();

  void _retry() => setState(() {
    _future = widget.source();
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'เลือก${widget.title}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาด้วย รหัส หรือ ชื่อ ได้ที่นี่',
                  hintStyle: const TextStyle(fontSize: 17),
                  prefixIcon: const Icon(Iconsax.search_normal),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<PickerItem>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _SheetError(onRetry: _retry);
                    }
                    final items = fuzzySearch(
                      snap.data ?? const <PickerItem>[],
                      _q,
                      (i) => '${i.name} ${i.code}',
                    );
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'ยังไม่มีข้อมูล',
                          style: TextStyle(fontSize: 17),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Iconsax.user),
                            ),
                            title: Text(
                              'ชื่อ: ${it.name}',
                              style: const TextStyle(fontSize: 18),
                            ),
                            subtitle: Text(
                              'รหัส: ${it.code}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            onTap: () => Navigator.pop(context, it),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Backend loss-option that means "no cause" — exclusive inside
/// [_MultiPickerSheet] and skips the loss-area field requirement.
const _noneName = 'ไม่มี';

/// Checkbox variant of [_PickerSheet] — returns the whole selected
/// set on ตกลง. 'ไม่มี' is exclusive: picking it clears the rest,
/// and picking anything else un-picks it.
class _MultiPickerSheet extends StatefulWidget {
  const _MultiPickerSheet({
    required this.title,
    required this.source,
    required this.initial,
  });

  final String title;
  final Future<List<PickerItem>> Function() source;
  final Set<String> initial;

  @override
  State<_MultiPickerSheet> createState() => _MultiPickerSheetState();
}

class _MultiPickerSheetState extends State<_MultiPickerSheet> {
  String _q = '';
  List<PickerItem> _items = const [];
  // Selection keyed by code, not name — two options sharing a
  // display name don't collide. Initial names resolve once items
  // load; names no longer in the list stay in [_extra] so a
  // restored draft doesn't silently drop a removed option.
  Set<String>? _selected;
  final Set<String> _extra = {};
  late Future<List<PickerItem>> _future = widget.source();

  void _retry() => setState(() {
    _future = widget.source();
  });

  void _init(List<PickerItem> items) {
    if (_selected != null) return;
    _items = items;
    _selected = {
      for (final it in items)
        if (widget.initial.contains(it.name)) it.code,
    };
    _extra.addAll(widget.initial.difference({for (final it in items) it.name}));
  }

  void _toggle(PickerItem it, bool on) {
    setState(() {
      final sel = _selected!;
      if (it.name == _noneName) {
        sel.clear();
        _extra.clear();
        if (on) sel.add(it.code);
      } else {
        for (final n in _items) {
          if (n.name == _noneName) sel.remove(n.code);
        }
        _extra.remove(_noneName);
        on ? sel.add(it.code) : sel.remove(it.code);
      }
    });
  }

  Set<String> _pickedNames() => {
    ..._extra,
    for (final it in _items)
      if (_selected!.contains(it.code)) it.name,
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'เลือก${widget.title}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาได้ที่นี่',
                  hintStyle: const TextStyle(fontSize: 17),
                  prefixIcon: const Icon(Iconsax.search_normal),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<PickerItem>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _SheetError(onRetry: _retry);
                    }
                    _init(snap.data ?? const <PickerItem>[]);
                    final items = fuzzySearch(
                      snap.data ?? const <PickerItem>[],
                      _q,
                      (i) => '${i.name} ${i.code}',
                    );
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'ยังไม่มีข้อมูล',
                          style: TextStyle(fontSize: 17),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        return Card(
                          child: CheckboxListTile(
                            value: _selected!.contains(it.code),
                            onChanged: (v) => _toggle(it, v ?? false),
                            title: Text(
                              it.name,
                              style: const TextStyle(fontSize: 18),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _selected == null ? widget.initial : _pickedNames(),
                    ),
                    child: const Text('ตกลง', style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown inside picker dialogs when the fetch throws — gives a
/// retry instead of silently looking like "no data".
class _SheetError extends StatelessWidget {
  const _SheetError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.warning_2, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          const Text('โหลดข้อมูลไม่สำเร็จ', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}
