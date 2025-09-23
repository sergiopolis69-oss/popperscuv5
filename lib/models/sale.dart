
class Sale {
  final int? id;
  final String customerPhone;
  final String paymentMethod;
  final String datetime;
  final String place;
  final double shippingCost;
  final double discount; // descuento total de la venta

  Sale({
    this.id,
    required this.customerPhone,
    required this.paymentMethod,
    required this.datetime,
    required this.place,
    required this.shippingCost,
    required this.discount,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'customerPhone': customerPhone,
    'paymentMethod': paymentMethod,
    'datetime': datetime,
    'place': place,
    'shippingCost': shippingCost,
    'discount': discount,
  };

  factory Sale.fromMap(Map<String, Object?> map) => Sale(
    id: map['id'] as int?,
    customerPhone: map['customerPhone'] as String,
    paymentMethod: map['paymentMethod'] as String,
    datetime: map['datetime'] as String,
    place: map['place'] as String,
    shippingCost: (map['shippingCost'] as num).toDouble(),
    discount: (map['discount'] as num).toDouble(),
  );
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final int quantity;
  final double unitPrice; // precio de venta unitario al momento

  SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'saleId': saleId,
    'productId': productId,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  factory SaleItem.fromMap(Map<String, Object?> map) => SaleItem(
    id: map['id'] as int?,
    saleId: (map['saleId'] as num).toInt(),
    productId: (map['productId'] as num).toInt(),
    quantity: (map['quantity'] as num).toInt(),
    unitPrice: (map['unitPrice'] as num).toDouble(),
  );
}
