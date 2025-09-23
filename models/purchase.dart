
class Purchase {
  final int? id;
  final String date;
  final String supplier;
  final String note;

  Purchase({this.id, required this.date, required this.supplier, this.note = ''});

  Map<String, Object?> toMap() => {
    'id': id,
    'date': date,
    'supplier': supplier,
    'note': note,
  };

  factory Purchase.fromMap(Map<String, Object?> map) => Purchase(
    id: map['id'] as int?,
    date: map['date'] as String,
    supplier: map['supplier'] as String,
    note: (map['note'] as String?) ?? '',
  );
}

class PurchaseItem {
  final int? id;
  final int purchaseId;
  final int productId;
  final int quantity;
  final double unitCost;

  PurchaseItem({
    this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'purchaseId': purchaseId,
    'productId': productId,
    'quantity': quantity,
    'unitCost': unitCost,
  };

  factory PurchaseItem.fromMap(Map<String, Object?> map) => PurchaseItem(
    id: map['id'] as int?,
    purchaseId: (map['purchaseId'] as num).toInt(),
    productId: (map['productId'] as num).toInt(),
    quantity: (map['quantity'] as num).toInt(),
    unitCost: (map['unitCost'] as num).toDouble(),
  );
}
