import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import '../../core/utils/validators.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/recurring_transaction.dart';
import '../../data/services/recurring_service.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/state_views.dart';

/// Crear o editar una regla recurrente.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.recurringId});

  final String? recurringId;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  TxType _type = TxType.expense;
  String? _categoryId;
  PaymentMethod _method = PaymentMethod.cash;
  Frequency _frequency = Frequency.monthly;
  DateTime _date = Dates.today();
  DateTime? _endDate;
  RecurringStatus _status = RecurringStatus.active;
  RecurringTransaction? _original;
  bool _loading = false;
  bool _saving = false;
  Object? _error;

  bool get _isEditing => widget.recurringId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
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
      final r = await ref.read(recurringRepositoryProvider).getById(widget.recurringId!);
      if (r == null || r.deletedAt != null) throw const AppException('El recurrente no existe.');
      _original = r;
      _type = r.type;
      _categoryId = r.categoryId;
      _method = r.paymentMethod;
      _frequency = r.frequency;
      _date = r.nextDate;
      _endDate = r.endDate;
      _status = r.status;
      _amount.text = r.amount.toDecimalString();
      _description.text = r.description ?? '';
    } catch (e) {
      _error = e;
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      showInfoSnack(context, 'Selecciona una categoría.');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final service = ref.read(recurringServiceProvider);
    try {
      final amount = Money.parse(_amount.text);
      final description = _description.text.trim();
      if (_original != null) {
        final o = _original!;
        final frequencyChanged = o.frequency != _frequency;
        await service.update(o.copyWith(
          type: _type,
          amount: amount,
          categoryId: _categoryId,
          description: description,
          paymentMethod: _method,
          frequency: _frequency,
          // Si cambia la frecuencia o la fecha, la nueva fecha se toma como ancla.
          startDate: frequencyChanged || _date != o.nextDate ? _date : o.startDate,
          nextDate: _date,
          endDate: _endDate,
          clearEndDate: _endDate == null,
          status: _status == RecurringStatus.finished && (_endDate == null || !_endDate!.isBefore(_date))
              ? RecurringStatus.active
              : _status,
        ));
        await service.processDue(user);
      } else {
        await service.create(
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
        );
      }
      if (!mounted) return;
      showInfoSnack(context, _isEditing ? 'Recurrente actualizado' : 'Recurrente creado');
      context.pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Editar recurrente' : 'Nuevo recurrente';
    if (_loading) return Scaffold(appBar: AppBar(title: Text(title)), body: const LoadingView());
    if (_error != null) return Scaffold(appBar: AppBar(title: Text(title)), body: ErrorView(error: _error!));

    final categories =
        (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[]).where((c) => c.type == _type).toList();
    final preview = Recurrence.next(_date, _frequency, anchorDay: _date.day);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Egreso')),
                ButtonSegment(value: TxType.income, label: Text('Ingreso')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 20),
            AmountField(controller: _amount, validator: Validators.amount),
            const SizedBox(height: 20),
            Text('Categoría', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: categories,
              selectedId: _categoryId,
              onSelected: (c) => setState(() => _categoryId = c.id),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<Frequency>(
              value: _frequency,
              decoration: const InputDecoration(labelText: 'Frecuencia', prefixIcon: Icon(Icons.event_repeat)),
              items: [for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
              onChanged: (f) => setState(() => _frequency = f ?? _frequency),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(_isEditing ? 'Próxima fecha' : 'Primera fecha'),
              subtitle: Text('${Dates.formatLong(_date)}\nLuego: ${Dates.formatShort(preview)}'),
              isThreeLine: true,
              onTap: () => _pickDate(),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Fecha de fin (opcional)'),
              subtitle: Text(_endDate == null ? 'Sin fecha de fin' : Dates.formatLong(_endDate!)),
              trailing: _endDate == null
                  ? null
                  : IconButton(
                      tooltip: 'Quitar fecha de fin',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _endDate = null),
                    ),
              onTap: () => _pickDate(end: true),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PaymentMethod>(
              value: _method,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Método de pago', prefixIcon: Icon(Icons.wallet)),
              items: [for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)', prefixIcon: Icon(Icons.notes)),
              validator: Validators.description,
            ),
            if (_isEditing && _status != RecurringStatus.finished)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                subtitle: const Text('Desactívalo para pausar la generación automática'),
                value: _status == RecurringStatus.active,
                onChanged: (v) => setState(() => _status = v ? RecurringStatus.active : RecurringStatus.paused),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_isEditing ? 'Guardar cambios' : 'Crear recurrente'),
            ),
          ]),
        ),
      ),
    );
  }
}
