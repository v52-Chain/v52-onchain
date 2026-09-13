# Security — v52-onchain

Scope: `contracts/hsk/V52EvidenceRegistry.sol` and its deployment/operational
model. Avalanche contracts (`V52ServiceRegistry` / x402 settlement) are out
of scope for this document until they exist in this repository.

## Threat model

`V52EvidenceRegistry` anchors a cryptographic commitment of a Vector52
`.v52` forensic package. It is intentionally minimal:

- **What it stores on-chain:** `manifestRoot` (SHA-256 of `manifest.json`),
  `methodologyHash`, `schemaVersion`, a non-sensitive `caseId`, the issuer
  address, block number and timestamp, and an optional `supersedes`
  pointer.
- **What it never stores:** the manifest itself, raw evidence, wallet
  addresses under investigation, claim text, verdicts, or any personal
  data. A leaked or fully public HSK chain reveals nothing about the
  underlying case beyond "someone anchored this hash at this time."
- **What anchoring proves:** that a specific `manifest_root` existed and
  was committed by a specific issuer address at a specific block/time.
- **What anchoring does NOT prove:** that the claim inside the case is
  true, that the methodology was followed correctly, or that the issuer is
  trustworthy. Provenance ≠ correctness. `POST /v1/verify` (backend) proves
  package integrity against a manifest; the chain only proves *when* and
  *by whom* that manifest's hash was committed.

## Access control

- `owner` — set at deploy time to the deployer. Can call `setIssuer()` and
  `transferOwnership()`. The owner is **not** automatically an issuer and
  cannot call `anchorCase()` unless separately allow-listed.
- `issuers` — an explicit allow-list (`mapping(address => bool)`). Only
  allow-listed addresses can call `anchorCase()`. This is the key control:
  anyone reading the chain can verify *which* addresses were authorized to
  anchor at any point (via `IssuerUpdated` events), which matters for
  auditing whether an anchor came from the real Vector52 backend or an
  impostor.
- There is no upgradability, pausability or admin override on anchored
  data: once `anchorCase()` succeeds, that `Anchor` struct is immutable.
  The only way to "correct" a bad anchor is to anchor a new `manifestRoot`
  with `supersedes` pointing at the old one — the old anchor remains
  readable and attributed to whoever anchored it.

## Key management

- **Contract owner key:** used only for `setIssuer()` /
  `transferOwnership()`. Low-frequency, high-impact. Should eventually move
  to a multisig once the team has one; for the buildathon it is a single
  EOA controlled by Saúl.
- **Issuer key (backend relayer):** the Vector52 backend holds a private
  key configured as `HSK_ANCHOR_PRIVATE_KEY` and calls `anchorCase()` after
  building a `.v52` package (see `v52-backend/app/onchain/hsk_registry.py`).
  This key only needs enough native HSK to pay gas — it holds no other
  funds and has no special permissions beyond the allow-list entry.
- **Current testnet deployment** uses the same wallet for both the deploy
  transaction (owner) and the initial issuer, because it was also the
  wallet already funded on HSK testnet for `x402-test/` experiments (see
  `deployments/hsk-testnet.json`). Before any mainnet deployment: generate
  a dedicated deployer/owner key and a dedicated backend-relayer/issuer
  key, and never reuse a key across networks or roles.
- **Never commit a private key to this repository.** `.env` and
  `.env.local` are gitignored; `x402-test/.env` holds test-network keys
  only and must never hold mainnet funds.

## Known limitations (buildathon-stage, tracked honestly)

- **Not verified on a block explorer.** HSK testnet does not expose a
  confirmed Etherscan-compatible verification API at the time of this
  deployment. Bytecode/source match must currently be checked manually
  (see README.md "Verificación de código"). This is tracked as
  `NOT_VERIFIED` in `deployments/hsk-testnet.json`, not silently ignored.
- **Single point of failure for anchoring.** If the backend's
  `HSK_ANCHOR_PRIVATE_KEY` is lost or compromised, no new anchors can be
  submitted (lost key) or an attacker could anchor spam entries under a
  legitimate-looking issuer address (compromised key) — but could never
  forge history for an existing `manifestRoot`, since `anchorCase()`
  reverts (`AlreadyAnchored`) on any root that already exists. Rotate via
  `setIssuer(oldKey, false)` + `setIssuer(newKey, true)` from the owner key
  if a relayer key is suspected compromised.
- **No reentrancy risk.** `anchorCase()` makes no external calls and holds
  no funds; there is nothing to reenter.
- **No economic incentive/slashing.** Anchoring is free beyond gas — the
  x402 payment gating described in `docs/CONTRATO-INTEGRACION.md` for
  `POST /v1/cases/{case_id}/anchor` covers backend/gas-sponsorship
  economics, not on-chain security of this contract.

## Reporting

This is a buildathon project without a dedicated security contact yet. If
you find an issue, open a private security advisory on the
`v52-Chain/v52-onchain` GitHub repository rather than a public issue.
