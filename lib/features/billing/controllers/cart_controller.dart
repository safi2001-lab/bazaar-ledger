import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  final int itemId;
  final String name;
  final String? barcode;
  final String unit;
  final double unitPrice;
  final double quantity;
  final double taxRate; // e.g. 18.0%
  final double discountAmount;
  final String? batchNumber;
  final String? serialImei;

  CartItem({
    required this.itemId,
    required this.name,
    this.barcode,
    required this.unit,
    required this.unitPrice,
    required this.quantity,
    this.taxRate = 18.0,
    this.discountAmount = 0.0,
    this.batchNumber,
    this.serialImei,
  });

  double get taxableAmount => (unitPrice * quantity) - discountAmount;
  double get taxAmount => taxableAmount * (taxRate / 100.0);
  double get lineTotal => taxableAmount + taxAmount;

  CartItem copyWith({
    int? itemId,
    String? name,
    String? barcode,
    String? unit,
    double? unitPrice,
    double? quantity,
    double? taxRate,
    double? discountAmount,
    String? batchNumber,
    String? serialImei,
  }) {
    return CartItem(
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      taxRate: taxRate ?? this.taxRate,
      discountAmount: discountAmount ?? this.discountAmount,
      batchNumber: batchNumber ?? this.batchNumber,
      serialImei: serialImei ?? this.serialImei,
    );
  }
}

class CartState {
  final List<CartItem> items;
  final int? selectedPartyId;
  final String paymentMode; // 'Cash', 'Raast', 'JazzCash', 'EasyPaisa', 'Credit'
  final double overallDiscount;
  final double roundOff;

  const CartState({
    this.items = const [],
    this.selectedPartyId,
    this.paymentMode = 'Cash',
    this.overallDiscount = 0.0,
    this.roundOff = 0.0,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get totalLineDiscounts => items.fold(0.0, (sum, item) => sum + item.discountAmount);
  double get totalTaxAmount => items.fold(0.0, (sum, item) => sum + item.taxAmount);
  double get grossTotal => subtotal - totalLineDiscounts + totalTaxAmount - overallDiscount;
  double get grandTotal => grossTotal + roundOff;
  int get totalItemCount => items.length;
  double get totalQuantity => items.fold(0.0, (sum, item) => sum + item.quantity);

  CartState copyWith({
    List<CartItem>? items,
    int? selectedPartyId,
    String? paymentMode,
    double? overallDiscount,
    double? roundOff,
  }) {
    return CartState(
      items: items ?? this.items,
      selectedPartyId: selectedPartyId ?? this.selectedPartyId,
      paymentMode: paymentMode ?? this.paymentMode,
      overallDiscount: overallDiscount ?? this.overallDiscount,
      roundOff: roundOff ?? this.roundOff,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void addItem(CartItem item) {
    final existingIndex = state.items.indexWhere(
      (i) => i.itemId == item.itemId && i.batchNumber == item.batchNumber && i.serialImei == item.serialImei,
    );

    if (existingIndex >= 0) {
      final updatedList = List<CartItem>.from(state.items);
      final current = updatedList[existingIndex];
      updatedList[existingIndex] = current.copyWith(quantity: current.quantity + item.quantity);
      state = state.copyWith(items: updatedList);
    } else {
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  void updateQuantity(int index, double newQuantity) {
    if (index < 0 || index >= state.items.length) return;
    final updatedList = List<CartItem>.from(state.items);
    if (newQuantity <= 0) {
      updatedList.removeAt(index);
    } else {
      updatedList[index] = updatedList[index].copyWith(quantity: newQuantity);
    }
    state = state.copyWith(items: updatedList);
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.items.length) return;
    final updatedList = List<CartItem>.from(state.items)..removeAt(index);
    state = state.copyWith(items: updatedList);
  }

  void setPaymentMode(String mode) {
    state = state.copyWith(paymentMode: mode);
  }

  void setSelectedParty(int? partyId) {
    state = state.copyWith(selectedPartyId: partyId);
  }

  void setOverallDiscount(double discount) {
    state = state.copyWith(overallDiscount: discount);
  }

  void clearCart() {
    state = const CartState();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
