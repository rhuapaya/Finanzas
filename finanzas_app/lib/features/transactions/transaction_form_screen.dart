import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/validators.dart';
import '../../data/io/receipt_storage.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/fin_transaction.dart';
import '../../data/services/recurring_service.dart';
import '../../data/services/transaction_service.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/receipt_image.dart';
import '../../shared/widgets/state_views.dart';

/// Crear o editar un movimiento.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.transactionId, this.initialType = TxType.expense});

  final String? transactionId;
  final TxType initialType;

  bool get isEditing => transactionId != null;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _receipts = ReceiptStorage();

  late TxType _type = widget.initialType;
  String? _categoryId;
  DateTime _date = Dates.today();
  PaymentMethod _method = PaymentMethod.cash;
  String? _receiptLocal;
  String? _receiptRemote;
  bool _recurring = false;
  Frequency _frequency = Frequency.monthly;
  DateTime? _endDate;

  FinTransaction? _original;
  bool _loading = false;
  bool _saving = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await ref.read(transactionRepositoryProvider).getById(widget.transactionId!);
      if (t == null || t.deletedAt != null) throw const AppException('El movimiento no existe.');
      _original = t;
      _type = t.type;
      _categoryId = t.categoryId;
      _date = t.date;
      _method = t.paymentMethod;
      _receiptLocal = t.receiptLocalPath;
      _receiptRemote = t.receiptRemotePath;
      _amount.text = t.amount.toDecimalString();
      _description.text = t.description ?? '';
    } catch (e) {
      _loadError = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({bool end = false}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? _date) : _date,
      firstDate: end ? _date : DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: end ? 'Fecha de fin' : 'Fecha del movimiento',
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endDate = picked;
      } else {
        _date = picked;
        if (_endDate != null && _endDate!.isBefore(_date)) _endDate = null;
      }
    });
  }

  Future<void> _pickReceipt() async {
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ]),
      ),
    );
    if (fromCamera == null) return;
    try {
      final path = await _receipts.pick(fromCamera: fromCamera);
      if (path == null) return;
      // Borra una foto nueva anterior que aún no se guardó.
      if (_receiptLocal != null && _receiptLocal != _original?.receiptLocalPath) {
        await ReceiptStorage.deleteIfExists(_receiptLocal);
      }
      setState(() {
        _receiptLocal = path;
        _receiptRemote = null;
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _removeReceipt() {
    if (_receiptLocal != null && _receiptLocal != _original?.receiptLocalPath) {
      ReceiptStorage.deleteIfExists(_receiptLocal);
    }
    setState(() {
      _receiptLocal = null;
      _receiptRemote = null;
    });
  }

  Future<void> _createCategory() async {
    final created = await context.push<Category>('/categories/new?type=${_type.code}');
    if (created != null && mounted) setState(() => _categoryId = created.id);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      showInfoSnack(context, 'Selecciona una categoría.');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final amount = Money.parse(_amount.text);
      final description = _description.text;
      List<String> alerts;
      String message;

      if (widget.isEditing) {
        final draft = TransactionDraft(
          type: _type,
          amount: amount,
          categoryId: _categoryId!,
          date: _date,
          description: description,
          paymentMethod: _method,
          receiptLocalPath: _receiptLocal,
        );
        final result = await ref.read(transactionServiceProvider).update(user, _original!, draft);
        alerts = result.alerts;
        message = 'Movimiento actualizado';
      } else if (_recurring) {
        final (_, ruleAlerts) = await ref.read(recurringServiceProvider).create(
              user,
              RecurringDraft(
                type: _type,
                amount: amount,
                categoryId: _categoryId!,
                frequency: _frequency,
                startDate: _date,
                endDate: _endDate,
                description: description,
                paymentMethod: _method,
              ),
              firstReceiptPath: _receiptLocal,
            );
        alerts = ruleAlerts;
        message = _date.isAfter(Dates.today())
            ? 'Movimiento recurrente programado desde el ${Dates.formatShort(_date)}'
            : 'Movimiento recurrente creado';
      } else {
        final draft = TransactionDraft(
          type: _type,
          amount: amount,
          categoryId: _categoryId!,
          date: _date,
          description: description,
          paymentMethod: _method,
          receiptLocalPath: _receiptLocal,
        );
        final result = await ref.read(transactionServiceProvider).create(user, draft);
        alerts = result.alerts;
        message = _type == TxType.income ? 'Ingreso registrado' : 'Egreso registrado';
      }

      if (!mounted) return;
      showInfoSnack(
        context,
        alerts.isEmpty ? message : '$message\n${alerts.join('\n')}',
        duration: Duration(seconds: alerts.isEmpty ? 3 : 7),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final original = _original;
    final user = ref.read(currentUserProvider);
    if (original == null || user == null) return;
    final ok = await confirmAction(
      context,
      title: 'Eliminar movimiento',
      message: '¿Seguro que deseas eliminar este movimiento? Esta acción no se puede deshacer.',
    );
    if (!ok) return;
    try {
      await ref.read(transactionServiceProvider).delete(user, original);
      if (!mounted) return;
      showInfoSnack(context, 'Movimiento eliminado');
      context.pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _viewReceipt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: Center(child: ReceiptImage(localPath: _receiptLocal, remotePath: _receiptRemote, height: 600)),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton.filledTonal(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Editar movimiento' : 'Nuevo movimiento';
    if (_loading) return Scaffold(appBar: AppBar(title: Text(title)), body: const LoadingView());
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: ErrorView(error: _loadError!));
    }

    final scheme = Theme.of(context).colorScheme;
    final allCategories = ref.watch(categoriesProvider);
    final categories = (allCategories.valueOrNull ?? const <Category>[]).where((c) => c.type == _type).toList();
    final hasReceipt = _receiptLocal != null || _receiptRemote != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SegmentedButton<TxType>(
                key: const Key('tx_type'),
                segments: [
                  ButtonSegment(
                    value: TxType.expense,
                    icon: Icon(Icons.arrow_upward, color: scheme.expense),
                    label: const Text('Egreso'),
                  ),
                  ButtonSegment(
                    value: TxType.income,
                    icon: Icon(Icons.arrow_downward, color: scheme.income),
                    label: const Text('Ingreso'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 20),
              AmountField(
                fieldKey: const Key('tx_amount'),
                controller: _amount,
                autofocus: !widget.isEditing,
                validator: Validators.amount,
              ),
              const SizedBox(height: 20),
              Text('Categoría', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              allCategories.isLoading
                  ? const LinearProgressIndicator()
                  : CategoryPicker(
                      categories: categories,
                      selectedId: _categoryId,
                      onSelected: (c) => setState(() => _categoryId = c.id),
                      onAddCategory: _createCategory,
                    ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(_recurring ? 'Primera fecha' : 'Fecha'),
                subtitle: Text(Dates.formatLong(_date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () => _pickDate(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PaymentMethod>(
                value: _method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Método de pago', prefixIcon: Icon(Icons.wallet)),
                items: [
                  for (final m in PaymentMethod.values)
                    DropdownMenuItem(
                      value: m,
                      child: Row(children: [Icon(m.icon, size: 20), const SizedBox(width: 10), Text(m.label)]),
                    ),
                ],
                onChanged: (m) => setState(() => _method = m ?? _method),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('tx_description'),
                controller: _description,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  prefixIcon: Icon(Icons.notes),
                ),
                validator: Validators.description,
              ),
              const SizedBox(height: 8),
              Text('Comprobante (opcional)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (hasReceipt)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(children: [
                    GestureDetector(
                      onTap: _viewReceipt,
                      child: ReceiptImage(localPath: _receiptLocal, remotePath: _receiptRemote),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(children: [
                        IconButton.filledTonal(
                          tooltip: 'Cambiar foto',
                          onPressed: _pickReceipt,
                          icon: const Icon(Icons.edit),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Quitar foto',
                          onPressed: _removeReceipt,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                    ),
                  ]),
                )
              else
                OutlinedButton.icon(
                  onPressed: _pickReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Adjuntar foto del comprobante'),
                ),
              if (!widget.isEditing) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.repeat),
                  title: const Text('Movimiento recurrente'),
                  subtitle: const Text('Se registrará automáticamente según la frecuencia'),
                  value: _recurring,
                  onChanged: (v) => setState(() => _recurring = v),
                ),
                if (_recurring) ...[
                  DropdownButtonFormField<Frequency>(
                    value: _frequency,
                    decoration: const InputDecoration(labelText: 'Frecuencia', prefixIcon: Icon(Icons.event_repeat)),
                    items: [
                      for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (f) => setState(() => _frequency = f ?? _frequency),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_busy_outlined),
                    title: const Text('Fecha de fin (opcional)'),
                    subtitle: Text(_endDate == null ? 'Sin fecha de fin' : Dates.formatLong(_endDate!)),
                    trailing: _endDate == null
                        ? const Icon(Icons.edit_calendar_outlined)
                        : IconButton(
                            tooltip: 'Quitar fecha de fin',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _endDate = null),
                          ),
                    onTap: () => _pickDate(end: true),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('tx_save'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(widget.isEditing ? 'Guardar cambios' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
