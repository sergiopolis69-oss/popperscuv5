class SaleItem {
  final int productId;
  final int quantity;
  final double unitPrice;

  SaleItem({required this.productId, required this.quantity, required this.unitPrice});

  Map<String, dynamic> toMap(int saleId) => {
    'sale_id': saleId,
    'product_id': productId,
    'quantity': quantity,
    'unit_price': unitPrice,
  };
}

class Sale {
  final int? id;
  final String? customerPhone;
  final String paymentMethod;
  final String place;
  final double shippingCost;
  final double discount;
  final DateTime date;
  final List<SaleItem> items;

  Sale({
    this.id,
    required this.customerPhone,
    required this.paymentMethod,
    required this.place,
    required this.shippingCost,
    required this.discount,
    required this.date,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_phone': customerPhone,
    'payment_method': paymentMethod,
    'place': place,
    'shipping_cost': shippingCost,
    'discount': discount,
    'date': date.toIso8601String(),
  };
}
