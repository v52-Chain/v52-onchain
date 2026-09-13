# v52-onchain

Contratos de Vector52 para HSK y Avalanche.

**Estado:** `V52EvidenceRegistry` (HSK) implementado, testeado exhaustivamente
con Foundry y desplegado/verificado funcionalmente en HSK Testnet. Los
contratos de Avalanche (`V52ServiceRegistry` / x402 settlement) siguen
pendientes — ver [`docs/PROYECTO-FINAL.md`](../docs/PROYECTO-FINAL.md)
sección 7.2 para el estado real de esa integración.

---

## HSK — `V52EvidenceRegistry`

Ancla **únicamente** el compromiso criptográfico de un expediente `.v52` de
Vector52. Nunca almacena el expediente completo, evidencia cruda, wallets
investigadas, el texto del claim ni el veredicto.

### Qué prueba este contrato

- Que un `manifest_root` (SHA-256 de `manifest.json`) específico existió y
  fue registrado por una dirección `issuer` autorizada, en un bloque y
  timestamp determinados.
- Procedencia: si un `manifest_root` fue reemplazado (`supersedes`), la
  cadena de versiones queda enlazada y consultable on-chain.
- Autoría: qué direcciones estuvieron autorizadas a anclar en cada momento
  (eventos `IssuerUpdated`), para poder distinguir un anchor legítimo del
  backend de Vector52 de uno fabricado por un tercero.

### Qué NO prueba este contrato

- Que el claim analizado por Vector52 sea cierto.
- Que la metodología de Contribution Analysis se haya aplicado
  correctamente.
- La integridad del contenido del paquete `.v52.zip` — eso lo prueba
  `POST /v1/verify` en el backend, comparando el hash recalculado contra
  `manifest_root`. El contrato solo certifica *cuándo* y *quién* ancló ese
  hash.
- Nada sobre la wallet investigada, el chain_id auditado o el veredicto:
  esos datos nunca llegan a HSK.

Ver [`SECURITY.md`](./SECURITY.md) para el modelo de amenazas, control de
acceso y gestión de llaves completos.

### Contrato

```
contracts/hsk/V52EvidenceRegistry.sol
```

- `anchorCase(manifestRoot, methodologyHash, schemaVersion, caseId, supersedes)`
  — solo direcciones `issuer` autorizadas. Revierte en root duplicado,
  root/caseId vacíos, o `supersedes` desconocido/auto-referenciado.
- `getAnchor(manifestRoot)` / `isAnchored(manifestRoot)` /
  `getLatestManifestRoot(caseId)` — lectura pública, sin restricciones.
- `setIssuer(address, bool)` / `transferOwnership(address)` — solo `owner`.
- Eventos: `CaseAnchored`, `CaseSuperseded`, `IssuerUpdated`,
  `OwnershipTransferred` — son la fuente que consumirá
  `v52-subgraph-hsk` para indexar `manifestRoot`, issuer, bloque,
  transacción, schema version y supersesión.

### Direcciones y chain IDs — HSK Testnet

