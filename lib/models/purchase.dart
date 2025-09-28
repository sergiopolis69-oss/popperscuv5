class PurchaseItem {
  final int productId;
  final int quantity;
  final double unitCost;

  PurchaseItem({required this.productId, required this.quantity, required this.unitCost});

  Map<String, dynamic> toMap(int purchaseId) => {
    'purchase_id': purchaseId,
    'product_id': productId,
    'quantity': quantity,
    'unit_cost': unitCost,
  };
}

class Purchase {
  final int? id;
  final String folio;
  final int supplierId;
  final DateTime date;
  final List<PurchaseItem> items;

  Purchase({
    this.id,
    required this.folio,
    required this.supplierId,
    required this.date,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'folio': folio,
    'supplier_id': supplierId,
    'date': date.toIso8601String(),
  };
}
