import 'package:flutter/material.dart';

class OrderSearchField extends StatefulWidget {
  const OrderSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.labelText = 'Search table or order number',
  });

  final String query;
  final ValueChanged<String> onChanged;
  final String labelText;

  @override
  State<OrderSearchField> createState() => _OrderSearchFieldState();
}

class _OrderSearchFieldState extends State<OrderSearchField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant OrderSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != controller.text) {
      controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: widget.labelText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  widget.onChanged('');
                },
                icon: const Icon(Icons.clear),
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}