| Campo | Valor |
|---|---|
| Red | HashKey Chain Testnet |
| Chain ID | `133` |
| RPC | `https://testnet.hsk.xyz` |
| Explorer | `https://testnet-explorer.hsk.xyz` |
| `V52EvidenceRegistry` | [`0x3422820Ef9FBC8e0206E4CBcB6369dBd14BE18c4`](https://testnet-explorer.hsk.xyz/address/0x3422820Ef9FBC8e0206E4CBcB6369dBd14BE18c4) |
| Deploy tx | [`0xe1fa572227cb85f0c944e7038cc66a684b7d21489fa1ff9532c770f2ea480782`](https://testnet-explorer.hsk.xyz/tx/0xe1fa572227cb85f0c944e7038cc66a684b7d21489fa1ff9532c770f2ea480782) |
| Deploy block | `33035699` |
| Owner / initial issuer | `0x0f26475928053737C3CCb143Ef9B28F8eDab04C7` |
| Verificación en explorer | **`NOT_VERIFIED`** — ver "Verificación de código" |

Registro completo en formato máquina: [`deployments/hsk-testnet.json`](./deployments/hsk-testnet.json).

**Transacción real de prueba (smoke test post-deploy):**
[`0xd97a0054d252bccbb17cbb4e4f0fc84cbd23eba4bbfc84fc9c40ccf03a8225fb`](https://testnet-explorer.hsk.xyz/tx/0xd97a0054d252bccbb17cbb4e4f0fc84cbd23eba4bbfc84fc9c40ccf03a8225fb)
ancla `manifest_root=0x2407b6f2529df3afbb2ab609cb236ff00b8421c7a57f78128ee58ed6d54f5005`
bajo `case_id=case_smoke_test_deploy_verification`. Puede consultarse con
`GET /v1/anchors/0x2407b6f2529df3afbb2ab609cb236ff00b8421c7a57f78128ee58ed6d54f5005`
contra el backend, o directamente:

```bash
cast call 0x3422820Ef9FBC8e0206E4CBcB6369dBd14BE18c4 \
  "getAnchor(bytes32)" \
  0x2407b6f2529df3afbb2ab609cb236ff00b8421c7a57f78128ee58ed6d54f5005 \
  --rpc-url https://testnet.hsk.xyz
```

**HSK Mainnet (chain 177):** objetivo declarado en
[`docs/PROYECTO-FINAL.md`](../docs/PROYECTO-FINAL.md); no desplegado
todavía. Testnet se usa aquí como contingencia mientras se confirma
financiamiento/issuer de producción — sección 13 de ese documento explica
el gate: *"HSK: contrato/anchor consultable → confirmar testnet por
escrito; no fingir Mainnet."*

### Verificación de código

HSK Testnet no expone hoy una API de verificación tipo Etherscan
confirmada para este deployment. Mientras tanto, cualquiera puede verificar
manualmente que el bytecode on-chain corresponde a este código fuente:

```bash
export PATH="$PATH:$HOME/.foundry/bin"
git clone https://github.com/v52-Chain/v52-onchain
cd v52-onchain && forge install && forge build

# Bytecode desplegado on-chain:
cast code 0x3422820Ef9FBC8e0206E4CBcB6369dBd14BE18c4 --rpc-url https://testnet.hsk.xyz

# Bytecode reproducido localmente (runtime code, comparar el sufijo tras el
# constructor args ABI-encoded al final del creation code):
cat out/V52EvidenceRegistry.sol/V52EvidenceRegistry.json | jq -r .deployedBytecode.object
```

Ambos deben coincidir byte a byte. El compilador usado fue
`solc 0.8.26`, optimizador activado, `200` runs, `evm_version = paris`
(ver `foundry.toml`).

---

## Avalanche

Contratos o adapters estrictamente necesarios para demostrar settlement
x402 y, si aporta al flujo real, un registro mínimo de capacidades del
servicio. **No implementado en este repositorio todavía.**

El estado real del facilitador x402 (OpenZeppelin Relayer) está
documentado en [`x402-test/README.md`](./x402-test/README.md): el plugin
oficial `relayer-plugin-x402-facilitator` anuncia soporte EVM en
`/supported` pero su `handleVerify`/`handleSettle` internos solo
implementan el caso `stellar`, por lo que las llamadas EVM devuelven hoy
`{"invalidReason":"unsupported_network","isValid":false}`. `V52ServiceRegistry`
no se despliega hasta que exista un facilitador que realmente liquide en
Avalanche.

---

## Desarrollo local (Foundry)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

git clone https://github.com/v52-Chain/v52-onchain
cd v52-onchain
forge install     # clona lib/forge-std (submódulo)
forge build
forge test -vv --gas-report
```

Estructura:

```
v52-onchain/
├── contracts/
│   └── hsk/V52EvidenceRegistry.sol
├── script/
│   └── DeployV52EvidenceRegistry.s.sol
├── test/
│   └── V52EvidenceRegistry.t.sol   # 43 tests: unit + fuzz (256 runs c/u)
├── deployments/
│   └── hsk-testnet.json
├── abi/
│   └── V52EvidenceRegistry.json     # ABI generado, versionado como artifact
├── x402-test/                       # programa de prueba x402 (ver su README)
├── foundry.toml
├── SECURITY.md
└── README.md
```

### Tests

`forge test` corre 43 tests contra `V52EvidenceRegistry`:

- Constructor: owner correcto, issuer inicial opcional, el owner **no** es
  issuer automáticamente.
- `setIssuer` / `transferOwnership`: control de acceso, eventos, reversión
  para no-owner y dirección cero.
- `anchorCase`: happy path (struct guardado, `isAnchored`,
  `latestManifestRootOf`, `anchorCount`, evento `CaseAnchored`),
  control de acceso (no-issuer, owner-no-issuer), validación de entradas
  (root/caseId vacíos, root duplicado — incluso entre distintos issuers),
  cadena de supersesión de 3 versiones con eventos `CaseSuperseded`.
- 3 tests de fuzzing (256 runs cada uno): root/caseId arbitrarios,
  llamante no-issuer arbitrario, allow-list controlada solo por el owner.

Ningún test toca red real — corren contra la EVM local de Foundry.

### Deploy

```bash
export PATH="$PATH:$HOME/.foundry/bin"

# La private key NUNCA se guarda en foundry.toml ni en un .env de este
# repo: se exporta en el shell desde el .env que ya la contiene.
KEY=$(python3 -c "print(open('x402-test/.env').read().strip().split('=',1)[1].strip())")

# Dry run (simulación, sin enviar tx):
PRIVATE_KEY="0x$KEY" forge script script/DeployV52EvidenceRegistry.s.sol:DeployV52EvidenceRegistry \
  --rpc-url hsk_testnet -vvvv

# Deploy real:
PRIVATE_KEY="0x$KEY" forge script script/DeployV52EvidenceRegistry.s.sol:DeployV52EvidenceRegistry \
  --rpc-url hsk_testnet --broadcast -vvvv
```

`INITIAL_ISSUER` es opcional (por defecto, el propio deployer). Para
producción, usar una wallet de deploy distinta de la wallet issuer/relayer
del backend — ver `SECURITY.md`.

### Interactuar con el contrato ya desplegado (`cast`)

Lectura (no requiere llave):

```bash
export PATH="$PATH:$HOME/.foundry/bin"
REGISTRY=0x3422820Ef9FBC8e0206E4CBcB6369dBd14BE18c4
RPC=https://testnet.hsk.xyz

# ¿Existe un anchor para este manifest_root?
cast call $REGISTRY "isAnchored(bytes32)(bool)" 0x<manifest_root> --rpc-url $RPC

# Registro completo (manifestRoot, methodologyHash, schemaVersion, caseId,
# issuer, blockNumber, timestamp, supersedes, exists):
cast call $REGISTRY "getAnchor(bytes32)" 0x<manifest_root> --rpc-url $RPC

# Último manifest_root anclado para un caseId:
cast call $REGISTRY "getLatestManifestRoot(string)(bytes32)" "case_..." --rpc-url $RPC

# ¿Una dirección está autorizada a anclar?
cast call $REGISTRY "issuers(address)(bool)" 0x<address> --rpc-url $RPC
```

Escritura (requiere ser un `issuer` autorizado y tener HSK para gas):

```bash
MANIFEST_ROOT=$(cast keccak "contenido a anclar")   # o sha256 real del manifest.json
METHOD_HASH=$(cast keccak "v52-contribution-0.1.0")

cast send $REGISTRY \
  "anchorCase(bytes32,bytes32,string,string,bytes32)" \
  "$MANIFEST_ROOT" "$METHOD_HASH" "0.1.0" "case_..." \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --private-key 0x<issuer_private_key> --rpc-url $RPC
```

El último argumento (`supersedes`) debe ser `bytes32(0)` para un primer
anchor, o el `manifest_root` anterior si se está reemplazando una versión.

En producción, esta escritura la realiza exclusivamente el backend de
Vector52 vía `POST /v1/cases/{case_id}/anchor` — ver
[`v52-backend/docs/API.md`](../v52-backend/docs/API.md) sección de HSK
Anchor y [`v52-backend/app/onchain/hsk_registry.py`](../v52-backend/app/onchain/hsk_registry.py).

### ABI

`abi/V52EvidenceRegistry.json` se regenera con:

```bash
forge inspect contracts/hsk/V52EvidenceRegistry.sol:V52EvidenceRegistry abi --json \
  > abi/V52EvidenceRegistry.json
```

`v52-backend` mantiene una copia vendorizada en
`app/onchain/abi/V52EvidenceRegistry.json` (debe resincronizarse
manualmente si el contrato cambia — no hay todavía un pipeline de
publicación de artifacts entre repos). `v52-subgraph-hsk` debe consumir
este mismo archivo como `abis/V52EvidenceRegistry.json`.

---

## Definition of Done

- [x] Direcciones y chain IDs publicados (testnet).
- [ ] Contratos verificados en explorador (bloqueado por disponibilidad de
      verificador HSK-compatible — ver "Verificación de código").
- [x] Tests y scripts reproducibles (`forge test`, `forge script`).
- [x] ABIs versionadas (`abi/V52EvidenceRegistry.json`).
- [x] Ninguna llave privada en el repositorio (se exporta desde `.env`
      gitignorado en tiempo de ejecución).
- [x] Transacciones reales enlazadas desde este README (deploy + smoke
      test).
