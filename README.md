# PDV Flutter

Punto de venta simple en Flutter con:
- Ventas (cliente, forma de pago, envío, descuento, productos con live search o SKU)
- Historial de ventas
- Clientes (top clientes y alta rápida)
- Utilidad promedio ponderada por periodo
- Inventario (existencias, alta/baja)
- Compras (folio → proveedor live search → productos live/SKU → totales → guarda y suma inventario)
- XML por catálogo: clientes, productos, proveedores, ventas, compras

## Compilación
Usa el workflow `.github/workflows/android-build.yml` o en local:
```
flutter pub get
flutter build apk --release
```
