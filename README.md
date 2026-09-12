# v52-onchain

Contratos de Vector52 para HSK y Avalanche. **Scaffold documental; implementación pendiente.**

## HSK

`V52EvidenceRegistry` ancla únicamente el hash del manifest, versión, case ID no sensible y emisor. Nunca almacena el expediente completo ni datos personales.

## Avalanche

Contratos o adapters estrictamente necesarios para demostrar settlement x402 y, si aporta al flujo real, un registro mínimo de capacidades del servicio.

## Definition of Done

- direcciones y chain IDs publicados;
- contratos verificados en explorador;
- tests y scripts reproducibles;
- ABIs versionadas;
- ninguna llave privada en el repositorio;
- transacciones reales enlazadas desde el README.
